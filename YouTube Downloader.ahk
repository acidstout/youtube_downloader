;@Ahk2Exe-SetName YouTube Downloader
;@Ahk2Exe-SetProductName YouTube Downloader
;@Ahk2Exe-SetDescription Einfach Videos von YouTube runterladen
;@Ahk2Exe-SetCompanyName Rekow IT
;@Ahk2Exe-SetCopyright Copyright © 2026 Rekow IT
;@Ahk2Exe-SetVersion 1.3.1
;@Ahk2Exe-SetLanguage 0x0807
#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

; =================== TODO ===================
;	- Modify RunOther() function to delete all local dependencies and trigger a re-download.
;

; ================== CONFIG ==================
; ---- Version requirement ----
global DENO_MIN_MAJOR := 2
global DENO_MIN_MINOR := 0   ; We require Deno version >= 2.0.x

; ---- URLs of dependencies ----
global DENO_URL     := "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip"
global FFMPEG_URL   := "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
global YTDLP_URL    := "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"

; ---- Local target folders of dependencies ----
global LOCAL_YTD    := A_AppData "\Programs\YouTube Downloader"
global LOCAL_DENO   := LOCAL_YTD "\deno.exe"
global LOCAL_FFMPEG := LOCAL_YTD "\ffmpeg.exe"
global LOCAL_YTDLP  := LOCAL_YTD "\yt-dlp.exe"
iniPath             := LOCAL_YTD "\settings.ini"
iniSection          := "UI"
iniKeyBrowser       := "Browser"
versionInfo         := "v1.3.1"

; ---- i18n ----
global LANG_DIR := A_ScriptDir "\lang"
global LANG_FALLBACK := "en"
global I18N := Map()
global I18N_MISSING := Map()
global I18N_DEBUG := true   ; set to false for release builds
global CUR_LANG := ""
global iniKeyLang := "Lang"


; Display name -> lang tag (file name)
; ---- Language discovery ----
global LANGS := Map()          ; DisplayName -> Code
global LANG_FILES := Map()     ; Code -> FullPath

InitLanguages() {
    global LANGS, LANG_FILES, LANG_DIR

    LANGS := Map()
    LANG_FILES := Map()

    tempList := []   ; array of { name, code }

    if !DirExist(LANG_DIR) {
        tempList.Push({ name: "English", code: "en" })
    } else {
        loop files LANG_DIR "\*.ini" {
            filePath := A_LoopFileFullPath
            code := RegExReplace(A_LoopFileName, "\.ini$", "")

            ; Read display name from file
            display := ""

            try display := IniRead(filePath, "meta", "name", "")
            if (display = "")
                display := IniRead(filePath, "strings", "app.title", "")
            if (display = "")
                display := code

            tempList.Push({ name: display, code: code })
            LANG_FILES[code] := filePath
        }
    }

	; --- Sort alphabetically by display name ---
	Loop tempList.Length {
		i := A_Index
		Loop tempList.Length - i {
			j := A_Index
			if (StrCompare(tempList[j].name, tempList[j+1].name) > 0) {
				tmp := tempList[j]
				tempList[j] := tempList[j+1]
				tempList[j+1] := tmp
			}
		}
	}
	
    ; --- Rebuild LANGS map in sorted order ---
    for item in tempList
        LANGS[item.name] := item.code
}

LangCodeToName(code) {
    global LANG_FILES

    if !LANG_FILES.Has(code)
        return code

    filePath := LANG_FILES[code]

    ; Preferred: [meta] name=Deutsch / English / ...
    try {
        name := IniRead(filePath, "meta", "name", "")
        if (name != "")
            return name
    }

    ; Fallback: use app title from [strings]
    try {
        title := IniRead(filePath, "strings", "app.title", "")
        if (title != "")
            return title
    }

    ; Final fallback: raw code
    return code
}
; ===========================================

InitLanguages()
; Load translations early so startup UI can use T()
EarlyInitI18N()

EarlyInitI18N() {
    global CUR_LANG, iniPath, iniSection, iniKeyLang, LANG_FALLBACK
    tag := IniRead(iniPath, iniSection, iniKeyLang, "")
    if (tag = "")
        tag := GuessOsLangTag()
    if !LangTagAvailable(tag)
        tag := LANG_FALLBACK
    if !LangTagAvailable(tag)
        tag := FirstAvailableLangTag()
    CUR_LANG := tag
    LoadI18N(tag)
}

OnExit(LogMissingTranslations)

; Check folders and permissions
try {
	if !DirExist(LOCAL_YTD) {
		DirCreate(LOCAL_YTD)
	}
} catch Error as err {
	MsgBox T("err.dep_folder", err.Message), T("app.title"), 0x10
}

installedDependencies := IniRead(iniPath, iniSection, "InstalledDependencies", "")

if (installedDependencies != "1") {
	CheckAndDownloadDependencies()
}

CheckAndDownloadDependencies() {
    global iniPath, iniSection

    ; ---- Progress GUI ----
    pg := ProgressGuiCreate(T("dep.pg.title"))
    pg.Update(0, T("dep.pg.start"))

    overallOk := true
    msg := ""

    r1 := EnsureDenoLocalOnly(pg)
    overallOk := overallOk && r1.ok
    msg .= T("dep.summary.deno", r1.ok ? T("dep.result.ok") : T("dep.result.fail"), r1.message)
	

    r2 := EnsureFfmpegLocalOnly(pg)
    overallOk := overallOk && r2.ok
    msg .= T("dep.summary.ffmpeg", r2.ok ? T("dep.result.ok") : T("dep.result.fail"), r2.message)

    r3 := EnsureYtdlpLocalOnly(pg)
    overallOk := overallOk && r3.ok
    msg .= T("dep.summary.ytdlp", r3.ok ? T("dep.result.ok") : T("dep.result.fail"), r3.message)

    pg.Update(100, overallOk ? T("dep.pg.done") : T("dep.pg.done_errors"))
    Sleep 350
    pg.Close()

    if (overallOk) {
        IniWrite("1", iniPath, iniSection, "InstalledDependencies")
    } else {
        ; Optional: show the summary in user's language
        ; MsgBox msg, T("app.title"), 0x10
        ; Or log it somewhere
    }
}
; =========================
; Simple progress GUI
; =========================
class ProgressGui {
	__New(title := "") {
        if (title = "")
            title := T("dep.pg.title")
			
        this.Gui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", title)
        this.Gui.MarginX := 12
        this.Gui.MarginY := 10
        this.Text := this.Gui.AddText("w420", "")
        this.Bar := this.Gui.AddProgress("w420 h18 -Smooth Range0-100", 0)
		hMenu := DllCall("GetSystemMenu", "ptr", this.Gui.Hwnd, "int", false, "ptr")
		DllCall("EnableMenuItem", "ptr", hMenu, "uint", 0xF060, "uint", 0x00000001) ; SC_CLOSE + MF_GRAYED
        this.Gui.Show("AutoSize")
    }

