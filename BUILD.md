# Requirements
AutoHotkey v2  
(Optional) Resource Hacker  
(Optional) UPX

# Build process
1. Open Ahk2Exe
2. Load YouTube Downloader.ahk
3. (Optional) Provide a nice icon for your application
4. Set Base File setting to v2.x with the respective architecture of the destination system (e.g., U32 for x86 or U64 for x64)
5. Set "Compress exe with" to "(none)". We'll do that later manually.
6. Click the "Convert" button.

You now have a fully working exe-file.

# Adding proper version information
1. Open Resource Hacker
2. Load the exe-file you just created with Ahk2Exe
3. Edit the VERSION_INFO resource to your liking
4. Save the modifications
5. (Optional) Now compress the exe-file with UPX
6. (Optional) Sign the exe-file with your code signing certificate

