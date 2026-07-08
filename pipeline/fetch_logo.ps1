# ============================================================
# fetch_logo.ps1 - Download a company logo from English Wikipedia
#
# Usage (run inside the pipeline folder):
#   .\fetch_logo.ps1 -Title "Hitachi" -No 21 -Slug "hitachi"
#
#   -Title : Article title on en.wikipedia.org (check the exact
#            title on the site first, e.g. "Toyota", "Sony Group")
#   -No    : Dictionary number = the "no" you wrote in data.js
#   -Slug  : Lowercase ascii name used for the file name
#
# Result: saves  assets/logos/NN_slug.png  (512px thumbnail)
# Then set  logo:"NN_slug"  in data.js and ALWAYS eyeball the PNG.
#
# How it picks the image:
#   1) files on the article that look like a logo (name contains
#      "logo", prefers ones that also contain the article title)
#   2) fallback: the article's lead image (can be a photo - check!)
#
# NOTE: this script is ASCII-only on purpose (PowerShell 5.1 has
# encoding pitfalls with non-ASCII script files).
# ============================================================
param(
  [Parameter(Mandatory=$true)][string]$Title,
  [Parameter(Mandatory=$true)][int]$No,
  [Parameter(Mandatory=$true)][string]$Slug
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# App root = parent of this script's folder
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$outDir = Join-Path $root "assets\logos"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }

$file = "{0:D2}_{1}" -f $No, $Slug.ToLower()
$out  = Join-Path $outDir ($file + ".png")
$ua   = @{ "User-Agent" = "ShukatsuJiten-LogoFetcher/1.1 (internal prototype; contact: team)" }
$base = "https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1"

function Get-FirstPage($res) {
  $pages = @($res.query.pages.PSObject.Properties | ForEach-Object { $_.Value })
  if (-not $pages) { return $null }
  return $pages[0]
}

# Wikipedia sometimes answers 429 (too many requests) - retry with a pause.
function Invoke-ApiWithRetry([string]$uri) {
  for ($i = 1; $i -le 4; $i++) {
    try { return Invoke-RestMethod -Uri $uri -Headers $ua }
    catch { if ($i -eq 4) { throw }; Write-Host ("  retry " + $i + "/3 (rate limited), waiting 10s...") -ForegroundColor Yellow; Start-Sleep -Seconds 10 }
  }
}
function Invoke-DownloadWithRetry([string]$uri, [string]$outFile) {
  for ($i = 1; $i -le 4; $i++) {
    try { Invoke-WebRequest -Uri $uri -Headers $ua -OutFile $outFile; return }
    catch { if ($i -eq 4) { throw }; Write-Host ("  retry " + $i + "/3 (rate limited), waiting 10s...") -ForegroundColor Yellow; Start-Sleep -Seconds 10 }
  }
}

# Rendered 512px thumbnail url for a "File:Xxx.svg" title.
# IMPORTANT: always use thumburl (SVG sources must be rendered to PNG).
function Get-ThumbUrl([string]$fileTitle) {
  $api = $base + "&prop=imageinfo&iiprop=url&iiurlwidth=512&titles=" + [uri]::EscapeDataString($fileTitle)
  $p = Get-FirstPage (Invoke-ApiWithRetry $api)
  if ($p -and $p.imageinfo) {
    if ($p.imageinfo[0].thumburl) { return $p.imageinfo[0].thumburl }
    return $p.imageinfo[0].url
  }
  return $null
}

Write-Host ("Searching en.wikipedia for: " + $Title)

# --- 1) look for a file whose name contains "logo" on the article ---
$thumb = $null; $picked = $null
$apiImgs = $base + "&prop=images&imlimit=200&titles=" + [uri]::EscapeDataString($Title)
$page = Get-FirstPage (Invoke-ApiWithRetry $apiImgs)
if ($page -and $page.PSObject.Properties["missing"]) {
  Write-Host "NG: article not found. Check the exact title on en.wikipedia.org" -ForegroundColor Red
  exit 1
}
if ($page -and $page.images) {
  $files = @($page.images | ForEach-Object { $_.title })
  # drop Wikipedia UI images (Commons logo, icons, stubs...)
  $files = $files | Where-Object { $_ -notmatch "(?i)commons-logo|wiki|oojs|symbol|icon|question|edit|padlock|increase|decrease|stub" }
  $logos = @($files | Where-Object { $_ -match "(?i)logo" -and $_ -match "(?i)\.(svg|png)$" })
  $firstWord = ($Title -split "[ ,\.]")[0]
  $best = @($logos | Where-Object { $_ -match [regex]::Escape($firstWord) })
  if ($best.Count -gt 0) { $picked = $best[0] } elseif ($logos.Count -gt 0) { $picked = $logos[0] }
  if ($picked) { $thumb = Get-ThumbUrl $picked }
}

# --- 2) fallback: the article's lead image (often a photo!) ---
if (-not $thumb) {
  $apiLead = $base + "&prop=pageimages&piprop=thumbnail%7Cname&pithumbsize=512&titles=" + [uri]::EscapeDataString($Title)
  $lead = Get-FirstPage (Invoke-ApiWithRetry $apiLead)
  if ($lead -and $lead.thumbnail) {
    $picked = "(lead image) " + $lead.pageimage
    $thumb  = $lead.thumbnail.source
    Write-Host "WARN: no logo-named file found; using the lead image. It may be a PHOTO." -ForegroundColor Yellow
  }
}

if (-not $thumb) {
  Write-Host "NG: no usable image found. Save the logo manually from the article page (512px)." -ForegroundColor Red
  exit 1
}

Invoke-DownloadWithRetry $thumb $out
$kb = [math]::Round((Get-Item $out).Length / 1KB)
Write-Host ""
Write-Host ("OK: saved " + $out + "  (" + $kb + " KB)") -ForegroundColor Green
Write-Host ("    picked     : " + $picked)
Write-Host ("    source url : " + $thumb)
Write-Host ""
Write-Host ("NEXT 1: set  logo:""" + $file + """  for this company in data.js")
Write-Host  "NEXT 2: OPEN THE PNG AND CHECK IT IS THE CORRECT, CURRENT LOGO"
Write-Host  "NEXT 3: run the validation page (the *.html file starting with underscore)"
