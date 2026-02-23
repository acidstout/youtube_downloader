;@Ahk2Exe-SetName YouTube Downloader
;@Ahk2Exe-SetProductName YouTube Downloader
;@Ahk2Exe-SetDescription Einfach Videos von YouTube runterladen
;@Ahk2Exe-SetCompanyName Rekow IT
;@Ahk2Exe-SetCopyright Copyright © 2026 Rekow IT
;@Ahk2Exe-SetVersion 1.3
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
versionInfo         := "v1.3"
; ===========================================


; Check folders and permissions
try {
	if !DirExist(LOCAL_YTD) {
		DirCreate(LOCAL_YTD)
	}
} catch Error as err {
	MsgBox "Der Ordner für die Abhängigkeiten konnte nicht erstellt werden:`r`n" err.Message
}

installedDependencies := IniRead(iniPath, iniSection, "InstalledDependencies", "")

if (installedDependencies != "1") {
	CheckAndDownloadDependencies()
}

CheckAndDownloadDependencies() {
	; ---- Progress GUI ----
	pg := ProgressGuiCreate("YouTube Downloader: Abhängigkeiten prüfen/installieren")
	pg.Update(0, "Starte ...")

	overallOk := true
	msg := ""

	; Step plan:
	; 0-33  : Deno (download, extract, validate)
	; 34-66 : FFmpeg (download, extract single exe, validate)
	; 67-100: yt-dlp (download single exe, validate)

	r1 := EnsureDenoLocalOnly(pg)
	overallOk := overallOk && r1.ok
	msg .= "Deno: " (r1.ok ? "OK" : "FAIL") "`r`n" r1.message "`r`n`r`n"

	r2 := EnsureFfmpegLocalOnly(pg)
	overallOk := overallOk && r2.ok
	msg .= "FFmpeg: " (r2.ok ? "OK" : "FAIL") "`r`n" r2.message

	r3 := EnsureYtdlpLocalOnly(pg)
	overallOk := overallOk && r3.ok
	msg .= "yt-dlp: " (r3.ok ? "OK" : "FAIL") "`r`n" r3.message

	pg.Update(100, overallOk ? "Erledigt." : "Erledigt mit Fehlern.")
	Sleep 350
	pg.Close()

	if (overallOk) {
		IniWrite("1", iniPath, iniSection, "InstalledDependencies")
	}
}