    Update(pct, status) {
        try this.Bar.Value := pct
        try this.Text.Value := status
        Sleep 10
    }

    Close() {
        try this.Gui.Destroy()
    }
}

ProgressGuiCreate(title) {
    return ProgressGui(title)
}


; Read last selection (default = 1)
last := IniRead(iniPath, iniSection, iniKeyBrowser, "1")
last := (last ~= "^[1234]$") ? Integer(last) : 1

; Read fallback browser version
fallbackVersion := IniRead(iniPath, iniSection, "Version", "")
if (fallbackVersion == "") {
	fallbackVersion := "143.0.0.0"
	SaveFallbackVersion(fallbackVersion)
}

; ---------- GUI ----------
mainGui := Gui("+Resize +MinSize500x360", T("app.title"))
mainGui.MarginX := 12
mainGui.MarginY := 12
mainGui.SetFont("s10", "Segoe UI")
; mainGui.Opt("+E0x02000000")  ; WS_EX_COMPOSITED: Use compositing, which might be sluggish and therefore is commented out.

; Language picker (bottom-right, positioned in OnGuiSize)
langItems := []
for dispName, _ in LANGS
    langItems.Push(dispName)

ddlLang := mainGui.AddDropDownList("w170", langItems)
ddlLang.OnEvent("Change", LangChanged)
InitLanguage(ddlLang)

; Add radio-buttons for browser selection
grp := mainGui.Add("GroupBox", "x10 y10 w360 h48", T("grp.cookies"))
r1     := mainGui.Add("Radio", "x20 y30",  "Chrome")
r2     := mainGui.Add("Radio", "xp+90 yp", "Edge")
r3     := mainGui.Add("Radio", "xp+90 yp", "Firefox")
r4     := mainGui.Add("Radio", "xp+90 yp", "<Nichts>")
radios := [r1, r2, r3, r4]
radios[last].Value := 1   ; restore last selection

; Save on change
for r in [r1, r2, r3, r4] {
    r.OnEvent("Click", SaveSettings)
}

lblUrls := mainGui.AddText(, T("lbl.urls"))
urlsEdit := mainGui.AddEdit("vUrls WantTab Multi -Wrap VScroll")

lblLog := mainGui.AddText(, T("lbl.log"))
logEdit := mainGui.AddEdit("ReadOnly +Multi -Wrap HScroll VScroll vLog")

statusLeft := mainGui.AddText(, T("status.ready"))
statusRight := mainGui.AddText(, versionInfo)
statusRight.Opt("+Right")
statusRight.OnEvent("Click", ShowAbout)

btnRunUrls  := mainGui.AddButton(, "Download")
btnOther    := mainGui.AddButton(, "Update")
btnClearLog := mainGui.AddButton(, T("btn.clearlog"))

; Apply i18n translation
ApplyUiText()

btnRunUrls.OnEvent("Click", RunUrls)
btnOther.OnEvent("Click", RunOther)
btnClearLog.OnEvent("Click", (*) => (
    logEdit.Value := ""
))

; Handle resize so widths/heights track the window
mainGui.OnEvent("Size", OnGuiSize)

; Save settings only on close
mainGui.OnEvent("Close", (*) => (
    IniWrite(GetSelected(), iniPath, iniSection, iniKeyBrowser),
    ExitApp()
))

mainGui.Show("w900 h600")
return

; ---------- Layout ----------
OnGuiSize(thisGui, minMax, newW, newH) {
	global lblUrls, urlsEdit, lblLog, logEdit, statusLeft, statusRight, btnRunUrls, btnOther, btnClearLog, ddlLang

    if (minMax = -1) ; minimized
        return

	GuiSetRedraw(thisGui.Hwnd, 0)

	try {
		mX := thisGui.MarginX
		mY := thisGui.MarginY
		gap := 8

		; Available client area (approx; good enough for consistent layout)
		clientW := newW
		clientH := newH

		usableW := clientW - 2*mX
		if (usableW < 200)
			usableW := 200

		; Button sizes (same width)
		btnH := 30
		btnW := 120     ; pick any width you like
		btnGap := 10

		; Bottom strip: buttons + status
		bottomNeededH := btnH + gap + 20  ; status line height ~20
		topY := mY

		; Compute remaining height for the two edit fields + labels
		; Labels take ~20 each. We'll allocate dynamically.
		labelH := 20

		remainingH := clientH - (mY) - bottomNeededH - (labelH*2) - (gap*4)
		if (remainingH < 120)
			remainingH := 120

		; Enforce ratio: log = urls/3, so total = urls + urls/3 = (4/3)urls => urls = 3/4 total
		urlsH := Floor(remainingH * 3 / 4)
		logH  := Floor(remainingH / 5)

		; --- Place controls ---
		x := mX
		y := topY

		lblUrls.Move(x, y, usableW, labelH)
		y += labelH + gap

		urlsEdit.Move(x, y, usableW, urlsH)
		y += urlsH + gap

		lblLog.Move(x, y, usableW, labelH)
		y += labelH + gap

		logEdit.Move(x, y, usableW, logH)
		y += logH + gap + 20

		; Buttons at the bottom
		btnY := clientH - mY - btnH - 36 - gap  ; leave room for status below
		if (btnY < y)
			btnY := y

		; Keep buttons at their absolute position on window resize.
		rightX := x + usableW

		; right-aligned pair
		btnOtherX   := rightX - btnW
		btnRunUrlsX := btnOtherX - btnGap - btnW
		btnClearLogX := btnRunUrlsX - btnGap - btnW

		btnRunUrls.Move(btnRunUrlsX, btnY, btnW, btnH)
		btnOther.Move(btnOtherX, btnY, btnW, btnH)
		btnClearLog.Move(btnClearLogX, btnY, btnW, btnH)

		; Status line below buttons
		statusY := btnY + btnH + gap

		ddlW := 170
		statusRightW := 90
		statusGap := 10
		ddlGap := 10

		; Put language picker at the far right
		ddlLang.Move(x + usableW - ddlW, statusY - 2, ddlW)

		; Version text just left of the language picker
		statusRight.Move(x + usableW - ddlW - ddlGap - statusRightW, statusY, statusRightW, 20)

		; Left status uses remaining space
		statusLeft.Move(x, statusY, usableW - ddlW - ddlGap - statusRightW - statusGap, 20)
		
		; Position radio-buttons and GroupBox
		marginLeft   := 13
		marginBottom := 30   ; move group box higher from bottom

		grpW := 360
		grpH := 48

		x := marginLeft
		y := newH - marginBottom - grpH

		; Move group box
		grp.Move(x, y, grpW, grpH)

		; Place radios inside group box
		radioY := y + 22
		radioX := x + 10
		spacingX := 90

		r1.Move(radioX, radioY)
		r2.Move(radioX + spacingX, radioY)
		r3.Move(radioX + spacingX*2, radioY)
		r4.Move(radioX + spacingX*3, radioY)
	} finally {
		GuiSetRedraw(thisGui.Hwnd, 1)
		GuiForceRedraw(thisGui.Hwnd)
	}
}

