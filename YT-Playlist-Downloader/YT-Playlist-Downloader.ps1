# =====================================================================
#  YT Playlist Downloader
# ---------------------------------------------------------------------
#  1) Converts saved YouTube playlist pages (HTML) into link lists.
#  2) Downloads link lists as MP3 with yt-dlp and tags every song with
#       Comment   = https://www.youtube.com/watch?v=VIDEOID
#       Publisher = VIDEOID
#
#  Run it:    right-click this file > "Run with PowerShell"
#  Paste it:  open PowerShell in this folder and paste the whole script
#
#  Setup and help: see README.txt
# =====================================================================


# ----------------------------- Settings ------------------------------

$FolderNames = @{
    Html  = 'HTML_Input'   # you put saved playlist pages here
    Lists = 'Link_Lists'   # link lists made from those pages
    Music = 'Music'        # finished MP3s
    Temp  = 'Temp'         # work folder, emptied automatically
    Tools = 'Tools'        # yt-dlp, ffmpeg and TagLibSharp go in here
}

$SecondsBetweenDownloads = 1

# yt-dlp settings (same as the original script)
function Get-YtDlpArgs($Url, $Tools) {
    @(
        '--ffmpeg-location', $Tools.FfmpegDir,
        '--no-cache-dir',
        '--paths', $Dir.Temp,
        '--output', '%(title)s.%(ext)s',
        '--extract-audio',
        '--audio-format', 'mp3',
        '--audio-quality', '0',
        '--embed-thumbnail',
        '--add-metadata',
        '--no-playlist',
        $Url
    )
}


# ------------------------------ Helpers ------------------------------

function Write-Info($Text, $Color = 'Gray') {
    Write-Host "  $Text" -ForegroundColor $Color
}

function Write-Header($Title) {
    Clear-Host
    Write-Host ''
    Write-Host "  == $Title ==" -ForegroundColor Cyan
    Write-Host ''
}

function Wait-Enter {
    [void](Read-Host "`n  Press Enter to continue")
}

function Get-VideoUrl($Id) {
    "https://www.youtube.com/watch?v=$Id"
}

# Finds the project folder: the script's own folder, or the current
# folder when pasted, or asks for it.
function Get-ProjectRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }

    $here = (Get-Location).ProviderPath
    if (Test-Path -LiteralPath (Join-Path $here $FolderNames.Tools)) { return $here }

    Write-Host ''
    Write-Info 'Could not find the project folder (the one with the Tools folder in it).' Yellow
    while ($true) {
        $path = (Read-Host '  Paste the folder path here (Enter = cancel)').Trim().Trim('"')
        if (-not $path) { return $null }
        if (Test-Path -LiteralPath (Join-Path $path $FolderNames.Tools)) {
            return (Resolve-Path -LiteralPath $path).ProviderPath
        }
        Write-Info 'No Tools folder in there, try again.' Yellow
    }
}

# Builds full folder paths and creates any folder that is missing.
function Initialize-Folders {
    $script:Dir = @{}
    foreach ($key in $FolderNames.Keys) {
        $script:Dir[$key] = Join-Path $script:Root $FolderNames[$key]
    }
    $needed = @($Dir.Html, $Dir.Lists, $Dir.Music, $Dir.Temp,
                (Join-Path $Dir.Tools 'yt-dlp'),
                (Join-Path $Dir.Tools 'ffmpeg'),
                (Join-Path $Dir.Tools 'TagLibSharp'))
    foreach ($folder in $needed) { [void][IO.Directory]::CreateDirectory($folder) }
}

function Clear-Temp {
    Get-ChildItem -LiteralPath $Dir.Temp -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '.gitkeep' } |      # keeps the folder on GitHub
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# Lets the user pick items by number: "1,3,5-7", "A" for all, Enter = back.
function Read-Selection($Items) {
    while ($true) {
        $answer = (Read-Host "`n  Pick by number (e.g. 1,3,5-7)  A = all  Enter = back").Trim()
        if ($answer -eq '') { return }
        if ($answer -match '^(a|all)$') { return $Items }

        $picked = New-Object System.Collections.Generic.List[object]
        $valid = $true
        foreach ($part in ($answer -split '[,\s]+' | Where-Object { $_ })) {
            if     ($part -match '^(\d+)-(\d+)$') { $from = [int]$Matches[1]; $to = [int]$Matches[2] }
            elseif ($part -match '^\d+$')         { $from = [int]$part;       $to = $from }
            else   { $valid = $false; break }

            if ($from -gt $to) { $from, $to = $to, $from }
            if ($from -lt 1 -or $to -gt $Items.Count) { $valid = $false; break }
            foreach ($n in $from..$to) {
                if (-not $picked.Contains($Items[$n - 1])) { $picked.Add($Items[$n - 1]) }
            }
        }
        if ($valid -and $picked.Count) { return $picked.ToArray() }
        Write-Info "Use numbers from 1 to $($Items.Count), like 1,3,5-7 or A for all." Yellow
    }
}