; =========================
; Simple progress GUI
; =========================
class ProgressGui {
    __New(title := "Fortschritt") {
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
mainGui := Gui("+Resize +MinSize500x360", "YouTube Downloader")
mainGui.MarginX := 12
mainGui.MarginY := 12
mainGui.SetFont("s10", "Segoe UI")
; mainGui.Opt("+E0x02000000")  ; WS_EX_COMPOSITED: Use compositing, which might be sluggish and therefore is commented out.

; Add radio-buttons for browser selection
grp    := mainGui.Add("GroupBox", "x10 y10 w360 h48", "Nutze Session-Cookies von")
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

lblUrls  := mainGui.AddText(, "YouTube URLs einfügen (eine pro Zeile):")
urlsEdit := mainGui.AddEdit("vUrls WantTab Multi -Wrap VScroll")

lblLog  := mainGui.AddText(, "Protokoll:")
logEdit := mainGui.AddEdit("ReadOnly +Multi -Wrap HScroll VScroll vLog")

statusLeft  := mainGui.AddText(, "Bereit.")
statusRight := mainGui.AddText(, versionInfo)
statusRight.Opt("+Right")
statusRight.OnEvent("Click", ShowAbout)

btnRunUrls  := mainGui.AddButton(, "Download")
btnOther    := mainGui.AddButton(, "Update")
btnClearLog := mainGui.AddButton(, "Protokoll leeren")

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
	global lblUrls, urlsEdit, lblLog, logEdit, statusLeft, statusRight, btnRunUrls, btnOther, btnClearLog

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
		rightW := 160          ; fixed width for the bottom-right static text
		statusGap := 10

		; Left status takes remaining space, stays left-aligned
		statusLeft.Move(x, statusY, usableW - rightW - statusGap, 20)

		; Right status is right-aligned and fixed width
		statusRight.Move(x + usableW - rightW, statusY, rightW, 20)
		
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
ShowAbout(*) {
	global versionInfo
	MsgBox "YouTube Downloader`r`nVersion " versionInfo "`r`n`r`nCopyright © 2026 by Rekow IT`r`nhttps://rekow.ch`r`n`r`nAlle Rechte vorbehalten.", "Über", 0x40
	return
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
		MsgBox "Der Downloads-Ordner konnte nicht erstellt werden:`r`n" err.Message
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
        MsgBox "Keine URLs gefunden.", "YouTube Downloader", 0x30
        return
    }
    if !FileExist(LOCAL_YTDLP) {
        MsgBox "yt-dlp.exe nicht gefunden:`r`n" LOCAL_YTDLP "`r`nBitte erst updaten.", "YouTube Downloader", 0x10
        return
    }

    SetBusy(true)
    AppendLog(logEdit, "=== Download gestartet: " FormatTime(, "yyyy-MM-dd HH:mm:ss") " ===`r`n")

    ok := 0
    for idx, url in urls {
        statusLeft.Value := "Lade " idx "/" urls.Length ": " url
        AppendLog(logEdit, "[" idx "/" urls.Length "] " url "`r`n")

        ; Run yt-dlp.exe
		cmd := LOCAL_YTDLP " " cookiesFromBrowser " --buffer-size 64K --http-chunk-size 1M --windows-filenames --concurrent-fragments 10 -o %(fulltitle)s.%(ext)s " url
        exitCode := RunWait(cmd, downloadsDir, "Hide")

        if (exitCode = 0) {
            ok++
            AppendLog(logEdit, "  -> OK`r`n")
        } else {
            AppendLog(logEdit, "  -> Fehler #" exitCode "`r`n")
        }
    }

    statusLeft.Value := "Erledigt. " ok "/" urls.Length " erfolgreich."
    AppendLog(logEdit, "=== Erledigt: " ok "/" urls.Length " erfolgreich ===`r`n")
    SetBusy(false)
}

RunOther(*) {
    global YTDLP_URL, statusLeft, logEdit, LOCAL_YTDLP

    SetBusy(true)
    statusLeft.Value := "Update ..."
    AppendLog(logEdit, "=== Update yt-dlp: " FormatTime(, "yyyy-MM-dd HH:mm:ss") " ===`r`n")

    if !FileExist(LOCAL_YTDLP) {
        AppendLog(logEdit, "yt-dlp.exe nicht gefunden: " LOCAL_YTDLP "`r`nEs wird versucht, yt-dlp.exe herunterzuladen.`r`n")
		url := YTDLP_URL

		try {
			HttpDownload(url, LOCAL_YTDLP)
			statusLeft.Value := "Erledigt."
			AppendLog(logEdit, "  -> OK`r`n")
		} catch as e {
			statusLeft.Value := "Fehler!"
			AppendLog(logEdit, "  -> Fehler:`r`n" e.Message "`r`n")
		}
    } else {
		cmd := LOCAL_YTDLP " -U"
		exitCode := RunWait(cmd, LOCAL_YTD, "Hide")

		if (exitCode = 0) {
			statusLeft.Value := "Erledigt."
			AppendLog(logEdit, "  -> OK`r`n")
		} else {
			statusLeft.Value := "Fehler!"
			AppendLog(logEdit, "  -> Fehler #" exitCode "`r`n")
		}
	}
	
	if FileExist(LOCAL_YTDLP ":Zone.Identifier") {
		zone := LOCAL_YTDLP ":Zone.Identifier"

		try {
			FileDelete zone
			AppendLog(logEdit, "  -> yt-dlp.exe wurde als sicher markiert.`r`n")
		} catch {
			AppendLog(logEdit, "  -> yt-dlp.exe ist bereits sicher.`r`n")
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
        throw Error("Invalid GUID: " guidStr)
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
	
	userAgentChrome1    := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/"
	userAgentChrome2    := " Safari/537.36"
	
	userAgentFirefox1   := "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:"
	userAgentFirefox2   := ") Gecko/20100101"
	
	browserVersion      := fallbackVersion
	userAgentPart1      := userAgentChrome1
	userAgentPart2      := userAgentChrome2
	userAgentPart3      := ""

	switch last {
		case 1:
			; Chrome
			userAgentPart1 := userAgentChrome1
			userAgentPart2 := userAgentChrome2
			userAgentPart3 := ""
			try {
				; Search for Chrome
				browserFile := RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe", "")
			} catch {
				AppendLog(logEdit, "  -> Chrome nicht gefunden.`r`n")
			}
			
		case 2:
			; Edge
			userAgentPart1 := userAgentChrome1
			userAgentPart2 := userAgentChrome2
			userAgentPart3 := " Edg/"
			try {
				; Search for Edge
				browserFile := RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe", "")
			} catch {
				AppendLog(logEdit, "  -> Edge nicht gefunden.`r`n")
			}
			
		case 3:
			; Firefox
			userAgentPart1 := userAgentFirefox1
			userAgentPart2 := userAgentFirefox2
			userAgentPart3 := "Firefox/"
			try {
				; Search for Firefox
				browserFile := RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe", "")
			} catch {
				AppendLog(logEdit, "  -> Firefox nicht gefunden.`r`n")
			}			
			
		default:
			; Fallback
			browserFile := ""
	}

	if (browserFile != "") {
		AppendLog(logEdit, "  -> Habe " browserFile " gefunden.`r`n")
		try {
			browserVersion := GetFileVersion(browserFile)
		} catch as e {
			AppendLog(logEdit, "  -> Konnte User-Agent nicht ermitteln. Nutze Standard.`r`n")
		}
	}

	; Append Edge version if we have Edge.
	if (userAgentPart3 != "") {
		userAgentPart3 .= browserVersion
	}

	if (browserVersion != "") {
		SaveFallbackVersion(browserVersion)
		browserVersion := userAgentPart1 browserVersion userAgentPart2 userAgentPart3
	} else {
		AppendLog(logEdit, "  -> Unbekannte Browser-Version: '" browserVersion "'`r`n")
		browserVersion := userAgentChrome1 fallbackVersion userAgentChrome2
	}
	AppendLog(logEdit, "  -> User-Agent: " browserVersion "`r`n")

	return browserVersion
}

; Download helper
HttpDownload(url, savePath) {
	userAgent := GetBrowserUserAgent()
    ; Ensure target directory exists
    SplitPath savePath, , &dir
    if (dir)
        DirCreate dir

    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.Option[6] := true ; Enable redirects
    req.Open("GET", url, false)
    req.SetRequestHeader("User-Agent", userAgent)
    req.Send()
    req.WaitForResponse()

    status := req.Status
    if (status < 200 || status >= 300)
        throw Error("HTTP error " status ": " req.StatusText)

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

    pg.Update(5, "Suche Deno ...")

    if FileExist(LOCAL_DENO) {
		WaitForFileStable(LOCAL_DENO, 10000)
        v := TryRunDenoVersion(LOCAL_DENO)
        if v.ok && VersionAtLeast(v.major, v.minor, DENO_MIN_MAJOR, DENO_MIN_MINOR) {
            pg.Update(50, "Deno OK.")
            return { ok: true, message: "Gefunden.`r`nPfad: " LOCAL_DENO "`r`nVersion: " v.major "." v.minor "." v.patch }
        }
        ; present but too old/broken => reinstall
    }

    ; Install/reinstall from ZIP
    pg.Update(10, "Downloade Deno...")
    tempZip := A_Temp "\deno_" A_TickCount ".zip"
    if !SilentDownload(DENO_URL, tempZip) {
        pg.Update(33, "Deno Download fehlgeschlagen.")
        return { ok: false, message: "Konnte Deno nicht herunterladen.`r`nURL: " DENO_URL }
    }

    ; Extract only deno.exe out of the ZIP into script folder
    pg.Update(20, "Installiere Deno ...")
    try {
        if FileExist(LOCAL_DENO)
            FileDelete(LOCAL_DENO)
        ExtractSingleFileFromZipShell(tempZip, LOCAL_YTD, "deno.exe", 100000)
    } catch as e {
        try FileDelete(tempZip)
        pg.Update(33, "Deno Installation fehlgeschlagen.")
        return { ok: false, message: "Deno konnte nicht installiert werden.`r`n" e.Message }
    }
    try FileDelete(tempZip)

    pg.Update(25, "Validiere Deno...")
	WaitForFileStable(LOCAL_DENO, 10000)
    v2 := TryRunDenoVersion(LOCAL_DENO)
    if !v2.ok {
        pg.Update(33, "Deno Validierung fehlgeschlagen.")
        return { ok: false, message: "Deno erfolgreich installiert, aber die Validierung schlug fehl.`r`n" v2.message }
    }
    if !VersionAtLeast(v2.major, v2.minor, DENO_MIN_MAJOR, DENO_MIN_MINOR) {
        pg.Update(33, "Deno Version zu alt.")
        return { ok: false, message: "Deno erfolgreich installiert, aber die Version ist zu alt.`r`nGefunden: " v2.major "." v2.minor "." v2.patch "`r`nBenötigt: >= " DENO_MIN_MAJOR "." DENO_MIN_MINOR ".0" }
    }

    pg.Update(33, "Deno installiert.")
    return { ok: true, message: "Deno installiert.`r`nPfad: " LOCAL_DENO "`r`nVersion: " v2.major "." v2.minor "." v2.patch }
}

TryRunDenoVersion(denoPath) {
    exec := ExecCaptureCP(denoPath, "--version", 4000)

    if (exec.timedOut)
        return { ok: false, message: "Timeout nach 8000 ms" }

    stdtext := Trim(exec.stdout) != "" ? exec.stdout : exec.stderr
    if (Trim(stdtext) = "")
        return { ok: false, message: "Keine Ausgabe. ExitCode: " exec.exitCode }

    for line in StrSplit(stdtext, "`n", "`r") {
        line := Trim(line)
        if RegExMatch(line, "i)^deno\s+(\d+)\.(\d+)\.(\d+)", &m)
            return { ok: true, major: Integer(m[1]), minor: Integer(m[2]), patch: Integer(m[3]) }
    }

    return { ok: false, message: "Konnte Version nicht parsen.`r`nExitCode: " exec.exitCode "`r`nAusgabe:`r`n" stdtext }
}

; =========================
; FFmpeg (local-only, extract ONLY ffmpeg.exe)
; =========================
EnsureFfmpegLocalOnly(pg) {
    global FFMPEG_URL, LOCAL_FFMPEG

    pg.Update(34, "Suche FFmpeg ...")

    if FileExist(LOCAL_FFMPEG) {
		WaitForFileStable(LOCAL_FFMPEG, 10000)
        r := TryRunFfmpeg(LOCAL_FFMPEG)
        if r.ok {
            pg.Update(66, "FFmpeg OK.")
            return { ok: true, message: "Gefunden.`r`nPfad: " LOCAL_FFMPEG "`r`n" r.message }
        }
        ; broken => reinstall
    }

    pg.Update(40, "Downloade FFmpeg ...")
    tempZip := A_Temp "\ffmpeg_" A_TickCount ".zip"
    if !SilentDownload(FFMPEG_URL, tempZip) {
        pg.Update(66, "FFmpeg Download fehlgeschlagen.")
        return { ok: false, message: "Konnte FFmpeg nicht herunterladen.`r`nURL: " FFMPEG_URL }
    }

    pg.Update(50, "Installiere FFmpeg ...")
    try {
        if FileExist(LOCAL_FFMPEG)
            FileDelete(LOCAL_FFMPEG)
        ExtractSingleFileFromZipShell(tempZip, LOCAL_YTD, "ffmpeg.exe", 100000)
    } catch as e {
        try FileDelete(tempZip)
        pg.Update(66, "FFmpeg Installation fehlgeschlagen.")
        return { ok: false, message: "FFmpeg konnte nicht installiert werden.`r`n" e.Message }
    }
    try FileDelete(tempZip)

    pg.Update(60, "Validiere FFmpeg ...")
	WaitForFileStable(LOCAL_FFMPEG, 10000)
    r2 := TryRunFfmpeg(LOCAL_FFMPEG)
    if r2.ok {
        pg.Update(66, "FFmpeg installiert.")
        return { ok: true, message: "FFmpeg installiert.`r`nPfad: " LOCAL_FFMPEG "`r`n" r2.message }
    }

    pg.Update(66, "FFmpeg Validierung fehlgeschlagen.")
    return { ok: false, message: "FFmpeg erfolgreich installiert, aber Validierung fehlgeschlagen.`r`n" r2.message }
}

TryRunFfmpeg(ffmpegPath) {
    exec := ExecCaptureCP(ffmpegPath, "-version", 4000)

    if (exec.timedOut)
        return { ok: false, message: "Timeout nach 8000 ms" }

    stdtext := Trim(exec.stdout) != "" ? exec.stdout : exec.stderr
    if (Trim(stdtext) = "")
        return { ok: false, message: "Keine Ausgabe. ExitCode: " exec.exitCode }

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

    return { ok: false, message: "FFmpeg Ausgabe unerwartet.`r`nExitCode: " exec.exitCode "`r`nAusgabe:`r`n" stdtext }
}


; =========================
; yt-dlp (local-only)
; =========================
EnsureYtdlpLocalOnly(pg) {
    global YTDLP_URL, LOCAL_YTDLP

    pg.Update(67, "Suche yt-dlp ...")

    if FileExist(LOCAL_YTDLP) {
		WaitForFileStable(LOCAL_YTDLP, 10000)
        r := TryRunYtdlp(LOCAL_YTDLP)
        if r.ok {
            pg.Update(100, "yt-dlp OK.")
            return { ok: true, message: "Gefunden.`r`nPfad: " LOCAL_YTDLP "`r`n" r.message }
        }
        ; broken => reinstall
    }

    pg.Update(70, "Downloade yt-dlp ...")
    tempFile := A_Temp "\ytdlp_" A_TickCount ".exe"
    if !SilentDownload(YTDLP_URL, tempFile) {
        pg.Update(100, "yt-dlp Download fehlgeschlagen.")
        return { ok: false, message: "Konnte yt-dlp nicht herunterladen.`r`nURL: " YTDLP_URL }
    }

    pg.Update(80, "Installiere yt-dlp ...")
    try {
        if FileExist(LOCAL_YTDLP)
            FileDelete(LOCAL_YTDLP)
			MoveYtdlpFromTemp(tempFile)
    } catch as e {
        try FileDelete(tempFile)
        pg.Update(100, "yt-dlp Installation fehlgeschlagen.")
        return { ok: false, message: "yt-dlp konnte nicht installiert werden.`r`n" e.Message }
    }
    try FileDelete(tempFile)

    pg.Update(95, "Validiere yt-dlp ...")
	WaitForFileStable(LOCAL_YTDLP, 10000)
    r2 := TryRunYtdlp(LOCAL_YTDLP)
    if r2.ok {
        pg.Update(100, "yt-dlp installiert.")
        return { ok: true, message: "yt-dlp installiert.`r`nPfad: " LOCAL_YTDLP "`r`n" r2.message }
    }

    pg.Update(100, "yt-dlp Validierung fehlgeschlagen.")
    return { ok: false, message: "yt-dlp erfolgreich installiert, aber Validierung fehlgeschlagen.`r`n" r2.message }
}

TryRunYtdlp(*) {
	global LOCAL_YTDLP
    exec := ExecCaptureCP(LOCAL_YTDLP, "--version", 4000)

    if (exec.timedOut)
        return { ok: false, message: "Timeout nach 8000 ms" }

    stdtext := Trim(exec.stdout) != "" ? exec.stdout : exec.stderr
    if (Trim(stdtext) = "")
        return { ok: false, message: "Keine Ausgabe. ExitCode: " exec.exitCode }

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

	;return { ok: true, message: firstLine }
    return { ok: false, message: "yt-dlp Ausgabe unerwartet.`r`nExitCode: " exec.exitCode "`r`nAusgabe:`r`n" stdtext }
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
            throw Error("Timeout waiting for downloaded file: " sourceFile)
        Sleep 100
    }

    ; Ensure it is fully written, then unblock it (prevents SmartScreen hang)
    WaitForFileStable(sourceFile, timeoutMs)
    UnblockFile(sourceFile)

	try {
		FileMove(sourceFile, LOCAL_YTDLP, true)
	} catch Error as e {
		throw Error("Installation of yt-dlp failed:`r`n" e.Message)
	}
}


; =========================
; ZIP: extract ONLY one file using Shell COM (no PowerShell, minimal UI)
; =========================
ExtractSingleFileFromZipShell(zipPath, destDir, fileName, timeoutMs := 120000) {
    if !FileExist(zipPath)
        throw Error("ZIP not found: " zipPath)

    if !DirExist(destDir)
        DirCreate(destDir)

    app := ComObject("Shell.Application")

    zipNs := app.NameSpace(zipPath)
    if !zipNs
        throw Error("Failed to open ZIP via Shell: " zipPath)

    dstNs := app.NameSpace(destDir)
    if !dstNs
        throw Error("Failed to open destination via Shell: " destDir)

    item := FindZipItemRecursive(zipNs, fileName)
    if !item
        throw Error(fileName " not found inside ZIP: " zipPath)

    ; 16 = No UI (best-effort). Still silent in most environments.
    dstNs.CopyHere(item, 16|4)

    ; Wait until the file appears
    target := destDir "\" fileName
    start := A_TickCount
    while !FileExist(target) {
        if (A_TickCount - start > timeoutMs)
            throw Error("Timeout waiting for extracted file: " target)
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