; ---------- Actions ----------
ApplyUiText() {
    global mainGui, grp, lblUrls, lblLog, statusLeft
    global btnRunUrls, btnOther, btnClearLog

    mainGui.Title := T("app.title")
    grp.Text := T("grp.cookies")
    lblUrls.Text := T("lbl.urls")
    lblLog.Text := T("lbl.log")
    statusLeft.Text := T("status.ready")

    btnRunUrls.Text := T("btn.download")
    btnOther.Text := T("btn.update")
    btnClearLog.Text := T("btn.clearlog")
}

LangChanged(*) {
    global ddlLang, LANGS, CUR_LANG, iniPath, iniSection, iniKeyLang

    disp := ddlLang.Text
    tag := LANGS.Has(disp) ? LANGS[disp] : "en"
    if (tag = CUR_LANG)
        return

    CUR_LANG := tag
    IniWrite(tag, iniPath, iniSection, iniKeyLang)
    LoadI18N(tag)
    ApplyUiText()
}

ShowAbout(*) {
    global versionInfo
    MsgBox T("about.text", versionInfo), T("about.title"), 0x40
}

SaveSettings(*) {
	global last, iniPath, iniSection, iniKeyBrowser
	last := GetSelected()
	IniWrite(last, iniPath, iniSection, iniKeyBrowser)
}

SaveFallbackVersion(fallbackVersion) {
	global iniPath, iniSection
	IniWrite(fallbackVersion, iniPath, iniSection, "Version")
}

RunUrls(*) {
    global urlsEdit, statusLeft, logEdit, LOCAL_YTDLP, last

	downloadsDir := GetDownloadsDir()
	
	try {
		if !DirExist(downloadsDir) {
			DirCreate(downloadsDir)
		}
	} catch Error as err {
		MsgBox T("err.downloads_folder", err.Message), T("app.title"), 0x10
	}
	
	switch last {
		case 1:
			cookiesFromBrowser := "--cookies-from-browser chrome"
		case 2:
			cookiesFromBrowser := "--cookies-from-browser edge"
		case 3:
			cookiesFromBrowser := "--cookies-from-browser firefox"
		default:
			cookiesFromBrowser := ""
	}
	
    urls := ParseUrls(urlsEdit.Value)
    if (urls.Length = 0) {
        MsgBox T("err.no_urls"), T("app.title"), 0x30
        return
    }
    if !FileExist(LOCAL_YTDLP) {
        MsgBox T("err.ytdlp_missing", LOCAL_YTDLP), T("app.title"), 0x10
        return
    }

    SetBusy(true)
    AppendLog(logEdit, T("log.download_started", FormatTime(, "yyyy-MM-dd HH:mm:ss")) "`r`n")

    ok := 0
    for idx, url in urls {
        statusLeft.Value := T("status.downloading", idx, urls.Length, url)
        AppendLog(logEdit, "[" idx "/" urls.Length "] " url "`r`n")

        ; Run yt-dlp.exe
		cmd := LOCAL_YTDLP " " cookiesFromBrowser " --buffer-size 64K --http-chunk-size 1M --windows-filenames --concurrent-fragments 10 -o %(fulltitle)s.%(ext)s " url
        exitCode := RunWait(cmd, downloadsDir, "Hide")

        if (exitCode = 0) {
            ok++
            AppendLog(logEdit, T("log.item_ok") "`r`n")
        } else {
            AppendLog(logEdit, T("log.item_error", exitCode) "`r`n")
        }
    }

    statusLeft.Value := T("status.finished", ok, urls.Length)
	AppendLog(logEdit, T("log.download_done", ok, urls.Length) "`r`n")
    SetBusy(false)
}

RunOther(*) {
    global YTDLP_URL, statusLeft, logEdit, LOCAL_YTDLP

    SetBusy(true)
	statusLeft.Value := T("status.update")
	AppendLog(logEdit, T("log.update_header", FormatTime(, "yyyy-MM-dd HH:mm:ss")) "`r`n")

    if !FileExist(LOCAL_YTDLP) {
        AppendLog(logEdit, T("log.ytdlp_missing_try_download", LOCAL_YTDLP))
		url := YTDLP_URL

		try {
			HttpDownload(url, LOCAL_YTDLP)
			statusLeft.Value := T("status.done")
			AppendLog(logEdit, T("log.item_ok") "`r`n")
		} catch as e {
			statusLeft.Value := T("status.error")
			AppendLog(logEdit, "  -> " e.Message "`r`n")
		}
    } else {
		cmd := LOCAL_YTDLP " -U"
		exitCode := RunWait(cmd, LOCAL_YTD, "Hide")

		if (exitCode = 0) {
			statusLeft.Value := T("status.done")
			AppendLog(logEdit, T("log.item_ok") "`r`n")
		} else {
			statusLeft.Value := T("status.error")
			AppendLog(logEdit, "  -> " exitCode "`r`n")
		}
	}
	
	if FileExist(LOCAL_YTDLP ":Zone.Identifier") {
		zone := LOCAL_YTDLP ":Zone.Identifier"

		try {
			FileDelete zone
			AppendLog(logEdit, T("log.file_marked_safe"))
		} catch {
			AppendLog(logEdit, T("log.file_already_safe"))
		}
	}
	
    SetBusy(false)
}