# ------------------------------- Tools -------------------------------

# Searches the Tools folder, so any version / sub-folder layout works.
function Find-Tools {
    $files = @(Get-ChildItem -LiteralPath $Dir.Tools -Recurse -File -ErrorAction SilentlyContinue)

    $ytdlp  = $files | Where-Object { $_.Name -like 'yt-dlp*.exe' } | Select-Object -First 1
    $ffmpeg = $files | Where-Object {
                  $_.Name -eq 'ffmpeg.exe' -and
                  (Test-Path -LiteralPath (Join-Path $_.DirectoryName 'ffprobe.exe'))
              } | Select-Object -First 1

    # TagLibSharp ships two builds: net462 suits Windows PowerShell 5.1,
    # netstandard2.0 suits PowerShell 7. Prefer the matching one.
    # The matching build is tried first, the other one as a fallback.
    $dlls   = @($files | Where-Object { $_.Name -eq 'TagLibSharp.dll' })
    $prefer = if ($PSVersionTable.PSEdition -eq 'Core') { '*netstandard*' } else { '*net4*' }
    $taglib = @(@($dlls | Where-Object { $_.FullName -like $prefer }) + $dlls |
                ForEach-Object { $_.FullName } | Select-Object -Unique)

    [pscustomobject]@{
        YtDlp     = if ($ytdlp)  { $ytdlp.FullName } else { $null }
        FfmpegDir = if ($ffmpeg) { $ffmpeg.DirectoryName } else { $null }
        TagLib    = $taglib    # list of TagLibSharp.dll paths, best first
        Ready     = [bool]($ytdlp -and $ffmpeg -and $taglib.Count)
    }
}

function Write-ToolStatus($Tools) {
    Write-Host '  Tools: ' -NoNewline -ForegroundColor DarkGray
    foreach ($t in @(@('yt-dlp', $Tools.YtDlp), @('ffmpeg', $Tools.FfmpegDir), @('TagLibSharp', $Tools.TagLib.Count))) {
        if ($t[1]) { Write-Host "$($t[0]) OK   " -NoNewline -ForegroundColor Green }
        else       { Write-Host "$($t[0]) MISSING   " -NoNewline -ForegroundColor Red }
    }
    Write-Host ''
}

function Show-MissingTools($Tools) {
    Write-Info 'Some tools are missing. Put them here and try again:' Yellow
    Write-Host ''
    if (-not $Tools.YtDlp) {
        Write-Info "yt-dlp.exe       ->  $(Join-Path $Dir.Tools 'yt-dlp')"
        Write-Info '                     https://github.com/yt-dlp/yt-dlp/releases/latest' DarkGray
    }
    if (-not $Tools.FfmpegDir) {
        Write-Info "ffmpeg (unzipped, needs ffmpeg.exe + ffprobe.exe)  ->  $(Join-Path $Dir.Tools 'ffmpeg')"
        Write-Info '                     https://github.com/GyanD/codexffmpeg/releases/latest  (the -full_build.zip)' DarkGray
    }
    if (-not $Tools.TagLib.Count) {
        Write-Info "TagLibSharp (unzipped package)  ->  $(Join-Path $Dir.Tools 'TagLibSharp')"
        Write-Info '                     https://www.nuget.org/packages/TagLibSharp' DarkGray
    }
    Write-Host ''
    Write-Info 'Each Tools folder has a note with the official GitHub and download links.' DarkGray
}

