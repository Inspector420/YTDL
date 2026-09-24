YT Playlist Downloader
======================

Saves a whole YouTube playlist as MP3 files, with cover art, title and
artist, plus the video's link and ID written into each song's tags.

It works in two steps:
  1. Convert a saved playlist page (HTML) into a list of links.
  2. Download that list with yt-dlp as MP3.

Songs you already have are skipped, so you can run it again any time
(for example after liking new videos) and only new songs get downloaded.


SETUP (once)
------------
Put these three tools in the Tools folder. Just unzip them as they come;
the script searches inside the folders, so version names don't matter.
Each Tools folder also has a note with these links.

  Tools\yt-dlp\        yt-dlp.exe
                       GitHub:    https://github.com/yt-dlp/yt-dlp
                       Download:  https://github.com/yt-dlp/yt-dlp/releases/latest

  Tools\ffmpeg\        a Windows ffmpeg build (needs ffmpeg.exe + ffprobe.exe)
                       GitHub:    https://github.com/FFmpeg/FFmpeg  (source code only)
                       Download:  https://github.com/GyanD/codexffmpeg/releases/latest
                                  (the file ending in "-full_build.zip")

  Tools\TagLibSharp\   the TagLibSharp package
                       GitHub:    https://github.com/mono/taglib-sharp  (source code only)
                       Download:  https://www.nuget.org/packages/TagLibSharp
                                  Click "Download package", rename the .nupkg file
                                  to .zip, then unzip it into this folder.


STEP 1 - SAVE THE PLAYLIST PAGE
-------------------------------
  1. Open the playlist on youtube.com (Chrome or Edge).
  2. Scroll all the way to the bottom so every video is loaded.
     YouTube only loads 100 videos at a time. Holding the End key helps.
  3. Press Ctrl+S, set "Save as type" to "Webpage, Complete", and save it
     into HTML_Input. The extra "..._files" folder it creates can be deleted.
     ("Webpage, Single File" .mhtml files work too.)

     DO NOT USE "WEBPAGE, HTML ONLY": IT SAVES ONLY THE FIRST 100 VIDEOS,
     NO MATTER HOW FAR YOU SCROLLED. The browser remembers the last type
     you picked, so check it every time.

  Name the file something you'll recognize, like "Liked videos.html".
  The link list will get the same name: "Liked videos.txt".

  The converter compares what it found with the video count shown on the
  page, and tells you if the saved page is missing videos (for example
  when it was saved before YouTube finished loading the list).

  Other way that also works: press F12, find the element
  <div id="contents" ...> that holds the videos, right-click it,
  Copy > Copy outerHTML, paste into Notepad, save as a .html file.
  (This copy has no video count, so the completeness check can't run.)

  The converter doesn't depend on how YouTube lays out its pages. It looks
  for video IDs in links, page data and thumbnails, so it should keep
  working when YouTube redesigns things.


STEP 2 - RUN THE SCRIPT
-----------------------
  Right-click YT-Playlist-Downloader.ps1 > "Run with PowerShell".

  If Windows refuses to run it, either:
    - open PowerShell in this folder and paste the whole script in
      (pasting always works), or
    - run:  powershell -ExecutionPolicy Bypass -File .\YT-Playlist-Downloader.ps1


STEP 3 - USE THE MENU
---------------------
  1) Convert HTML files to link lists   HTML_Input  ->  Link_Lists
  2) Download link lists as MP3         Link_Lists  ->  Music
  3) Update yt-dlp                      do this when downloads start failing

  Pick files by number:  1   or  1,3   or  2-5   or  A for all.
  You can press Ctrl+C to stop a download run at any time.


WHAT GETS WRITTEN INTO EACH SONG
--------------------------------
  Comment     https://www.youtube.com/watch?v=VIDEOID
  Publisher   VIDEOID   (the 11 characters after "v=")

  If two different videos have the same title, the second one is saved as
  "Title [VIDEOID].mp3" so nothing gets overwritten.


IF SOMETHING FAILS
------------------
  Links that couldn't be downloaded (deleted, private, blocked...) are saved
  to Link_Lists\<list name> (failed).txt. Pick that list later to retry.
  When everything in it succeeds, the file removes itself.

  Most failures are fixed by option 3 (Update yt-dlp).


FOLDERS
-------
  HTML_Input\    saved playlist pages go here
  Link_Lists\    link lists made by the script (plain text, one link per line)
  Music\         finished MP3s
  Temp\          work folder, emptied automatically
  Tools\         yt-dlp, ffmpeg and TagLibSharp