; ---------- Helpers ----------
ParseUrls(text) {
    urls := []
    for line in StrSplit(text, "`n") {
        line := Trim(line, "`r`t ")
        if (line = "")
            continue
        if (SubStr(line, 1, 1) = "#")
            continue
        urls.Push(line)
    }
    return urls
}

SetBusy(isBusy) {
    global btnRunUrls, btnOther
    btnRunUrls.Enabled := !isBusy
    btnOther.Enabled := !isBusy
}


; Append to log with auto-scrolling.
AppendLog(ctrl, text) {
    ctrl.Value .= text

    ; Move caret to end
    len := StrLen(ctrl.Value)
    SendMessage(0x00B1, len, len, ctrl.Hwnd)  ; EM_SETSEL

    ; Scroll caret into view
    SendMessage(0x00B7, 0, 0, ctrl.Hwnd)      ; EM_SCROLLCARET
}


; Fix flickering in GUI when resizing window.
GuiSetRedraw(hWnd, enable) {
    ; WM_SETREDRAW = 0xB
    DllCall("SendMessage", "ptr", hWnd, "uint", 0xB, "ptr", enable, "ptr", 0)
}

GuiForceRedraw(hWnd) {
    ; RedrawWindow flags: invalidate|erase|allchildren = 0x0001|0x0004|0x0080
    DllCall("RedrawWindow", "ptr", hWnd, "ptr", 0, "ptr", 0, "uint", 0x0001|0x0004|0x0080)
}


; Get user's Downloads folder
GetDownloadsDir() {
    ; FOLDERID_Downloads = 374DE290-123F-4565-9164-39C4925E467B
    static DownloadsGuid := "{374DE290-123F-4565-9164-39C4925E467B}"

    pPath := 0
    hr := DllCall("Shell32\SHGetKnownFolderPath"
        , "ptr", GUIDFromString(DownloadsGuid)
        , "uint", 0
        , "ptr", 0
        , "ptr*", &pPath)

    if (hr = 0 && pPath != 0) {
        path := StrGet(pPath, "UTF-16")
        DllCall("Ole32\CoTaskMemFree", "ptr", pPath)
        return path
    }

    ; Fallback: %USERPROFILE%\Downloads
    userProfile := EnvGet("USERPROFILE")
    return userProfile != ""
        ? userProfile "\Downloads"
        : LOCAL_YTD "\Downloads"
}

GUIDFromString(guidStr) {
    buf := Buffer(16, 0)
    hr := DllCall("Ole32\CLSIDFromString", "wstr", guidStr, "ptr", buf)
    if (hr != 0)
        throw Error(T("err.invalid_guid", guidStr))
    return buf
}


; Get file version
GetFileVersion(filePath) {
    size := DllCall("Version\GetFileVersionInfoSizeW"
        , "WStr", filePath
        , "UInt*", &dummy := 0
        , "UInt")

    if !size
        throw Error("No version info found")

    buf := Buffer(size)

    if !DllCall("Version\GetFileVersionInfoW"
        , "WStr", filePath
        , "UInt", 0
        , "UInt", size
        , "Ptr", buf.Ptr)
        throw Error("GetFileVersionInfo failed")

    ; Query VS_FIXEDFILEINFO
    if !DllCall("Version\VerQueryValueW"
        , "Ptr", buf.Ptr
        , "WStr", "\"
        , "Ptr*", &ffi := 0
        , "UInt*", &ffiLen := 0)
        throw Error("VerQueryValue failed")

    ; VS_FIXEDFILEINFO.dwFileVersionMS / LS
    major := (NumGet(ffi, 8,  "UInt") >> 16) & 0xFFFF
    minor := (NumGet(ffi, 8,  "UInt"))        & 0xFFFF
    build := (NumGet(ffi, 12, "UInt") >> 16) & 0xFFFF
    rev   := (NumGet(ffi, 12, "UInt"))        & 0xFFFF

    return major "." minor "." build "." rev
}

; Get user's browser user-agent
GetBrowserUserAgent() {
    global logEdit, last, fallbackVersion

    userAgentChrome1  := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/"
    userAgentChrome2  := " Safari/537.36"

    userAgentFirefox1 := "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:"
    userAgentFirefox2 := ") Gecko/20100101"

    browserVersion := fallbackVersion
    userAgentPart1 := userAgentChrome1
    userAgentPart2 := userAgentChrome2
    userAgentPart3 := ""

    browserFile := ""

    switch last {
        case 1:
            ; Chrome
            userAgentPart1 := userAgentChrome1
            userAgentPart2 := userAgentChrome2
            userAgentPart3 := ""
            try {
				browserFile := RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe", "")
			} catch {
				AppendLog(logEdit, T("log.browser_not_found", "Chrome") "`r`n")
			}

        case 2:
            ; Edge
            userAgentPart1 := userAgentChrome1
            userAgentPart2 := userAgentChrome2
            userAgentPart3 := " Edg/"
            try {
				browserFile := RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe", "")
			} catch {
				AppendLog(logEdit, T("log.browser_not_found", "Edge") "`r`n")
			}

        case 3:
            ; Firefox
            userAgentPart1 := userAgentFirefox1
            userAgentPart2 := userAgentFirefox2
            userAgentPart3 := "Firefox/"
            try {
				browserFile := RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe", "")
			} catch {
				AppendLog(logEdit, T("log.browser_not_found", "Firefox") "`r`n")
			}

        default:
            browserFile := ""
    }

    if (browserFile != "") {
        AppendLog(logEdit, T("log.browser_found", browserFile) "`r`n")
        try {
            browserVersion := GetFileVersion(browserFile)
        } catch as e {
            AppendLog(logEdit, T("log.ua_detect_failed_using_fallback") "`r`n")
        }
    }

    ; Append Edge version if we have Edge.
    if (userAgentPart3 != "")
        userAgentPart3 .= browserVersion

    if (browserVersion != "") {
        SaveFallbackVersion(browserVersion)
        browserVersion := userAgentPart1 browserVersion userAgentPart2 userAgentPart3
    } else {
        AppendLog(logEdit, T("log.ua_unknown_version", browserVersion) "`r`n")
        browserVersion := userAgentChrome1 fallbackVersion userAgentChrome2
    }

    AppendLog(logEdit, T("log.ua", browserVersion) "`r`n")
    return browserVersion
}

