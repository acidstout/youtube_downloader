# Requirements
AutoHotkey v2  

# Build process
1. Open Ahk2Exe
2. Load YouTube Downloader.ahk
3. Load the icon as provided
4. Set Base File setting to v2.x with the respective architecture of the destination system (e.g., U32 for x86 or U64 for x64)
5. Set "Compress exe with" to "(none)".
6. Click the "Convert" button.

You now have a fully working exe-file.

# Why no compression?
While this tool is totally harmless and does not even use stealth techniques to protect itself, a lot of paranoid anti-virus software exists and will flag this file a at least potentially dangerous or give it some generic trojan label. In order to provide proper and clean files I upload them to VirusTotal and let them check those files. As soon as I add compression anti-virus software will run in circles screaming the hell out of their lungs. So, I provide the source code, you can very easily compile it yourself, and then you will see all this anti-virus software is actually snake-oil.