# YouTube Downloader
Simple UI to paste a bunch of links to YouTube videos in and download them using yt-dlp

![title screen](screenshot.png)

  
## Features
- Simple, intuitive user-interface.
- Portable. No installation required, but provided for conveniance reasons.
- Small footprint. The UI itself just uses around 4MB RAM.
- Automatic download and installation of all dependencies to get you up and running.
- Multi-language support. Translations of other languages are welcome. Just put them in the lang folder and they'll work.

## Usage
When you start it for the first time, all necessary dependencies will be installed in the folder where you installed YouTube Downloader.

Three dependencies will be installed:
1. yt-dlp. For downloading videos from YouTube.
2. Deno. To solve the JavaScript-based challenges that Google requires to prevent tools such as yt-dlp from downloading YouTube videos.
3. FFmpeg. This is used to convert the videos into a usable format and to combine the audio and video tracks.

To download videos from YouTube, enter the video URL in the text field of the YouTube Downloader. One video URL per line. Once you have entered all the video URLs, click the download button, and the videos will be downloaded for you one after the other.

You can see the current progress in the status bar.

If you want to download videos that are subject to age restrictions, you must first log in to your Google account in your browser. The YouTube Downloader currently supports Chrome, Edge, and Firefox.

## Update
Only yt-dlp will require updates at irregular intervals. To update yt-dlp, click on the “Update” button in YouTube Downloader. The latest version will be downloaded.

Deno and FFmpeg rarely require updates. If this should ever be necessary, simply delete all files in the folder where you installed YouTube Downloader, except for the YouTube Downloader.exe file. Then run YouTube Downloader again so that all dependencies are downloaded fresh.

Alternatively, you can also update yt-dlp, Deno, and FFmpeg yourself via the respective official GitHub repositories:  
[Latest Deno](https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip)  
[Latest FFmpeg](https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip)  
[Latest yt-dlp](https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe)  

## Known issues
It may happen that a video cannot be downloaded even though all dependencies are cleanly installed and up to date. In this case, you can only wait until there is an update from yt-dlp that can cope with the changes Google has made to YouTube.

If you get a virus warning it is a false positive. Some anti-virus programs are extremely paranoid and see things which are simply not there. I uploaded the binary to VirusTotal, provide a link in the release tag, and none of the anti-virus programs had an issue with it. However, that may change anytime.