; Download helper
HttpDownload(url, savePath) {
    userAgent := GetBrowserUserAgent()

    ; Ensure target directory exists
    SplitPath savePath, , &dir
    if (dir) {
        try {
			DirCreate dir
		} catch as e {
			throw Error(T("err.create_dir_failed", dir, e.Message))
		}
	}

    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.Option[6] := true ; Enable redirects
    req.Open("GET", url, false)
    req.SetRequestHeader("User-Agent", userAgent)
    req.Send()
    req.WaitForResponse()

    status := req.Status
    if (status < 200 || status >= 300)
        throw Error(T("err.http_error", status, req.StatusText, url))

    stream := ComObject("ADODB.Stream")
    stream.Type := 1 ; binary
    stream.Open()
    stream.Write(req.ResponseBody)
    stream.SaveToFile(savePath, 2) ; overwrite
    stream.Close()
}

; Get selected radio-button to save in settings
GetSelected() {
    if (r1.Value)
        return 1
    if (r2.Value)
        return 2
	if (r3.Value)
		return 3
	return 4
}


; =========================
; Deno (local-only)
; =========================
EnsureDenoLocalOnly(pg) {
    global DENO_URL, LOCAL_DENO, DENO_MIN_MAJOR, DENO_MIN_MINOR
    pg.Update(5, T("dep.step.search_deno"))

    if FileExist(LOCAL_DENO) {
        WaitForFileStable(LOCAL_DENO, 10000)
        v := TryRunDenoVersion(LOCAL_DENO)
        if v.ok && VersionAtLeast(v.major, v.minor, DENO_MIN_MAJOR, DENO_MIN_MINOR) {
            pg.Update(50, T("dep.step.ok_deno"))
            return { ok: true, message: T("dep.msg.found", LOCAL_DENO, v.major "." v.minor "." v.patch) }
        }
    }

    pg.Update(10, T("dep.step.download_deno"))
    tempZip := A_Temp "\deno_" A_TickCount ".zip"
    if !SilentDownload(DENO_URL, tempZip) {
        pg.Update(33, T("dep.step.download_failed_deno"))
        return { ok: false, message: T("dep.msg.download_failed", "Deno", DENO_URL) }
    }

    pg.Update(20, T("dep.step.install_deno"))
    try {
        if FileExist(LOCAL_DENO)
            FileDelete(LOCAL_DENO)
        ExtractSingleFileFromZipShell(tempZip, LOCAL_YTD, "deno.exe", 100000)
    } catch as e {
        try FileDelete(tempZip)
        pg.Update(33, T("dep.step.install_failed_deno"))
        return { ok: false, message: T("dep.msg.install_failed", "Deno", e.Message) }
    }
    try FileDelete(tempZip)

    pg.Update(25, T("dep.step.validate_deno"))
    WaitForFileStable(LOCAL_DENO, 10000)
    v2 := TryRunDenoVersion(LOCAL_DENO)

    if !v2.ok {
        pg.Update(33, T("dep.step.validate_failed_deno"))
        return { ok: false, message: T("dep.msg.validate_failed", "Deno", v2.message) }
    }

    if !VersionAtLeast(v2.major, v2.minor, DENO_MIN_MAJOR, DENO_MIN_MINOR) {
        pg.Update(33, T("dep.step.too_old_deno"))
        return { ok: false
               , message: T("dep.msg.too_old"
                           , "Deno"
                           , v2.major "." v2.minor "." v2.patch
                           , DENO_MIN_MAJOR "." DENO_MIN_MINOR ".0") }
    }

    pg.Update(33, T("dep.step.installed_deno"))
    return { ok: true
           , message: T("dep.msg.installed"
                       , "Deno"
                       , LOCAL_DENO
                       , v2.major "." v2.minor "." v2.patch) }
}

TryRunDenoVersion(denoPath) {
    exec := ExecCaptureCP(denoPath, "--version", 4000)

    if (exec.timedOut)
        return { ok: false, message: T("err.timeout", 4000) }

    stdtext := Trim(exec.stdout) != "" ? exec.stdout : exec.stderr
    if (Trim(stdtext) = "")
        return { ok: false, message: T("err.no_output_exitcode", exec.exitCode) }

    for line in StrSplit(stdtext, "`n", "`r") {
        line := Trim(line)
        if RegExMatch(line, "i)^deno\s+(\d+)\.(\d+)\.(\d+)", &m)
            return { ok: true, major: Integer(m[1]), minor: Integer(m[2]), patch: Integer(m[3]) }
    }

    return { ok: false, message: T("err.parse_version_failed", exec.exitCode, stdtext) }
}