# Files from a downloaded zip are marked "from the internet", which can
# stop Windows PowerShell from loading TagLibSharp. This removes the mark.
function Unblock-Tools($Tools) {
    $paths = @($Tools.YtDlp,
               (Join-Path $Tools.FfmpegDir 'ffmpeg.exe'),
               (Join-Path $Tools.FfmpegDir 'ffprobe.exe')) + $Tools.TagLib
    foreach ($p in $paths) {
        try { Unblock-File -LiteralPath $p -ErrorAction Stop } catch { }   # not needed / not possible
    }
}

function Import-TagLib($DllPaths) {
    foreach ($dll in $DllPaths) {
        if ('TagLib.File' -as [type]) { return $true }   # already loaded
        try { Add-Type -LiteralPath $dll -ErrorAction Stop } catch { }
    }
    if ('TagLib.File' -as [type]) { return $true }
    Write-Info 'Could not load TagLibSharp. Tried:' Red
    foreach ($dll in $DllPaths) { Write-Info "  $dll" Red }
    return $false
}


# ------------------------------ Tagging ------------------------------

# Reads the video ID from a song: Publisher first, then any YouTube link
# in Comment (older downloads) or in yt-dlp's own "comment"/"purl" fields.
function Get-SongId($Path) {
    $file = $null
    try {
        $file = [TagLib.File]::Create($Path)
        if ($file.Tag.Publisher -match '^[A-Za-z0-9_-]{11}$') { return $file.Tag.Publisher }

        $texts = @($file.Tag.Comment)
        $id3 = $file.GetTag([TagLib.TagTypes]::Id3v2, $false)
        if ($id3) { $texts += @($id3.GetFrames('TXXX') | ForEach-Object { $_.Text }) }
        foreach ($text in $texts) {
            if ($text -match '(?:[?&]v=|youtu\.be/)([A-Za-z0-9_-]{11})') { return $Matches[1] }
        }
    } catch { }
    finally { if ($file) { $file.Dispose() } }
    return $null
}

# Writes Comment = full link and Publisher (TPUB) = video ID in one save.
function Set-SongTags($Path, $Id) {
    $file = [TagLib.File]::Create($Path)
    try {
        $file.Tag.Comment = Get-VideoUrl $Id

        $id3 = $file.GetTag([TagLib.TagTypes]::Id3v2, $true)
        $id3.RemoveFrames('TPUB')
        $frame = New-Object TagLib.Id3v2.TextInformationFrame('TPUB', [TagLib.StringType]::Latin1)
        $frame.Text = $Id
        $id3.AddFrame($frame)

        $file.Save()
    }
    finally { $file.Dispose() }
}