; =========================
; FFmpeg (local-only, extract ONLY ffmpeg.exe)
; =========================
EnsureFfmpegLocalOnly(pg) {
    global FFMPEG_URL, LOCAL_FFMPEG

    pg.Update(34, T("dep.step.search_ffmpeg"))

    if FileExist(LOCAL_FFMPEG) {
        WaitForFileStable(LOCAL_FFMPEG, 10000)
        r := TryRunFfmpeg(LOCAL_FFMPEG)
        if r.ok {
            pg.Update(66, T("dep.step.ok_ffmpeg"))
            return { ok: true, message: T("dep.msg.found", LOCAL_FFMPEG, r.message) }
        }
        ; broken => reinstall
    }

    pg.Update(40, T("dep.step.download_ffmpeg"))
    tempZip := A_Temp "\ffmpeg_" A_TickCount ".zip"
    if !SilentDownload(FFMPEG_URL, tempZip) {
        pg.Update(66, T("dep.step.download_failed_ffmpeg"))
        return { ok: false, message: T("dep.msg.download_failed", "FFmpeg", FFMPEG_URL) }
    }

    pg.Update(50, T("dep.step.install_ffmpeg"))
    try {
        if FileExist(LOCAL_FFMPEG)
            FileDelete(LOCAL_FFMPEG)
        ExtractSingleFileFromZipShell(tempZip, LOCAL_YTD, "ffmpeg.exe", 100000)
    } catch as e {
        try FileDelete(tempZip)
        pg.Update(66, T("dep.step.install_failed_ffmpeg"))
        return { ok: false, message: T("dep.msg.install_failed", "FFmpeg", e.Message) }
    }
    try FileDelete(tempZip)

    pg.Update(60, T("dep.step.validate_ffmpeg"))
    WaitForFileStable(LOCAL_FFMPEG, 10000)
    r2 := TryRunFfmpeg(LOCAL_FFMPEG)

    if r2.ok {
        pg.Update(66, T("dep.step.installed_ffmpeg"))
        return { ok: true, message: T("dep.msg.installed", "FFmpeg", LOCAL_FFMPEG, r2.message) }
    }

    pg.Update(66, T("dep.step.validate_failed_ffmpeg"))
    return { ok: false, message: T("dep.msg.validate_failed", "FFmpeg", r2.message) }
}

TryRunFfmpeg(ffmpegPath) {
    exec := ExecCaptureCP(ffmpegPath, "-version", 4000)

    if (exec.timedOut)
        return { ok: false, message: T("err.timeout", 4000) }

    stdtext := Trim(exec.stdout) != "" ? exec.stdout : exec.stderr
    if (Trim(stdtext) = "")
        return { ok: false, message: T("err.no_output_exitcode", exec.exitCode) }

    firstLine := ""
    for line in StrSplit(stdtext, "`n", "`r") {
        line := Trim(line)
        if (line != "") {
            firstLine := line
            break
        }
    }

    if RegExMatch(firstLine, "i)^ffmpeg\s+version\b")
        return { ok: true, message: firstLine }

    return { ok: false, message: T("err.unexpected_output", exec.exitCode, stdtext) }
}


; =========================
; yt-dlp (local-only)
; =========================
EnsureYtdlpLocalOnly(pg) {
    global YTDLP_URL, LOCAL_YTDLP

    pg.Update(67, T("dep.step.search_ytdlp"))

    if FileExist(LOCAL_YTDLP) {
        WaitForFileStable(LOCAL_YTDLP, 10000)
        r := TryRunYtdlp(LOCAL_YTDLP)
        if r.ok {
            pg.Update(100, T("dep.step.ok_ytdlp"))
            return { ok: true
                   , message: T("dep.msg.found", LOCAL_YTDLP, r.message) }
        }
        ; broken => reinstall
    }

    pg.Update(70, T("dep.step.download_ytdlp"))
    tempFile := A_Temp "\ytdlp_" A_TickCount ".exe"
    if !SilentDownload(YTDLP_URL, tempFile) {
        pg.Update(100, T("dep.step.download_failed_ytdlp"))
        return { ok: false
               , message: T("dep.msg.download_failed", "yt-dlp", YTDLP_URL) }
    }

    pg.Update(80, T("dep.step.install_ytdlp"))
    try {
        if FileExist(LOCAL_YTDLP)
            FileDelete(LOCAL_YTDLP)
        MoveYtdlpFromTemp(tempFile)
    } catch as e {
        try FileDelete(tempFile)
        pg.Update(100, T("dep.step.install_failed_ytdlp"))
        return { ok: false
               , message: T("dep.msg.install_failed", "yt-dlp", e.Message) }
    }
    try FileDelete(tempFile)

    pg.Update(95, T("dep.step.validate_ytdlp"))
    WaitForFileStable(LOCAL_YTDLP, 10000)
    r2 := TryRunYtdlp(LOCAL_YTDLP)

    if r2.ok {
        pg.Update(100, T("dep.step.installed_ytdlp"))
        return { ok: true
               , message: T("dep.msg.installed", "yt-dlp", LOCAL_YTDLP, r2.message) }
    }

    pg.Update(100, T("dep.step.validate_failed_ytdlp"))
    return { ok: false
           , message: T("dep.msg.validate_failed", "yt-dlp", r2.message) }
}

TryRunYtdlp(ytdlpPath) {
    exec := ExecCaptureCP(ytdlpPath, "--version", 4000)

    if (exec.timedOut)
        return { ok: false, message: T("err.timeout", 4000) }

    stdtext := Trim(exec.stdout) != "" ? exec.stdout : exec.stderr
    if (Trim(stdtext) = "")
        return { ok: false, message: T("err.no_output_exitcode", exec.exitCode) }

    firstLine := ""
    for line in StrSplit(stdtext, "`n", "`r") {
        line := Trim(line)
        if (line != "") {
            firstLine := line
            break
        }
    }

    if RegExMatch(firstLine, "^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$")
        return { ok: true, message: firstLine }

    return { ok: false
           , message: T("err.unexpected_output", exec.exitCode, stdtext) }
}


; =========================
; Silent download helper
; =========================
SilentDownload(url, outPath) {
    try {
        if FileExist(outPath)
            FileDelete(outPath)
        Download(url, outPath)
        if !FileExist(outPath)
            return false

        UnblockFile(outPath) ; important: remove MOTW from ZIP
        return true
    } catch {
        return false
    }
}


MoveYtdlpFromTemp(sourceFile, timeoutMs := 120000) {
    global LOCAL_YTDLP

    start := A_TickCount
    while !FileExist(sourceFile) {
        if (A_TickCount - start > timeoutMs)
            throw Error(T("err.wait_download_timeout", sourceFile, timeoutMs))
        Sleep 100
    }

    ; Ensure it is fully written, then unblock it (prevents SmartScreen hang)
    WaitForFileStable(sourceFile, timeoutMs)
    UnblockFile(sourceFile)

    try {
        FileMove(sourceFile, LOCAL_YTDLP, true)
    } catch Error as e {
        throw Error(T("err.install_failed_with_reason", "yt-dlp", e.Message))
    }
}