# Collects the video IDs of every song already in the Music folder.
function Get-ExistingIds {
    $ids   = New-Object 'System.Collections.Generic.HashSet[string]'
    $songs = @(Get-ChildItem -LiteralPath $Dir.Music -Filter '*.mp3' -File -Recurse -ErrorAction SilentlyContinue)
    $i = 0
    foreach ($song in $songs) {
        $i++
        if ($i % 20 -eq 1) {
            Write-Progress -Id 3 -Activity 'Checking songs already in Music' `
                -Status "$i of $($songs.Count)" -PercentComplete ([int]($i / $songs.Count * 100))
        }
        $id = Get-SongId $song.FullName
        if ($id) { [void]$ids.Add($id) }
    }
    Write-Progress -Id 3 -Activity 'Checking songs already in Music' -Completed
    return ,$ids
}


# ---------------------------- Link lists -----------------------------

function Get-ListPathFor($HtmlFile) {
    Join-Path $Dir.Lists ($HtmlFile.BaseName + '.txt')
}

# "Liked videos.txt" and "Liked videos (failed).txt" share one failed file.
function Get-FailedPathFor($ListPath) {
    $base = [IO.Path]::GetFileNameWithoutExtension($ListPath) -replace ' \(failed\)$', ''
    Join-Path $Dir.Lists "$base (failed).txt"
}

# Reads video IDs from a link list, in order, without duplicates.
# Accepts full links, "/watch?v=..." links, youtu.be links or bare IDs.
function Read-LinkList($Path) {
    $ids  = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $line = $line.Trim()
        $id = $null
        if     ($line -match '(?:[?&]v=|youtu\.be/|/shorts/)([A-Za-z0-9_-]{11})(?![A-Za-z0-9_-])') { $id = $Matches[1] }
        elseif ($line -match '^([A-Za-z0-9_-]{11})$') { $id = $Matches[1] }
        if ($id -and $seen.Add($id)) { $ids.Add($id) }
    }
    return ,$ids
}


# ---------------------- Reading playlist pages -----------------------
#
# YouTube changes its page layout often, so the converter ignores the
# layout completely. It only relies on two things that have not changed
# in many years:
#   - every video has an 11-character ID, found in links like watch?v=ID
#   - videos in a playlist link back to it with list=PLAYLISTID
# First it undoes the ways a saved page can escape links, so it reads
# "Webpage, Complete", "Webpage, Single File" (.mhtml), copied outerHTML
# and raw page source the same way.

$VideoId = '[A-Za-z0-9_-]{11}(?![A-Za-z0-9_-])'

$Unescapes = @(                                               # escaped form -> plain
    @('\\+u0026', '&'), @('\\+u003d', '='), @('\\+u003f', '?'), @('\\+/', '/'),   # JSON / JavaScript
    @('&(?:amp;)+', '&'), @('&#0*38;|&#x0*26;', '&'),                             # HTML
    @('&#0*61;|&#x0*3d;', '='), @('&#0*63;|&#x0*3f;', '?'),
    @('%26', '&'), @('%3d', '='), @('%3f', '?'), @('%2f', '/')                    # URL encoding
)

function Get-HtmlFiles {
    @(Get-ChildItem -LiteralPath $Dir.Html -File |
      Where-Object { $_.Extension -match '^\.(html?|mht|mhtml)$' } | Sort-Object Name)
}

function ConvertFrom-SavedPage([string]$Text) {
    # .mhtml files wrap long lines with "=" and write "=" as "=3D"
    if ($Text.Substring(0, [Math]::Min(5000, $Text.Length)) -match 'quoted-printable') {
        $Text = $Text -replace '=\r?\n', '' -replace '=3D', '='
    }
    foreach ($pair in $Unescapes) { $Text = $Text -replace $pair[0], $pair[1] }
    return $Text
}

# The number of videos the page itself says the playlist has (or $null).
function Get-ReportedCount([string]$Text) {
    $patterns = @(
        '"(?:numVideosText|videoCountText)"[^0-9]{0,60}?(\d[\d,.\u00a0 ]*)',   # page data
        '"stats"[^0-9]{0,60}?(\d[\d,.\u00a0 ]*)',                              # page data
        '(\d[\d,.\u00a0]*)(?:\s|&nbsp;|<[^>]*>)*videos\b'                      # visible text
    )
    foreach ($p in $patterns) {
        $m = [regex]::Match($Text, $p)
        if ($m.Success) {
            $digits = $m.Groups[1].Value -replace '\D', ''
            if ($digits -and $digits.Length -lt 8) { return [int]$digits }
        }
    }
    return $null
}

# Returns the playlist's video IDs in order, where they were found, and
# how many videos the page says it has.
function Read-PlaylistPage($Path) {
    Write-Progress -Id 2 -ParentId 1 -Activity 'Reading page' -Status 'Loading file' -PercentComplete 0
    $text = [IO.File]::ReadAllText($Path)
    Write-Progress -Id 2 -ParentId 1 -Activity 'Reading page' -Status 'Cleaning up links' -PercentComplete 10
    $text = ConvertFrom-SavedPage $text

    # Every video link: watch?...v=ID... (keeping its list=), or /shorts/ID and similar
    $links = [regex]::Matches($text, 'watch\?([^"''<>\s\\]+)|(?:/shorts/|/embed/|/live/|youtu\.be/)(' + $VideoId + ')')
    $hits  = New-Object System.Collections.Generic.List[object]
    $lists = New-Object 'System.Collections.Generic.Dictionary[string,int]'
    $n = 0
    foreach ($m in $links) {
        $n++
        if ($n % 500 -eq 0) {
            Write-Progress -Id 2 -ParentId 1 -Activity 'Reading page' `
                -Status "Checking links: $n of $($links.Count)" -PercentComplete (10 + [int]($n / $links.Count * 90))
        }
        $id = $null; $list = ''; $index = 0
        if ($m.Groups[1].Success) {
            $query = $m.Groups[1].Value
            if ($query -match ('(?:^|&)v=(' + $VideoId + ')')) { $id = $Matches[1] }
            if ($query -match '(?:^|&)list=([A-Za-z0-9_-]+)') { $list = $Matches[1] }
            if ($query -match '(?:^|&)index=(\d{1,6})(?!\d)') { $index = [int]$Matches[1] }
        }
        else { $id = $m.Groups[2].Value }
        if (-not $id) { continue }

        $hits.Add(@($id, $list, (-not $m.Groups[1].Success), $index))   # id, list, path-style, position
        if ($list) { if ($lists.ContainsKey($list)) { $lists[$list]++ } else { $lists[$list] = 1 } }
    }
    Write-Progress -Id 2 -Activity 'Reading page' -Completed

    $ids  = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'

    # Main way: the playlist is the list= ID that most links point back to
    if ($lists.Count) {
        $playlistId = ($lists.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
        foreach ($h in $hits) {
            if (($h[1] -ceq $playlistId -or $h[2]) -and $seen.Add($h[0])) { $ids.Add($h[0]) }
        }
        $source = "links of playlist $playlistId"

        # Order by the page's own position numbers (index=) when every video has one
        $position = New-Object 'System.Collections.Generic.Dictionary[string,int]'
        foreach ($h in $hits) {
            if ($h[3] -and $h[1] -ceq $playlistId -and
                (-not $position.ContainsKey($h[0]) -or $h[3] -lt $position[$h[0]])) { $position[$h[0]] = $h[3] }
        }
        if ($position.Count -eq $ids.Count) {
            $ids = [System.Collections.Generic.List[string]]@($ids | Sort-Object { $position[$_] })
        }

        # Safety check: if most linked videos do NOT carry the playlist ID,
        # YouTube probably changed its links, so use all video links instead
        $allLinked = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($h in $hits) { [void]$allLinked.Add($h[0]) }
        if ($ids.Count -lt $allLinked.Count / 2) { $ids.Clear(); $seen.Clear() }
    }

    # Backup ways, in case YouTube ever changes how its links look
    $backups = @(
        @('all video links',          $null),
        @('video IDs in page data',   ('"videoId"\s*:\s*"(' + $VideoId + ')"')),
        @('thumbnail links',          ('/vi(?:_webp)?/(' + $VideoId + ')/'))
    )
    foreach ($b in $backups) {
        if ($ids.Count) { break }
        $source = $b[0]
        if ($b[1]) { foreach ($m in [regex]::Matches($text, $b[1])) { if ($seen.Add($m.Groups[1].Value)) { $ids.Add($m.Groups[1].Value) } } }
        else       { foreach ($h in $hits) { if ($seen.Add($h[0])) { $ids.Add($h[0]) } } }
    }

    [pscustomobject]@{
        Ids      = $ids
        Source   = $source
        Reported = Get-ReportedCount $text
        Backup   = ($source -notlike 'links of playlist*')
    }
}

# Prints a big red block that is hard to miss.
function Write-Banner([string[]]$Lines) {
    $width = ($Lines | Measure-Object -Property Length -Maximum).Maximum + 4
    Write-Host ''
    foreach ($line in @('') + $Lines + @('')) {
        Write-Host '  ' -NoNewline
        Write-Host ('  ' + $line).PadRight($width) -ForegroundColor Yellow -BackgroundColor DarkRed
    }
    Write-Host ''
}

# Tells the user whether the saved page had the whole playlist.
function Write-PageCheck($Result) {
    $found    = $Result.Ids.Count
    $reported = $Result.Reported

    if ($Result.Backup) {
        Write-Info "   Found using backup method: $($Result.Source). Please double-check this list." DarkYellow
    }
    if ($reported -and $found -lt $reported) {
        $gap = $reported - $found
        if ($gap -le [Math]::Max(5, $reported * 0.02)) {
            Write-Info ('   The page lists {0:N0}. The other {1:N0} are probably hidden or unavailable videos.' -f $reported, $gap) DarkGray
        }
        elseif ($found -le 100) {
            # YouTube sends the first 100 videos with the page; the rest only load
            # while scrolling. "Webpage, HTML Only" saves just those first 100.
            Write-Banner @(
                '!!!  WARNING: ONLY THE FIRST {0} VIDEOS ARE IN THIS FILE  !!!' -f $found
                'THE PAGE SAYS THIS PLAYLIST HAS {0:N0} VIDEOS.' -f $reported
                ''
                'THIS HAPPENS WHEN "SAVE AS TYPE" IS SET TO "WEBPAGE, HTML ONLY".'
                'THAT ONLY SAVES THE FIRST 100, NO MATTER HOW FAR YOU SCROLLED.'
                ''
                'TO GET THEM ALL:'
                '  1. SCROLL TO THE VERY BOTTOM OF THE PLAYLIST'
                '  2. PRESS CTRL+S'
                '  3. SET "SAVE AS TYPE" TO "WEBPAGE, COMPLETE"'
                '     (OR "WEBPAGE, SINGLE FILE")'
                ''
                'THE LINK LIST WITH THESE {0} WAS STILL CREATED.' -f $found
            )
        }
        else {
            Write-Info ('   Note: only {0:N0} of the {1:N0} videos are in this file.' -f $found, $reported) DarkYellow
            Write-Info '   If you wanted the whole playlist, scroll to the very bottom before saving (README step 1).' DarkYellow
        }
    }
    elseif ($reported) {
        Write-Info ('   Complete: the page lists {0:N0} videos.' -f $reported) DarkGray
    }
    elseif ($found % 100 -eq 0) {
        Write-Info '   Exactly a multiple of 100: if the playlist is bigger, scroll further down before saving.' DarkYellow
    }
}


# ------------------------ 1) Convert HTML files ----------------------

function Convert-HtmlFiles {
    Write-Header 'Convert HTML files to link lists'

    $files = @(Get-HtmlFiles)
    if ($files.Count -eq 0) {
        Write-Info "No .html files found in: $($Dir.Html)" Yellow
        Write-Info 'Save a YouTube playlist page in there first (see README.txt).'
        Wait-Enter; return
    }

    for ($i = 0; $i -lt $files.Count; $i++) {
        $f = $files[$i]
        $done = if (Test-Path -LiteralPath (Get-ListPathFor $f)) { '   (converted before)' } else { '' }
        Write-Host ('  {0,3})  {1}   [{2:N1} MB]{3}' -f ($i + 1), $f.Name, ($f.Length / 1MB), $done)
    }

    $picked = @(Read-Selection $files)
    if ($picked.Count -eq 0) { return }
    Write-Host ''

    $n = 0
    foreach ($f in $picked) {
        $n++
        Write-Progress -Id 1 -Activity 'Converting HTML to link lists' `
            -Status "File $n of $($picked.Count): $($f.Name)" -PercentComplete ([int](($n - 1) / $picked.Count * 100))
        try {
            $result = Read-PlaylistPage $f.FullName
            if ($result.Ids.Count -eq 0) {
                Write-Info "$($f.Name): no videos found. Was the page saved as described in README.txt?" Yellow
                continue
            }

            $out = Get-ListPathFor $f
            [IO.File]::WriteAllLines($out, [string[]]@($result.Ids | ForEach-Object { Get-VideoUrl $_ }))
            Write-Info ('{0}  ->  {1}   ({2:N0} videos)' -f $f.Name, [IO.Path]::GetFileName($out), $result.Ids.Count) Green
            Write-PageCheck $result
        }
        catch {
            Write-Info "$($f.Name): failed - $($_.Exception.Message)" Red
        }
    }
    Write-Progress -Id 1 -Activity 'Converting HTML to link lists' -Completed
    Wait-Enter
}


# ------------------------- 2) Download lists -------------------------

function Start-Downloads {
    Write-Header 'Download link lists as MP3'

    $tools = Find-Tools
    if (-not $tools.Ready) { Show-MissingTools $tools; Wait-Enter; return }

    $lists = @(Get-ChildItem -LiteralPath $Dir.Lists -Filter '*.txt' -File | Sort-Object Name)
    if ($lists.Count -eq 0) {
        Write-Info "No link lists in: $($Dir.Lists)" Yellow
        Write-Info 'Convert an HTML file first (option 1 in the main menu).'
        Wait-Enter; return
    }

    for ($i = 0; $i -lt $lists.Count; $i++) {
        $count = (Read-LinkList $lists[$i].FullName).Count
        Write-Host ('  {0,3})  {1}   [{2} links]' -f ($i + 1), $lists[$i].Name, $count)
    }

    $picked = @(Read-Selection $lists)
    if ($picked.Count -eq 0) { return }

    # One queue from all picked lists, duplicates removed
    $queue = New-Object System.Collections.Generic.List[object]
    $seen  = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($list in $picked) {
        foreach ($id in (Read-LinkList $list.FullName)) {
            if ($seen.Add($id)) { $queue.Add([pscustomobject]@{ Id = $id; List = $list.FullName }) }
        }
    }

    Unblock-Tools $tools
    if (-not (Import-TagLib $tools.TagLib)) { Wait-Enter; return }

    Write-Host ''
    $have = Get-ExistingIds
    $todo = @($queue | Where-Object { -not $have.Contains($_.Id) })

    Write-Info "$($queue.Count) videos in the selected list(s)"
    Write-Info "$($queue.Count - $todo.Count) already in Music, skipped"
    Write-Info "$($todo.Count) to download" Cyan
    if ($todo.Count -eq 0) {
        Write-Info 'Nothing new to download.' Green
        Remove-FailedLists $picked
        Wait-Enter; return
    }

    while ($true) {
        $answer = (Read-Host "`n  Start downloading? (Y/N)").Trim()
        if ($answer -match '^(y|yes)$') { break }
        if ($answer -match '^(n|no)$')  { return }
        Write-Info 'Please type Y or N.' Yellow
    }

    Invoke-DownloadQueue $todo $picked $tools
}

function Invoke-DownloadQueue($Todo, $Lists, $Tools) {
    $failedIds = New-Object 'System.Collections.Generic.HashSet[string]'
    $saved     = 0
    $total     = $Todo.Count
    $started   = Get-Date
    $finished  = $false

    try {
        $n = 0
        foreach ($item in $Todo) {
            $n++
            $url = Get-VideoUrl $item.Id
            Write-Progress -Id 1 -Activity 'Downloading MP3s' `
                -Status ('{0} of {1}   |   saved {2}   failed {3}' -f $n, $total, $saved, $failedIds.Count) `
                -PercentComplete ([int](($n - 1) / $total * 100))
            Write-Host ''
            Write-Host ('  [{0}/{1}]  {2}' -f $n, $total, $url) -ForegroundColor Cyan

            Clear-Temp
            $ytArgs = Get-YtDlpArgs $url $Tools
            & $Tools.YtDlp @ytArgs
            if ($LASTEXITCODE -ne 0) {
                Write-Info 'yt-dlp reported a problem, retrying once...' Yellow
                Start-Sleep -Seconds 3
                & $Tools.YtDlp @ytArgs
            }

            $mp3  = Wait-ForMp3
            $name = if ($mp3) { Save-Song $mp3 $item.Id } else { $null }

            if ($name) { $saved++; Write-Info "Saved: $name" Green }
            else       { [void]$failedIds.Add($item.Id); Write-Info "FAILED: $url" Red }

            Start-Sleep -Seconds $SecondsBetweenDownloads
        }
        $finished = $true
    }
    finally {
        # Runs even if you press Ctrl+C, so failed links are never lost
        Write-Progress -Id 1 -Activity 'Downloading MP3s' -Completed
        Clear-Temp
        Save-FailedLists $Todo $Lists $failedIds $finished
    }

    $time = (Get-Date) - $started
    Write-Host ''
    Write-Host '  ------------------------------------------' -ForegroundColor DarkCyan
    Write-Info "Done in $([int]$time.TotalMinutes) min $($time.Seconds) s"
    Write-Info "Saved:  $saved" Green
    if ($failedIds.Count) {
        Write-Info "Failed: $($failedIds.Count)  (saved to '... (failed).txt' in Link_Lists, pick it to retry)" Red
    }
    Wait-Enter
}

# Waits (max 5 s) for the finished MP3 in Temp to be unlocked.
function Wait-ForMp3 {
    for ($i = 0; $i -lt 25; $i++) {
        $mp3 = Get-ChildItem -LiteralPath $Dir.Temp -Filter '*.mp3' -File |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($mp3) {
            try {
                $stream = [IO.File]::Open($mp3.FullName, 'Open', 'ReadWrite', 'None')
                $stream.Close()
                return $mp3
            } catch { }
        }
        Start-Sleep -Milliseconds 200
    }
    return $null
}

# Tags the MP3, then moves it to Music. Returns the final file name.
function Save-Song($Mp3, $Id) {
    try {
        Set-SongTags $Mp3.FullName $Id

        $dest = Join-Path $Dir.Music $Mp3.Name
        if (Test-Path -LiteralPath $dest) {
            # A different song already uses this name: keep both
            $dest = Join-Path $Dir.Music ('{0} [{1}]{2}' -f $Mp3.BaseName, $Id, $Mp3.Extension)
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
        }
        [IO.File]::Move($Mp3.FullName, $dest)
        return [IO.Path]::GetFileName($dest)
    }
    catch {
        Write-Info "Could not tag or move $($Mp3.Name): $($_.Exception.Message)" Red
        return $null
    }
}

# Writes "<list> (failed).txt" for every list that had failures.
# A finished run replaces the old file; an interrupted run adds to it.
function Save-FailedLists($Todo, $Lists, $FailedIds, $Finished) {
    $paths = @($Lists | ForEach-Object { Get-FailedPathFor $_.FullName } | Select-Object -Unique)
    foreach ($path in $paths) {
        $urls = @($Todo | Where-Object { (Get-FailedPathFor $_.List) -eq $path -and $FailedIds.Contains($_.Id) } |
                  ForEach-Object { Get-VideoUrl $_.Id })

        if (-not $Finished -and (Test-Path -LiteralPath $path)) {
            $urls = @(@([IO.File]::ReadAllLines($path)) + $urls | Select-Object -Unique)
        }

        if ($urls.Count) { [IO.File]::WriteAllLines($path, [string[]]$urls) }
        elseif ($Finished -and (Test-Path -LiteralPath $path)) { Remove-Item -LiteralPath $path -Force }
    }
}

# Nothing left to download for these lists, so old failed files can go.
function Remove-FailedLists($Lists) {
    foreach ($list in $Lists) {
        $path = Get-FailedPathFor $list.FullName
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
}


# -------------------------- 3) Update yt-dlp -------------------------

function Update-YtDlp {
    Write-Header 'Update yt-dlp'
    $tools = Find-Tools
    if (-not $tools.YtDlp) {
        Write-Info "yt-dlp.exe not found in $(Join-Path $Dir.Tools 'yt-dlp')" Yellow
        Wait-Enter; return
    }
    Write-Info 'Old versions of yt-dlp are the most common reason downloads fail.'
    Write-Host ''
    try { Unblock-File -LiteralPath $tools.YtDlp -ErrorAction Stop } catch { }
    & $tools.YtDlp -U
    Wait-Enter
}


# ----------------------------- Main menu -----------------------------

function Show-MainMenu {
    $tools = Find-Tools
    $htmlCount = @(Get-HtmlFiles).Count
    $listCount = @(Get-ChildItem -LiteralPath $Dir.Lists -Filter '*.txt' -File).Count
    $songCount = @(Get-ChildItem -LiteralPath $Dir.Music -Filter '*.mp3' -File -Recurse -ErrorAction SilentlyContinue).Count

    Clear-Host
    Write-Host ''
    Write-Host '  ================================================' -ForegroundColor DarkCyan
    Write-Host '     YT Playlist Downloader' -ForegroundColor Cyan
    Write-Host '  ================================================' -ForegroundColor DarkCyan
    Write-Host "  Folder: $Root" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "   1)  Convert HTML files to link lists    ($htmlCount HTML files)"
    Write-Host "   2)  Download link lists as MP3          ($listCount lists, $songCount songs in Music)"
    Write-Host '   3)  Update yt-dlp'
    Write-Host '   Q)  Quit'
    Write-Host ''
    Write-ToolStatus $tools
}

function Start-App {
    try { $Host.UI.RawUI.WindowTitle = 'YT Playlist Downloader' } catch { }

    $script:Root = Get-ProjectRoot
    if (-not $script:Root) { return }
    Initialize-Folders
    Clear-Temp

    while ($true) {
        Show-MainMenu
        switch ((Read-Host "`n  Choose").Trim().ToUpper()) {
            '1' { Convert-HtmlFiles }
            '2' { Start-Downloads }
            '3' { Update-YtDlp }
            'Q' { return }
        }
    }
}

try { Start-App } catch { Write-Host "`n  Unexpected error: $_" -ForegroundColor Red; [void](Read-Host '  Press Enter to close') }