; =========================
; ZIP: extract ONLY one file using Shell COM (no PowerShell, minimal UI)
; =========================
ExtractSingleFileFromZipShell(zipPath, destDir, fileName, timeoutMs := 120000) {
    if !FileExist(zipPath)
        throw Error(T("err.zip_not_found", zipPath))

    if !DirExist(destDir) {
        try DirCreate(destDir)
        catch as e
            throw Error(T("err.create_dir_failed", destDir, e.Message))
    }

    app := ComObject("Shell.Application")

    zipNs := app.NameSpace(zipPath)
    if !zipNs
        throw Error(T("err.zip_open_failed", zipPath))

    dstNs := app.NameSpace(destDir)
    if !dstNs
        throw Error(T("err.dest_open_failed", destDir))

    item := FindZipItemRecursive(zipNs, fileName)
    if !item
        throw Error(T("err.zip_item_not_found", fileName, zipPath))

    ; 16|4 = No UI + No progress dialog (best-effort).
    dstNs.CopyHere(item, 16|4)

    ; Wait until the file appears
    target := destDir "\" fileName
    start := A_TickCount
    while !FileExist(target) {
        if (A_TickCount - start > timeoutMs)
            throw Error(T("err.wait_extract_timeout", target, timeoutMs))
        Sleep 100
    }

    ; Ensure it is fully written, then unblock it (prevents SmartScreen hang)
    WaitForFileStable(target, timeoutMs)
    UnblockFile(target)
}

FindZipItemRecursive(folderNs, fileName) {
    items := folderNs.Items
    if !items
        return 0

    for item in items {
        try {
            if (StrLower(item.Name) = StrLower(fileName))
                return item

            if item.IsFolder {
                subFolder := item.GetFolder
                if subFolder {
                    found := FindZipItemRecursive(subFolder, fileName)
                    if found
                        return found
                }
            }
        } catch {
            ; ignore and continue
        }
    }
    return 0
}

UnblockFile(path) {
    ; Removes Mark-of-the-Web if present
    try {
		FileDelete(path ":Zone.Identifier")
	} catch {
		; Nothing
	}
}

WaitForFileStable(path, timeoutMs := 15000) {
    start := A_TickCount
    lastSize := -1
    stableFor := 0

    while (A_TickCount - start < timeoutMs) {
        if !FileExist(path) {
            Sleep 100
            continue
        }

        size := FileGetSize(path)
        if (size = lastSize && size > 0) {
            stableFor += 200
            if (stableFor >= 800) ; stable for ~0.8s
                return true
        } else {
            stableFor := 0
            lastSize := size
        }
        Sleep 200
    }
    return false
}

; =========================
; Version compare (major/minor only is enough for >= 2.0.0 requirement)
; =========================
VersionAtLeast(maj, min, reqMaj, reqMin) {
    if (maj > reqMaj)
        return true
    if (maj < reqMaj)
        return false
    return (min >= reqMin)
}


; =========================
; Exec capture (silent)
; =========================
ExecCaptureCP(exePath, args := "", timeoutMs := 5000) {
    ; Runs exePath directly (no cmd.exe), captures stdout/stderr, no window.
    ; Returns: { exitCode, stdout, stderr, timedOut }

    ; ---- Build command line (CreateProcess requires mutable command line) ----
    cmdLine := '"' exePath '"'
    if (args != "")
        cmdLine .= " " args

    ; ---- Create pipes for stdout and stderr ----
    sa := Buffer(A_PtrSize = 8 ? 24 : 12, 0) ; SECURITY_ATTRIBUTES
    NumPut("UInt", sa.Size, sa, 0)
    NumPut("Int", 1, sa, A_PtrSize = 8 ? 16 : 8) ; bInheritHandle = TRUE

    hOutR := 0, hOutW := 0
    hErrR := 0, hErrW := 0

    if !DllCall("CreatePipe", "Ptr*", &hOutR, "Ptr*", &hOutW, "Ptr", sa, "UInt", 0)
        return { exitCode: 1, stdout: "", stderr: "CreatePipe stdout failed", timedOut: false }

    if !DllCall("CreatePipe", "Ptr*", &hErrR, "Ptr*", &hErrW, "Ptr", sa, "UInt", 0) {
        DllCall("CloseHandle", "Ptr", hOutR), DllCall("CloseHandle", "Ptr", hOutW)
        return { exitCode: 1, stdout: "", stderr: "CreatePipe stderr failed", timedOut: false }
    }

    ; Make read handles non-inheritable
    DllCall("SetHandleInformation", "Ptr", hOutR, "UInt", 1, "UInt", 0) ; HANDLE_FLAG_INHERIT = 1
    DllCall("SetHandleInformation", "Ptr", hErrR, "UInt", 1, "UInt", 0)

    ; ---- STARTUPINFO / PROCESS_INFORMATION ----
    si := Buffer(A_PtrSize = 8 ? 104 : 68, 0)
    NumPut("UInt", si.Size, si, 0)
    ; dwFlags = STARTF_USESTDHANDLES (0x100)
    NumPut("UInt", 0x100, si, A_PtrSize = 8 ? 60 : 44)
    ; hStdOutput, hStdError
    NumPut("Ptr", hOutW, si, A_PtrSize = 8 ? 88 : 60)
    NumPut("Ptr", hErrW, si, A_PtrSize = 8 ? 96 : 64)
    ; hStdInput can stay 0

    pi := Buffer(A_PtrSize = 8 ? 24 : 16, 0)

    ; ---- CreateProcess (no window) ----
    CREATE_NO_WINDOW := 0x08000000

    ok := DllCall("CreateProcessW"
        , "Ptr", 0
        , "Ptr", StrPtr(cmdLine)
        , "Ptr", 0
        , "Ptr", 0
        , "Int", true              ; inherit handles
        , "UInt", CREATE_NO_WINDOW
        , "Ptr", 0
        , "Ptr", 0
        , "Ptr", si
        , "Ptr", pi
        , "Int")

    ; Close write ends in parent regardless
    DllCall("CloseHandle", "Ptr", hOutW)
    DllCall("CloseHandle", "Ptr", hErrW)

    if !ok {
        DllCall("CloseHandle", "Ptr", hOutR), DllCall("CloseHandle", "Ptr", hErrR)
        return { exitCode: 1, stdout: "", stderr: "CreateProcessW failed. WinErr=" A_LastError, timedOut: false }
    }

    hProcess := NumGet(pi, 0, "Ptr")
    hThread  := NumGet(pi, A_PtrSize, "Ptr")
    ; thread handle no longer needed
    DllCall("CloseHandle", "Ptr", hThread)

    ; ---- Read loops + wait ----
    stdout := "", stderr := ""
    start := A_TickCount
    timedOut := false

    while true {
        ; Drain any available output
        stdout .= ReadAvailableFromPipe(hOutR)
        stderr .= ReadAvailableFromPipe(hErrR)

        ; Check if process exited
        waitRes := DllCall("WaitForSingleObject", "Ptr", hProcess, "UInt", 0, "UInt")
        if (waitRes = 0) ; WAIT_OBJECT_0
            break

        if (A_TickCount - start > timeoutMs) {
            timedOut := true
            ; kill process
            DllCall("TerminateProcess", "Ptr", hProcess, "UInt", 1)
            break
        }
        Sleep 20
    }

    ; Final drain
    stdout .= ReadAvailableFromPipe(hOutR, true)
    stderr .= ReadAvailableFromPipe(hErrR, true)

    exitCode := 0
    DllCall("GetExitCodeProcess", "Ptr", hProcess, "UInt*", &exitCode)
    DllCall("CloseHandle", "Ptr", hProcess)
    DllCall("CloseHandle", "Ptr", hOutR)
    DllCall("CloseHandle", "Ptr", hErrR)

    return { exitCode: exitCode, stdout: stdout, stderr: stderr, timedOut: timedOut }
}

ReadAvailableFromPipe(hPipe, drainAll := false) {
    ; Non-blocking read from pipe using PeekNamedPipe.
    data := ""
    buf := Buffer(4096)
    avail := 0

    loop {
        ok := DllCall("PeekNamedPipe", "Ptr", hPipe, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt*", &avail, "Ptr", 0)
        if !ok || (avail = 0)
            break

        toRead := avail > 4096 ? 4096 : avail
        bytesRead := 0
        if !DllCall("ReadFile", "Ptr", hPipe, "Ptr", buf, "UInt", toRead, "UInt*", &bytesRead, "Ptr", 0)
            break

        if (bytesRead > 0)
            data .= StrGet(buf, bytesRead, "CP0")

        if (!drainAll)
            break
    }
    return data
}

; =================
; i18n
; =================
InitLanguage(ddlLang) {
    global CUR_LANG, iniPath, iniSection, iniKeyLang, LANG_FALLBACK

    saved := IniRead(iniPath, iniSection, iniKeyLang, "")
    tag := saved != "" ? saved : GuessOsLangTag()

    ; If saved/guessed is not available, fall back.
    if !LangTagAvailable(tag)
        tag := LANG_FALLBACK
    if !LangTagAvailable(tag)
        tag := FirstAvailableLangTag()

    CUR_LANG := tag
    SetDdlSelectionByTag(ddlLang, tag)
    LoadI18N(tag)
}

LangTagAvailable(tag) {
    global LANG_FILES
    return LANG_FILES.Has(tag)
}

FirstAvailableLangTag() {
    global LANG_FILES, LANG_FALLBACK
    if LANG_FILES.Has(LANG_FALLBACK)
        return LANG_FALLBACK
    for tag, _ in LANG_FILES
        return tag
    return LANG_FALLBACK
}

SetDdlSelectionByTag(ddlLang, tag) {
    global LANGS
    for disp, t in LANGS {
        if (t = tag) {
            ddlLang.Choose(disp)
            return
        }
    }
    ddlLang.Choose(1)
}

LoadI18N(tag) {
    global I18N, LANG_FILES, LANG_FALLBACK

    I18N := Map()

    ; Load fallback first (if it exists)
    if LANG_FILES.Has(LANG_FALLBACK)
        MergeIniIntoMap(I18N, LANG_FILES[LANG_FALLBACK], "strings")

    ; Overlay selected language (if different)
    if (tag != LANG_FALLBACK && LANG_FILES.Has(tag))
        MergeIniIntoMap(I18N, LANG_FILES[tag], "strings")
}

GuessOsLangTag() {
    global LANG_FILES, LANG_FALLBACK

    langHex := "0x" A_Language

    switch langHex {
        case 0x0807, 0x0407:
            return LANG_FILES.Has("de-CH") ? "de-CH" : "de"

        case 0x0409:
            return LANG_FILES.Has("en-US") ? "en-US" : "en"

        default:
            return LANG_FALLBACK
    }
}

MergeIniIntoMap(dest, iniFile, section) {
    if !FileExist(iniFile)
        return
    raw := IniRead(iniFile, section)
    if (raw = "")
        return
    for line in StrSplit(raw, "`n", "`r") {
        if (line = "" || InStr(line, "=") = 0)
            continue
        parts := StrSplit(line, "=", , 2)
        k := Trim(parts[1])
        v := (parts.Length >= 2) ? parts[2] : ""
        dest[k] := v
    }
}

T(key, args*) {
    global I18N, I18N_MISSING, I18N_DEBUG

    if I18N.Has(key) {
        s := I18N[key]
    } else {
        ; Record missing key once
        if !I18N_MISSING.Has(key)
            I18N_MISSING[key] := true

        ; Development behavior
        if (I18N_DEBUG) {
            ; Visually obvious but non-breaking
            s := "[[" key "]]"
        } else {
            ; Production fallback: show key name silently
            s := key
        }
    }

    ; Replace placeholders
    for i, a in args
        s := StrReplace(s, "{" i "}", a)

    ; Convert encoded line breaks
    s := StrReplace(s, "``r``n", "`r`n")
    s := StrReplace(s, "``n", "`n")
    s := StrReplace(s, "``r", "`r")

    return s
}

LogMissingTranslations(*) {
	global I18N_MISSING, I18N_DEBUG, LOCAL_YTD

	if (I18N_DEBUG) {
		if (I18N_MISSING.Count > 0) {
			i18nlist := "Missing translation keys:`r`n`r`n"
			for k, _ in I18N_MISSING
				i18nlist .= k "`r`n"
			FileAppend(i18nlist "`r`n", LOCAL_YTD "\missing_i18n_keys.txt")
		}
	}
}