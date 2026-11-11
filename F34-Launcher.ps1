<#
  F34-Launcher.ps1 - Fallout 34 setup launcher.

    Double-click  F34-Launcher.cmd            (window, no console)
    or:  powershell -ExecutionPolicy Bypass -File .\F34-Launcher.ps1
    -Console = the old text menu.   -Step 1|2|3|4|A = run one step in this console (the window uses this).

  Steps it runs:  1 Downgrade FO4 to 1.10.984   2 Download the required mods from Nexus
                  3 Install them into FO4/FO3/FNV   4 Start the Fallout 34 converter
  Downloads use YOUR Nexus API key (typed into this window once, stored encrypted for your
  Windows user only).  Premium account = fully automatic.  Free account = Nexus only hands out a
  download link after you press "Slow download" on its page, so the launcher opens the 14 pages
  and catches each click itself (same mechanism Vortex / MO2 use) - no save dialogs, no sorting.
#>
param(
  [string]$Nxm,                                   # internal: nxm:// link handed over by the browser
  [string]$Step,                                  # run one step (1,2,3,4,A) in this console, then wait for Enter
  [switch]$Console,                               # text menu instead of the window
  [string]$Fo4,                                   # game folders: found through Steam when not given
  [string]$Fo3,
  [string]$Fnv,
  [string]$Root,                                  # working folder (downloads, backups, tools): this script's folder
  [string]$Inst,                                  # unpacked Fallout 34 installer folder: newest one found under $Root
  [string]$Docs                                   # Documents\My Games\Fallout4 (found through Windows, follows OneDrive)
)
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ------------------------------------------------------------------ locate everything
if (-not $Root) { $Root = $PSScriptRoot }
if (-not $Root) { $Root = (Get-Location).Path }
function Get-SteamRoot {
  foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam') {
    try { $v = (Get-ItemProperty $k -ErrorAction Stop); foreach ($n in 'SteamPath', 'InstallPath') { if ($v.$n -and (Test-Path $v.$n)) { return ($v.$n -replace '/', '\') } } } catch {}
  }
  return 'C:\Program Files (x86)\Steam'
}
function Find-SteamGame([string[]]$names) {
  $steam = Get-SteamRoot; $libs = @($steam)
  $vdf = "$steam\steamapps\libraryfolders.vdf"
  if (Test-Path $vdf) { $libs += (Select-String -Path $vdf -Pattern '"path"\s+"(.+?)"' -AllMatches).Matches | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' } }
  foreach ($l in ($libs | Select-Object -Unique)) { foreach ($n in $names) { $p = "$l\steamapps\common\$n"; if (Test-Path $p) { return $p } } }
  return ''
}
if (-not $Fo4) { $Fo4 = Find-SteamGame 'Fallout 4' }
if (-not $Fo3) { $Fo3 = Find-SteamGame 'Fallout 3 goty', 'Fallout 3' }
if (-not $Fnv) { $Fnv = Find-SteamGame 'Fallout New Vegas' }
if (-not $Inst) {                                 # newest unpacked installer (the folder holding Fallout34Setup.exe + installer.ini)
  $cand = Get-ChildItem $Root -Recurse -Depth 3 -Filter Fallout34Setup.exe -File -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.DirectoryName 'installer.ini') }
  $Inst = $cand | Sort-Object { $v = '0.0'; $f = Join-Path $_.DirectoryName 'VERSION'; if (Test-Path $f) { $v = [string](Get-Content $f | Select-Object -First 1) }; try { [version]$v.Trim() } catch { [version]'0.0' } } -Descending | Select-Object -First 1 -ExpandProperty DirectoryName
  if (-not $Inst) { $Inst = "$Root\Fallout34_Installer" }
}
$Missing = @(); if (-not ($Fo4 -and (Test-Path "$Fo4\Fallout4.exe"))) { $Missing += 'Fallout 4' }; if (-not ($Fo3 -and (Test-Path "$Fo3\Data"))) { $Missing += 'Fallout 3' }; if (-not ($Fnv -and (Test-Path "$Fnv\Data"))) { $Missing += 'Fallout: New Vegas' }
if ($Missing -and -not $Nxm) {
  $msg = "Could not find: $($Missing -join ', ').`nInstall them through Steam, or pass the folders:  -Fo4 <path> -Fo3 <path> -Fnv <path>"
  Write-Host $msg -ForegroundColor Red
  try { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show($msg, 'Fallout 34 Setup') } catch {}
  return
}

if (-not $Docs) { $Docs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Fallout4' }
$Stage = "$Root\F34_Downloads"; $Tools = "$Root\tools"; $Log = "$Tools\nxm.log"; $KeyFile = "$Tools\nexus.key"
$Want  = '1.10.984'
foreach ($d in $Tools, "$Stage\FO4", "$Stage\FO3", "$Stage\FNV", "$Stage\.installed") { New-Item -ItemType Directory $d -Force | Out-Null }
$GameDir = @{ FO4 = $Fo4; FO3 = $Fo3; FNV = $Fnv }

# game domain, mod id, file id, staging folder, label   (file ids looked up on Nexus 2026-11-10)
$Files = @(
  # c = a file that proves the mod is installed (relative to that game's folder). opt = only needed for that feature.
  @{ g='fallout4'; m=42147; f=316287;     d='FO4'; n='F4SE 0.7.2';                          c='f4se_loader.exe' }
  @{ g='fallout4'; m=47327; f=316411;     d='FO4'; n='Address Library 1.10.984';            c='Data\F4SE\Plugins\version-1-10-984-0.bin' }
  @{ g='fallout4'; m=64880; f=350591;     d='FO4'; n='Buffout4 NG 1.37.0';                  c='Data\F4SE\Plugins\Buffout4.dll' }
  @{ g='fallout4'; m=27216; f=321359;     d='FO4'; n='Extended Dialogue Interface 1.4.0';   c='Data\F4SE\Plugins\XDI.dll' }
  @{ g='fallout4'; m=44798; f=342947;     d='FO4'; n='High FPS Physics Fix NG 0.8.11';      c='Data\F4SE\Plugins\HighFPSPhysicsFix.dll' }
  @{ g='fallout4'; m=28822; f=318312;     d='FO4'; n='LevelUpMenuEx (prkf 1.10.984)';       c='Data\F4SE\Plugins\PRKF.dll' }
  @{ g='fallout4'; m=21497; f=316359;     d='FO4'; n='MCM 1.40 beta 2';                     c='Data\F4SE\Plugins\mcm.dll' }
  @{ g='fallout4'; m=48758; f=254844;     d='FO4'; n='FallUI - Inventory 2.2.1';            c='Data\MCM\Config\FallUI\config.json' }
  @{ g='fallout4'; m=29447; f=415750;     d='FO4'; n='Backpacks of the Commonwealth 2.1.3'; c='Data\Backpacks of the Commonwealth.esp' }
  @{ g='fallout3'; m=25911; f=1000025897; d='FO3'; n='FO3 ATMOS 1.2';                       c='Data\Interior Lighting.esp' }
  @{ g='fallout3'; m=5573;  f=1000016117; d='FO3'; n='FO3 DC Interiors combo 2.9.2';        c='Data\DCInteriors_ComboEdition.esm' }
  @{ g='fallout3'; m=8069;  f=72840;      d='FO3'; n='FO3 Street Lights v2';                c='Data\StreetLights.esm' }
  @{ g='newvegas'; m=35794; f=1000029961; d='FNV'; n='FNV Interior Lighting Overhaul 6.9';  c='Data\Interior Lighting Overhaul - Core.esm' }
  @{ g='newvegas'; m=74295; f=1000183826; d='FNV'; n='FNV Mesh Improvement Mod 1.14hf2';    c='Data\NVMIM.esp' }
  @{ g='fallout4'; m=105090; f=410383;    d='FO4'; n='Online: F4SE Menu Framework 1.53';    c='Data\F4SE\Plugins\F4SEMenuFramework.dll'; opt='online' }
  @{ g='fallout4'; m=29119;  f=379262;    d='FO4'; n='Online: FallSouls 1.2.0';             c='Data\F4SE\Plugins\FallSouls.dll';         opt='online' }
)
$Req = [ordered]@{
  'F4SE'='f4se_loader.exe'; 'F4SE scripts'='Data\Scripts\F4SE.pex'
  'Address Library'='Data\F4SE\Plugins\version-1-10-984-0.bin'
  'Buffout 4'='Data\F4SE\Plugins\Buffout4.dll'; 'XDI'='Data\F4SE\Plugins\XDI.dll'
  'High FPS Physics Fix'='Data\F4SE\Plugins\HighFPSPhysicsFix.dll'
  'LevelUpMenuEx'='Data\F4SE\Plugins\PRKF.dll'; 'MCM'='Data\F4SE\Plugins\mcm.dll'
  'FallUI'='Data\MCM\Config\FallUI\config.json'
}

# Install choices for the archives that ship an option menu (FOMOD). s = path inside the user's own download,
# d = where it goes in the game folder. Nothing from these mods is shipped with the launcher.
$Presets = @{
  48758 = @(                                      # FallUI - Inventory: main files + default settings, NO M8rDisablePipboyEffects
    @{ s = 'FallUI - Inventory\Interface';     d = 'Data\Interface' }
    @{ s = 'FallUI - Inventory\MCM\Config';    d = 'Data\MCM\Config' }
    @{ s = 'Settings\FallUI-withPipboyFX.ini'; d = 'Data\MCM\Settings\FallUI.ini' }
  )
  29447 = @(                                      # Backpacks of the Commonwealth: core + "Scripted Leveled List Inject (Recommended)"
    @{ s = 'Backpacks of the Commonwealth - Main.ba2';     d = 'Data\Backpacks of the Commonwealth - Main.ba2' }
    @{ s = 'Backpacks of the Commonwealth - Textures.ba2'; d = 'Data\Backpacks of the Commonwealth - Textures.ba2' }
    @{ s = 'Backpacks of the Commonwealth.esp';            d = 'Data\Backpacks of the Commonwealth.esp' }
  )
  35794 = @(                                      # FNV Interior Lighting Overhaul: every plugin named in the converter's build_profiles.json
    @{ s = 'core\Interior Lighting Overhaul - Core.esm';              d = 'Data\Interior Lighting Overhaul - Core.esm' }
    @{ s = 'core\Interior Lighting Overhaul - Core.bsa';              d = 'Data\Interior Lighting Overhaul - Core.bsa' }
    @{ s = 'core\Interior Lighting Overhaul - Ultimate Edition.esp';  d = 'Data\Interior Lighting Overhaul - Ultimate Edition.esp' }
    @{ s = 'core\ILO - Fallout New Vegas.esp';                        d = 'Data\ILO - Fallout New Vegas.esp' }
    @{ s = 'extras\Interior Lighting Overhaul - L38PS.esm';           d = 'Data\Interior Lighting Overhaul - L38PS.esm' }
    @{ s = 'dlc_support\ILO - Dead Money.esp';                        d = 'Data\ILO - Dead Money.esp' }
    @{ s = 'dlc_support\ILO - Honest Hearts.esp';                     d = 'Data\ILO - Honest Hearts.esp' }
    @{ s = 'dlc_support\ILO - Old World Blues.esp';                   d = 'Data\ILO - Old World Blues.esp' }
    @{ s = 'dlc_support\ILO - Lonesome Road.esp';                     d = 'Data\ILO - Lonesome Road.esp' }
  )
}

# ------------------------------------------------------------------ helpers
function Get-Fo4Version { if (Test-Path "$Fo4\Fallout4.exe") { (Get-Item "$Fo4\Fallout4.exe").VersionInfo.FileVersion } else { 'NOT FOUND' } }
function Get-FreeGB($p) { [math]::Round((Get-PSDrive (Get-Item $p).PSDrive.Name).Free / 1GB) }
function Get-Staged($e) { Get-ChildItem "$Stage\$($e.d)" -File -Filter "$($e.m)__*" -ErrorAction SilentlyContinue | Where-Object Extension -ne '.part' | Select-Object -First 1 }
function Test-Online    { return (Test-Path "$Fo4\Data\F4SE\Plugins\F34Online.dll") }            # Fallout 34 Online switched on
function Test-Installed($e) { return (Test-Path (Join-Path $GameDir[$e.d] $e.c)) }
function Get-Wanted     { return @($Files | Where-Object { -not $_.opt -or ($_.opt -eq 'online' -and (Test-Online)) }) }
function Get-Broken     { return @(Get-Wanted | Where-Object { -not (Test-Installed $_) }) }             # wanted but not in the game folder
function Get-ModState($e) {
  if ($e.opt -eq 'online' -and -not (Test-Online)) { return 'not needed' }
  if (Test-Installed $e) { return 'installed' }
  if (Get-Staged $e) { return 'downloaded' }
  if (Test-Path "$Stage\$($e.d)\$($e.m)__*.part") { return 'downloading...' }
  return 'MISSING'
}
function Test-GameRunning { return [bool](Get-Process -Name Fallout4 -ErrorAction SilentlyContinue) }
function Set-IniValue($path, $section, $key, $value) {      # set one key, keep everything else as it is
  $lines = @(); if (Test-Path $path) { $lines = @(Get-Content $path) }
  $out = New-Object System.Collections.Generic.List[string]; $in = $false; $done = $false; $found = $false
  foreach ($l in $lines) {
    if ($l -match '^\s*\[(.+?)\]\s*$') {
      if ($in -and -not $done) { $out.Add("$key=$value"); $done = $true }
      $in = ($Matches[1] -ieq $section); if ($in) { $found = $true }
      $out.Add($l); continue
    }
    if ($in -and -not $done -and $l -match ('^\s*' + [regex]::Escape($key) + '\s*=')) { $out.Add("$key=$value"); $done = $true; continue }
    $out.Add($l)
  }
  if (-not $done) { if (-not $found) { $out.Add("[$section]") }; $out.Add("$key=$value") }
  Set-Content $path $out
}
function Backup-Once($path) {
  if (-not (Test-Path $path)) { return }
  if (-not (Test-Path "$path.pre-fix")) { Copy-Item $path "$path.pre-fix" }
  $it = Get-Item $path; if ($it.IsReadOnly) { $it.IsReadOnly = $false }
}
function Test-FixesApplied { return ((Test-Path "$Docs\Fallout4Custom.ini") -and [bool](Select-String -Path "$Docs\Fallout4Custom.ini" -Pattern '^\s*bAlwaysActive\s*=\s*1' -Quiet)) }
function Set-PluginActive($name, [bool]$on) {                # Fallout 4 plugins.txt: "*Name" = active, "Name" = inactive
  $pt = "$env:LOCALAPPDATA\Fallout4\plugins.txt"; New-Item -ItemType Directory (Split-Path $pt) -Force | Out-Null
  $lines = @(); if (Test-Path $pt) { $lines = @(Get-Content $pt) }
  $rx = '^\*?' + [regex]::Escape($name) + '\s*$'; $want = $name; if ($on) { $want = "*$name" }
  if ($lines | Where-Object { $_ -match $rx }) { $lines = $lines | ForEach-Object { if ($_ -match $rx) { $want } else { $_ } } }
  else { $lines += $want }
  Set-Content $pt $lines
}
function Get-MissingReqs { @($Req.GetEnumerator() | Where-Object { -not (Test-Path (Join-Path $Fo4 $_.Value)) }) }
function Say($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Test-ConverterRunning { return [bool](Get-Process -Name Fallout34Setup, f34conv -ErrorAction SilentlyContinue) }
function Get-ConverterStage {                     # "FNV: meshes | FO3: plugin" from the converter's own logs
  $parts = @()
  foreach ($w in "$Root\Fallout34_Work", "$Fo4\Fallout34_Work") {
    foreach ($g in 'fnv', 'fo3') {
      $log = "$w\$g\convert.log"
      if (-not (Test-Path $log)) { continue }
      $line = Get-Content $log -Tail 80 -ErrorAction SilentlyContinue | Where-Object { $_ -like '=== *' } | Select-Object -Last 1
      $stage = 'starting'
      if ($line) { $stage = ($line.Substring(4) -split ':')[0].Trim() }
      $parts += ('{0}: {1}' -f $g.ToUpper(), $stage)
    }
    if ($parts) { break }
  }
  return ($parts -join '   |   ')
}

function Get-ApiKey([switch]$Ask) {
  if (-not (Test-Path $KeyFile)) {
    if (-not $Ask) { return $null }
    Say "`nNexus API key needed (once). Get it here - scroll to the bottom, 'Personal API Key':" Yellow
    Say '  https://www.nexusmods.com/users/myaccount?tab=api+access'
    Start-Process 'https://www.nexusmods.com/users/myaccount?tab=api+access'
    $ss = Read-Host 'Paste the key here (input is hidden)' -AsSecureString
    $ss | ConvertFrom-SecureString | Set-Content $KeyFile
  }
  $ss = Get-Content $KeyFile | ConvertTo-SecureString
  [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss))
}
function Invoke-Nexus($path) {
  Invoke-RestMethod "https://api.nexusmods.com/v1/$path" -Headers @{ apikey = (Get-ApiKey); 'User-Agent' = 'F34Launcher/1.0'; 'Application-Name' = 'F34Launcher'; 'Application-Version' = '1.0' }
}
function Save-NexusFile($e, $query) {          # $query = '' (premium) or '?key=..&expires=..' (free, from nxm link)
  $info = Invoke-Nexus "games/$($e.g)/mods/$($e.m)/files/$($e.f).json"
  $link = @(Invoke-Nexus "games/$($e.g)/mods/$($e.m)/files/$($e.f)/download_link.json$query")[0].URI
  $name = ($info.file_name -replace '[\\/:*?"<>|]', '_')
  $dest = "$Stage\$($e.d)\$($e.m)__$name"
  (New-Object Net.WebClient).DownloadFile($link, "$dest.part")
  Move-Item "$dest.part" $dest -Force
  $dest
}

# ------------------------------------------------------------------ nxm:// handler mode (started by the browser)
if ($Nxm) {
  try {
    if ($Nxm -notmatch '^nxm://([^/]+)/mods/(\d+)/files/(\d+)\?(.+)$') { throw "unrecognised link: $Nxm" }
    $g = $Matches[1].ToLower(); $m = [int]$Matches[2]; $f = [long]$Matches[3]; $q = @{}
    $Matches[4] -split '&' | ForEach-Object { $kv = $_ -split '=', 2; $q[$kv[0]] = $kv[1] }
    $e = $Files | Where-Object { $_.g -eq $g -and $_.m -eq $m } | Select-Object -First 1
    if (-not $e) { $e = @{ g = $g; m = $m; f = $f; d = 'Other'; n = "mod $m" }; New-Item -ItemType Directory "$Stage\Other" -Force | Out-Null }
    else { $e = $e.Clone(); $e.f = $f }
    Add-Content $Log "$(Get-Date -f T) start  $($e.n)"
    $p = Save-NexusFile $e "?key=$($q.key)&expires=$($q.expires)"
    Add-Content $Log "$(Get-Date -f T) done   $p"
  } catch { Add-Content $Log "$(Get-Date -f T) ERROR  $Nxm :: $($_.Exception.Message)" }
  return
}

# ------------------------------------------------------------------ status
function Show-Status {
  Clear-Host
  Say '================  FALLOUT 34 LAUNCHER  ================' Cyan
  $v = Get-Fo4Version
  Say ("Fallout 4 version : {0}" -f $v) $(if ($v -like "$Want*") {'Green'} else {'Red'})
  Say ("Free space        : {0}: {1} GB    {2}: {3} GB" -f (Get-Item $Fo4).PSDrive.Name, (Get-FreeGB $Fo4), (Get-Item $Root).PSDrive.Name, (Get-FreeGB $Root))
  Say "`nDownloads / installs:"
  foreach ($e in $Files) {
    $s = Get-ModState $e
    Say ("  {0,-40} {1}" -f $e.n, $s) $(if ($s -eq 'installed') {'Green'} elseif ($s -eq 'MISSING') {'Red'} elseif ($s -eq 'not needed') {'DarkGray'} else {'Yellow'})
  }
  Say "`nFiles the Fallout 34 installer checks for:"
  foreach ($r in $Req.GetEnumerator()) { $ok = Test-Path (Join-Path $Fo4 $r.Value); Say ("  {0,-40} {1}" -f $r.Key, $(if ($ok) {'OK'} else {'MISSING'})) $(if ($ok) {'Green'} else {'Red'}) }
  Say ''
}

# ------------------------------------------------------------------ 1. downgrade
function Do-Downgrade {
  $v = Get-Fo4Version
  if ($v -like "$Want*") { Say 'Already on 1.10.984.' Green; return }
  if (Get-Process Fallout4 -ErrorAction SilentlyContinue) { throw 'Close Fallout 4 first.' }
  $dd = "$Tools\DepotDownloader"
  if (-not (Test-Path "$dd\DepotDownloader.exe")) {
    Say 'Getting DepotDownloader from GitHub...'
    $rel = Invoke-RestMethod 'https://api.github.com/repos/SteamRE/DepotDownloader/releases/latest' -Headers @{ 'User-Agent' = 'F34Launcher' }
    $a = $rel.assets | Where-Object name -match 'windows-x64\.zip$' | Select-Object -First 1
    New-Item -ItemType Directory $dd -Force | Out-Null
    Invoke-WebRequest $a.browser_download_url -OutFile "$dd\dd.zip" -UseBasicParsing
    Expand-Archive "$dd\dd.zip" $dd -Force; Remove-Item "$dd\dd.zip"
  }
  $user = Read-Host 'Steam account name (login name)'
  $depots = [ordered]@{ '377162'='5698952341602575696'; '377161'='7332110922360867314'; '377163'='8681102885670959037'; '377164'='8492427313392140315'
                        '435870'='1213339795579796878'; '435871'='7785009542965564688'; '435880'='366079256218893805'; '393885'='5000262035721758737' }
  $dl = "$Root\F34_Depots"; $got = @()
  Say 'DepotDownloader asks for your Steam password / Steam Guard once. Type them yourself.' Yellow
  foreach ($d in $depots.Keys) {
    & "$dd\DepotDownloader.exe" -app 377160 -depot $d -manifest $depots[$d] -username $user -remember-password -dir "$dl\depot_$d"
    if ($LASTEXITCODE -eq 0) { $got += $d } else { Write-Warning "depot $d skipped" }
  }
  if ($got -notcontains '377162') { throw 'exe depot did not download - nothing changed.' }
  if (Get-Process steam -ErrorAction SilentlyContinue) { & "$(Get-SteamRoot)\steam.exe" -shutdown; Start-Sleep 12 }
  New-Item -ItemType Directory "$Root\Backup_AE" -Force | Out-Null
  Copy-Item "$Fo4\Fallout4.exe" "$Root\Backup_AE\Fallout4_$v.exe" -Force
  foreach ($d in $got) { robocopy "$dl\depot_$d" $Fo4 /E /MOV /XD '.DepotDownloader' /NFL /NDL /NJH /NJS /NP | Out-Null }
  $acf = Join-Path (Split-Path (Split-Path $Fo4)) 'appmanifest_377160.acf'
  if (Test-Path $acf) { (Get-Content $acf -Raw) -replace '("AutoUpdateBehavior"\s+)"\d"', '$1"1"' | Set-Content $acf -NoNewline }
  Say "Fallout 4 is now $(Get-Fo4Version)" Green
}

# ------------------------------------------------------------------ 2. downloads
function Set-NxmHandler([switch]$Restore) {
  $k = 'HKCU:\Software\Classes\nxm'; $prev = "$Tools\nxm_prev.txt"
  if ($Restore) {
    if (-not (Test-Path $prev)) { return }
    $old = [string](Get-Content $prev -Raw)
    if ($old.Trim()) { Set-Item "$k\shell\open\command" -Value $old.Trim() } else { Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item $prev; return
  }
  if (-not (Test-Path $prev)) {
    $old = ''; if (Test-Path "$k\shell\open\command") { $old = (Get-Item "$k\shell\open\command").GetValue('') }
    Set-Content $prev $old
  }
  New-Item "$k\shell\open\command" -Force | Out-Null
  Set-Item $k -Value 'URL:NXM Protocol'
  New-ItemProperty $k -Name 'URL Protocol' -Value '' -Force | Out-Null
  Set-Item "$k\shell\open\command" -Value ('"{0}\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" -Nxm "%1"' -f $env:WINDIR, $PSCommandPath)
}
function Do-Download {
  $todo = @(Get-Broken | Where-Object { -not (Get-Staged $_) })
  if (-not $todo) { Say 'Nothing to download.' Green; return }
  $null = Get-ApiKey -Ask
  try { $me = Invoke-Nexus 'users/validate.json' } catch { Remove-Item $KeyFile -ErrorAction SilentlyContinue; throw "Nexus rejected that API key: $($_.Exception.Message)" }
  Say ("Nexus account: {0}  (premium: {1})" -f $me.name, $me.is_premium)

  if ($me.is_premium) {
    foreach ($e in $todo) { Say "downloading $($e.n) ..."; try { $null = Save-NexusFile $e '' } catch { Write-Warning "$($e.n): $($_.Exception.Message)" } }
    return
  }

  Say "`nFree account: Nexus requires one 'Slow download' click per file ($($todo.Count) left)." Yellow
  Say "Tabs open one at a time. Click SLOW DOWNLOAD; the next tab opens by itself when the click is detected."
  Say "First time the browser asks to open PowerShell: tick 'always allow' and accept."
  Read-Host 'Press Enter to start' | Out-Null
  Set-NxmHandler
  try {
    # one tab at a time: the next page opens by itself as soon as the click on the current one is detected
    $opened = @{}
    while ($true) {
      $next = $todo | Where-Object { -not (Get-Staged $_) -and -not (Test-Path "$Stage\$($_.d)\$($_.m)__*.part") } | Select-Object -First 1
      if ($next -and -not $opened[$next.m]) {
        $opened[$next.m] = $true
        Start-Process "https://www.nexusmods.com/$($next.g)/mods/$($next.m)?tab=files&file_id=$($next.f)&nmm=1"
      }
      Clear-Host; Say 'Click SLOW DOWNLOAD in the tab that just opened - the next tab opens by itself.   R = reopen tab   Q = stop' Cyan
      $left = 0
      foreach ($e in $todo) {
        $done = [bool](Get-Staged $e); $part = Test-Path "$Stage\$($e.d)\$($e.m)__*.part"
        if (-not $done) { $left++ }
        $st = if ($done) {'done'} elseif ($part) {'downloading...'} elseif ($next -and $e.m -eq $next.m) {'>>> CLICK SLOW DOWNLOAD <<<'} else {'queued'}
        Say ("  {0,-40} {1}" -f $e.n, $st) $(if ($done) {'Green'} elseif ($part) {'Yellow'} elseif ($st -ne 'queued') {'White'} else {'DarkGray'})
      }
      if ([Console]::KeyAvailable) { $k = [Console]::ReadKey($true).Key; if ($k -eq 'Q') { break }; if ($k -eq 'R' -and $next) { $opened.Remove($next.m) } }
      if (Test-Path $Log) { $err = @(Get-Content $Log -Tail 30 | Where-Object { $_ -match 'ERROR' }) | Select-Object -Last 3; if ($err) { Say "`nErrors:" Red; $err | ForEach-Object { Say "  $_" Red } } }
      if (-not $left) { break }
      Start-Sleep 2
    }
  } finally { Set-NxmHandler -Restore }
}

# ------------------------------------------------------------------ 3. install
function Do-Install {
  if ((Get-Fo4Version) -notlike "$Want*") { throw 'Downgrade first.' }
  $7z = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $7z) { Say 'Installing 7-Zip...'; winget install --id 7zip.7zip -e --silent --accept-source-agreements --accept-package-agreements | Out-Null; $7z = "$env:ProgramFiles\7-Zip\7z.exe" }
  if (-not (Test-Path $7z)) { throw '7-Zip is not installed.' }
  $7z = (Get-Item $7z).FullName; $sep = [IO.Path]::DirectorySeparatorChar
  $markers = 'meshes','textures','sound','music','scripts','interface','f4se','mcm','materials','strings','menus','shaders','lodsettings','video'
  $manual = @()
  foreach ($e in (Get-Broken)) {
    $a = Get-Staged $e
    if (-not $a) { Say "not downloaded yet: $($e.n)" Yellow; continue }
    $ready = "$Stage\_ready\$($e.m)"          # install choices already made (folder laid out like the game folder)
    if (Test-Path $ready) {
      robocopy $ready $GameDir[$e.d] /E /NFL /NDL /NJH /NJS /NP | Out-Null
      if ($LASTEXITCODE -ge 8) { throw "copy failed for $($e.n)" }
      Set-Content "$Stage\.installed\$($e.m)" "$(Get-Date -f s) $ready -> $($GameDir[$e.d])"
      Remove-Item "$Stage\_x\$($e.m)" -Recurse -Force -ErrorAction SilentlyContinue
      Say "installed  $($e.n)  ->  $($GameDir[$e.d])  (preset choices)" Green; continue
    }
    $tmp = "$Stage\_x\$($e.m)"; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    & $7z x $a.FullName "-o$tmp" -y | Out-Null
    Get-ChildItem $tmp -Recurse -File -Filter *.fomod | ForEach-Object { & $7z x $_.FullName "-o$(Join-Path $tmp '_fomod')" -y | Out-Null }   # old-style nested package
    if ($Presets.ContainsKey($e.m)) {
      $all = @(Get-ChildItem $tmp -Recurse); $bad = $null; $plan = @()
      foreach ($pz in $Presets[$e.m]) {
        $want = $sep + ($pz.s -replace '\\', $sep)
        $hit = $all | Where-Object { $_.FullName.EndsWith($want, [StringComparison]::OrdinalIgnoreCase) } | Sort-Object { $_.FullName.Length } | Select-Object -First 1
        if (-not $hit) { $bad = $pz.s; break }
        $plan += ,@($hit, (Join-Path $GameDir[$e.d] $pz.d))
      }
      if ($bad) { $manual += "$($e.n)  (this version of the archive has no '$bad' - install it by hand)  -> $tmp"; continue }
      foreach ($pl in $plan) {
        if ($pl[0].PSIsContainer) { robocopy $pl[0].FullName $pl[1] /E /NFL /NDL /NJH /NJS /NP | Out-Null; if ($LASTEXITCODE -ge 8) { throw "copy failed for $($e.n)" } }
        else { New-Item -ItemType Directory (Split-Path $pl[1]) -Force | Out-Null; Copy-Item $pl[0].FullName $pl[1] -Force }
      }
      Set-Content "$Stage\.installed\$($e.m)" "$(Get-Date -f s) preset -> $($GameDir[$e.d])"
      Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
      Say "installed  $($e.n)  ->  $($GameDir[$e.d])  (preset choices)" Green; continue
    }
    if (Get-ChildItem $tmp -Recurse -Filter ModuleConfig.xml -ErrorAction SilentlyContinue) { $manual += "$($e.n)  (has install options)  -> $tmp"; continue }
    $dirs = @(Get-Item $tmp) + @(Get-ChildItem $tmp -Recurse -Directory) | Sort-Object { $_.FullName.Length }
    $src = $null; $dst = $null
    $r = $dirs | Where-Object { (Test-Path "$($_.FullName)\Data") -or (Get-ChildItem $_.FullName -File -Filter '*_loader.exe' -ErrorAction SilentlyContinue) } | Select-Object -First 1
    if ($r) { $src = $r.FullName; $dst = $GameDir[$e.d] }
    else {
      $dd = $dirs | Where-Object {
        (Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue | Where-Object Extension -in '.esp','.esm','.esl','.ba2','.bsa') -or
        (Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue | Where-Object { $markers -contains $_.Name.ToLower() }) } | Select-Object -First 1
      if ($dd) { $src = $dd.FullName; $dst = Join-Path $GameDir[$e.d] 'Data' }
    }
    if (-not $src) { $manual += "$($e.n)  (layout not recognised)  -> $tmp"; continue }
    robocopy $src $dst /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "copy failed for $($e.n)" }
    Set-Content "$Stage\.installed\$($e.m)" "$(Get-Date -f s) $src -> $dst"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Say "installed  $($e.n)  ->  $dst" Green
  }
  foreach ($e in (Get-Broken)) {                              # unpacked but the expected file did not appear
    if ((Get-Staged $e) -and -not ($manual | Where-Object { $_.StartsWith($e.n) })) { $manual += "$($e.n)  (unpacked, but '$($e.c)' is not in the game folder - check the archive by hand)" }
  }
  if ($manual) { Say "`nThese were NOT installed - install them by hand from the extracted folders shown:" Yellow; $manual | ForEach-Object { Say "  $_" Yellow }; $manual | Set-Content "$Stage\needs_manual.txt" }
  else { Remove-Item "$Stage\needs_manual.txt" -ErrorAction SilentlyContinue }
  Enable-Plugins
}
function Enable-Plugins {
  Set-OldGamePlugins 'Fallout3' $Fo3 @('Fallout3.esm','Anchorage.esm','ThePitt.esm','BrokenSteel.esm','PointLookout.esm','Zeta.esm')
  Set-OldGamePlugins 'FalloutNV' $Fnv @('FalloutNV.esm','DeadMoney.esm','HonestHearts.esm','OldWorldBlues.esm','LonesomeRoad.esm','GunRunnersArsenal.esm','ClassicPack.esm','MercenaryPack.esm','TribalPack.esm','CaravanPack.esm')
  # Fallout 4: enable Backpacks (the F34 installer only activates its own plugins + XDI)
  $p4 = "$env:LOCALAPPDATA\Fallout4\plugins.txt"; $bp = 'Backpacks of the Commonwealth.esp'
  if ((Test-Path "$Fo4\Data\$bp") -and -not ((Test-Path $p4) -and (Select-String -Path $p4 -Pattern $bp -SimpleMatch -Quiet))) {
    New-Item -ItemType Directory (Split-Path $p4) -Force | Out-Null
    $cur = ''; if (Test-Path $p4) { $cur = [string](Get-Content $p4 -Raw) }
    if ($cur -and -not $cur.EndsWith("`n")) { Add-Content $p4 '' }      # never glue onto an unterminated last line
    Add-Content $p4 "*$bp"; Say "enabled $bp in Fallout 4 plugins.txt" Green
  }
}
function Set-OldGamePlugins($name, $dir, $official) {      # FO3 / FNV: every plugin in Data enabled, official files first
  $all  = @(Get-ChildItem "$dir\Data" -File | Where-Object Extension -in '.esm','.esp' | ForEach-Object Name)
  $list = @($official | Where-Object { $all -contains $_ }) +
          @($all | Where-Object { $official -notcontains $_ -and $_ -like '*.esm' } | Sort-Object) +
          @($all | Where-Object { $_ -like '*.esp' } | Sort-Object)
  $pt = "$env:LOCALAPPDATA\$name\plugins.txt"
  New-Item -ItemType Directory (Split-Path $pt) -Force | Out-Null
  if ((Test-Path $pt) -and -not (Test-Path "$pt.pre-F34")) { Copy-Item $pt "$pt.pre-F34" }
  Set-Content $pt $list -Encoding ASCII
  Say "$name plugins.txt: $($list.Count) plugins enabled" Green
}

# ------------------------------------------------------------------ 4. run the converter
function Do-Run {
  if (Test-ConverterRunning) { throw 'The Fallout 34 converter is already running. Let it finish (or close its window) first.' }
  if ((Get-Fo4Version) -notlike "$Want*") { throw 'Downgrade first.' }
  $miss = Get-MissingReqs
  if ($miss) { throw ('Still missing: ' + (($miss | ForEach-Object Key) -join ', ')) }
  if (-not (Test-Path "$Inst\Fallout34Setup.exe")) { throw "Installer not found: $Inst" }
  Say "Installer: $Inst  (version $((Get-Content "$Inst\VERSION" -ErrorAction SilentlyContinue | Select-Object -First 1)))"
  $bak = "$Root\Backup_preF34"; New-Item -ItemType Directory $bak -Force | Out-Null      # backups first, never overwritten
  if ((Test-Path "$env:LOCALAPPDATA\Fallout4\plugins.txt") -and -not (Test-Path "$bak\plugins.txt")) { Copy-Item "$env:LOCALAPPDATA\Fallout4\plugins.txt" $bak }
  if (-not (Test-Path "$bak\MyGames_Fallout4")) { robocopy $Docs "$bak\MyGames_Fallout4" /E /NFL /NDL /NJH /NJS /NP | Out-Null }
  Enable-Plugins
  $ini = "$Inst\installer.ini"; if (-not (Test-Path "$ini.orig")) { Copy-Item $ini "$ini.orig" }
  $t = Get-Content $ini -Raw
  $t = $t -replace '(?m)^Fallout4=[^\r\n]*', "Fallout4=$Fo4" -replace '(?m)^Fallout3=[^\r\n]*', "Fallout3=$Fo3" -replace '(?m)^FalloutNV=[^\r\n]*', "FalloutNV=$Fnv"
  if ((Get-FreeGB $Fo4) -lt 110 -and (Get-FreeGB $Root) -gt (Get-FreeGB $Fo4)) {
    New-Item -ItemType Directory "$Root\Fallout34_Work" -Force | Out-Null
    $t = $t -replace '(?m)^WorkFolder=[^\r\n]*', "WorkFolder=$Root\Fallout34_Work"; Say "Work folder -> $Root\Fallout34_Work"
  }
  Set-Content $ini $t -NoNewline
  Say 'Starting the Fallout 34 installer (2-4 hours, close everything else)...' Cyan
  Start-Process "$Inst\Fallout34Setup.exe" -WorkingDirectory $Inst -Wait
  $out = @(Get-ChildItem "$Fo4\Data" -File | Where-Object Name -match '34' )
  if ($out | Where-Object Name -eq 'Fallout34.esm') {
    $out | Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB) } } | Format-Table -AutoSize | Out-Host
    Say 'Converted files are in place.' Green
    try { Do-Fixes } catch { Say "Game fixes not applied: $($_.Exception.Message)" Yellow }
    Say 'Start the game with f4se_loader.exe (PLAY button).' Green
  } else {
    Say 'Fallout34.esm is NOT in Fallout 4\Data. If the setup window is still open, let it finish; if it closed, it was cancelled or failed.' Yellow
    Say "Logs: look in the work folder ($Root\Fallout34_Work or <Fallout 4>\Fallout34_Work) and check the last lines of convert.log there." Yellow
  }
}

# ------------------------------------------------------------------ maintenance: repair, game fixes, online switch
function Do-Repair {                                         # anything wanted that is not in the game folder: download + install
  $b = Get-Broken
  if (-not $b) { Say 'All mods are in place.' Green; return }
  Say ("Missing from the game folders: " + (($b | ForEach-Object n) -join ', ')) Yellow
  Do-Download; Do-Install
  $b = Get-Broken
  if ($b) { Say ("Still missing: " + (($b | ForEach-Object n) -join ', ')) Red } else { Say 'All mods are in place.' Green }
}
function Do-Fixes {                                          # settings the game needs to behave with Fallout 34
  if (Test-GameRunning) { throw 'Close Fallout 4 first.' }
  if (-not (Test-Path $Docs)) { throw "Fallout 4 settings folder not found: $Docs  (start the game once from Steam's launcher, then retry)" }
  $custom = "$Docs\Fallout4Custom.ini"; $prefs = "$Docs\Fallout4Prefs.ini"; $ini = "$Docs\Fallout4.ini"
  Backup-Once $custom; Set-IniValue $custom 'General' 'bAlwaysActive' '1'
  Say 'bAlwaysActive=1   (the game keeps running when it is not the active window)' Green
  if (Test-Path $prefs) {
    Backup-Once $prefs; Set-IniValue $prefs 'Display' 'bFull Screen' '0'; Set-IniValue $prefs 'Display' 'bBorderless' '1'
    Say 'borderless window (exclusive fullscreen can leave a black screen at startup)' Green
  }
  if (-not (Test-Path "$Fo4\Data\LondonWorldSpace.esm")) {  # leftovers of an uninstalled Fallout London
    if ((Test-Path $ini) -and (Select-String -Path $ini -Pattern 'LondonWorldSpace' -Quiet)) {
      Backup-Once $ini; (Get-Content $ini) -replace ',\s*LondonWorldSpace[^,]*', '' | Set-Content $ini
      Say 'removed Fallout London archive entries from Fallout4.ini' Green
    }
    $pt = "$env:LOCALAPPDATA\Fallout4\plugins.txt"
    if ((Test-Path $pt) -and (Select-String -Path $pt -Pattern 'LondonWorldSpace' -Quiet)) {
      Backup-Once $pt; (Get-Content $pt) | Where-Object { $_ -notmatch 'LondonWorldSpace' } | Set-Content $pt
      Say 'removed Fallout London plugins from plugins.txt' Green
    }
  }
}
function Do-BlackScreenFix {                                 # game stuck on a black screen: close it, fix the settings, start it again
  if (Test-GameRunning) {
    Say 'This closes Fallout 4. Anything not saved is lost.' Yellow
    Read-Host 'Press Enter to continue (or close this window to cancel)' | Out-Null
    Stop-Process -Name Fallout4 -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20 -and (Test-GameRunning); $i++) { Start-Sleep -Milliseconds 500 }
    if (Test-GameRunning) { throw 'Fallout 4 would not close. End it in Task Manager and try again.' }
  }
  Do-Fixes
  if (-not (Test-Path "$Fo4\f4se_loader.exe")) { throw 'f4se_loader.exe is missing - press REPAIR MODS.' }
  Start-Process "$Fo4\f4se_loader.exe" -WorkingDirectory $Fo4
  Say 'Fallout 4 is starting. Click into the game window and leave it in front; the first load can take a minute or two.' Green
}
function Do-ToggleOnline {                                   # Fallout 34 Online on/off without re-running the converter
  if (Test-GameRunning) { throw 'Close Fallout 4 first.' }
  $dll = "$Fo4\Data\F4SE\Plugins\F34Online.dll"; $off = "$dll.off"
  if (Test-Path $dll) {
    Remove-Item $off -Force -ErrorAction SilentlyContinue; Rename-Item $dll 'F34Online.dll.off'
    Set-PluginActive 'F34Online.esp' $false
    Say 'Fallout 34 Online is OFF (single-player: VATS and pausing work normally).' Green
  } else {
    if (Test-Path $off) { Rename-Item $off 'F34Online.dll' }
    else {
      $src = "$Inst\files\optional\f34online"
      if (-not (Test-Path $src)) { throw "Online files not found in the installer: $src" }
      robocopy $src $Fo4 /E /NFL /NDL /NJH /NJS /NP | Out-Null
      if ($LASTEXITCODE -ge 8) { throw 'copying the Online files failed' }
    }
    Set-PluginActive 'F34Online.esp' $true
    Say 'Fallout 34 Online is ON.' Green
    if (Get-Broken) { Say 'It needs F4SE Menu Framework and FallSouls - getting them now.' Yellow; Do-Repair }
  }
}

# ------------------------------------------------------------------ step runner / what is next
function Invoke-Step($c) {
  switch ($c) {
    'R' { Do-Repair }
    'F' { Do-Fixes }
    'B' { Do-BlackScreenFix }
    'O' { Do-ToggleOnline }
    '1' { Do-Downgrade }
    '2' { Do-Download }
    '3' { Do-Install }
    '4' { Do-Run }
    'A' {
      Do-Downgrade; Do-Download; Do-Install
      if ((Test-Path "$Stage\needs_manual.txt") -or (Get-MissingReqs)) { Say "`nStopped before the converter: something still needs attention (see above / status)." Yellow }
      else { Do-Run }
    }
  }
}
function Get-NextStep {
  if ((Get-Fo4Version) -notlike "$Want*") { return @{ s = '1'; t = 'Downgrade Fallout 4 to 1.10.984' } }
  $broken = Get-Broken
  if (Test-Path "$Fo4\Data\Fallout34.esm") {                 # already converted: maintenance only
    if ($broken) { return @{ s = 'R'; t = "$($broken.Count) mod(s) missing - press REPAIR MODS" } }
    if (-not (Test-FixesApplied)) { return @{ s = 'F'; t = 'Press APPLY GAME FIXES, then PLAY' } }
    return @{ s = ''; t = 'All done - press PLAY' }
  }
  if (@($broken | Where-Object { -not (Get-Staged $_) }).Count) { return @{ s = '2'; t = 'Download the required mods' } }
  if ($broken -or @(Get-MissingReqs).Count) { return @{ s = '3'; t = 'Install the mods' } }
  return @{ s = '4'; t = 'Run the Fallout 34 converter (2-4 hours)' }
}

# ------------------------------------------------------------------ entry
if ($Step) {                                       # one step in this console (started by the window)
  try { $Host.UI.RawUI.WindowTitle = "Fallout 34 - step $Step" } catch {}
  try { Invoke-Step $Step.ToUpper() } catch { Say "`nERROR: $($_.Exception.Message)" Red }
  Read-Host "`nFinished. Press Enter to close this window" | Out-Null
  return
}

if ($Console) {                                    # old text menu
  while ($true) {
    Show-Status
    Say '[A] Do everything left  [1] Downgrade  [2] Download  [3] Install  [4] Run converter  [R] Repair mods  [F] Game fixes  [B] Fix black screen  [O] Online on/off  [Q] Quit' Cyan
    $c = (Read-Host 'Choose').Trim().ToUpper()
    if ($c -eq 'Q') { return }
    try { Invoke-Step $c } catch { Say "`nERROR: $($_.Exception.Message)" Red }
    Read-Host "`nEnter to continue" | Out-Null
  }
}

# ------------------------------------------------------------------ window
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$cBg    = [System.Drawing.Color]::FromArgb(12, 18, 12)
$cPanel = [System.Drawing.Color]::FromArgb(20, 30, 20)
$cHover = [System.Drawing.Color]::FromArgb(30, 70, 40)
$cFg    = [System.Drawing.Color]::FromArgb(64, 255, 128)
$cDim   = [System.Drawing.Color]::FromArgb(45, 140, 80)
$cWarn  = [System.Drawing.Color]::FromArgb(255, 200, 60)
$cBad   = [System.Drawing.Color]::FromArgb(255, 95, 85)
$fMono  = New-Object System.Drawing.Font('Consolas', 10)
$fBold  = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$fBig   = New-Object System.Drawing.Font('Consolas', 22, [System.Drawing.FontStyle]::Bold)

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Fallout 34 Setup'
$form.ClientSize      = New-Object System.Drawing.Size(900, 742)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox     = $false
$form.BackColor       = $cBg
$form.ForeColor       = $cFg
$form.Font            = $fMono

function New-Label($text, $x, $y, $w, $h, $font, $color) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $text; $l.AutoSize = $false
  $l.Location = New-Object System.Drawing.Point($x, $y)
  $l.Size     = New-Object System.Drawing.Size($w, $h)
  if ($font)  { $l.Font = $font }
  if ($color) { $l.ForeColor = $color }
  $form.Controls.Add($l)
  return $l
}
function New-List($x, $y, $w, $h, $c1, $c2) {
  $lv = New-Object System.Windows.Forms.ListView
  $lv.Location = New-Object System.Drawing.Point($x, $y)
  $lv.Size     = New-Object System.Drawing.Size($w, $h)
  $lv.View = 'Details'; $lv.HeaderStyle = 'None'; $lv.FullRowSelect = $true; $lv.BorderStyle = 'FixedSingle'
  $lv.BackColor = $cPanel; $lv.ForeColor = $cFg; $lv.Font = $fMono
  [void]$lv.Columns.Add('name', $c1); [void]$lv.Columns.Add('state', $c2)
  $form.Controls.Add($lv)
  return $lv
}
function New-Row($lv, $text) {
  $it = New-Object System.Windows.Forms.ListViewItem
  $it.Text = $text; [void]$it.SubItems.Add('...')
  [void]$lv.Items.Add($it)
  return $it
}
function Set-Row($it, $text, $color) {
  if ($it.SubItems[1].Text -ne $text) { $it.SubItems[1].Text = $text; $it.ForeColor = $color }
}
function New-Button($text, $x, $y, $w) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $text
  $b.Location = New-Object System.Drawing.Point($x, $y)
  $b.Size     = New-Object System.Drawing.Size($w, 38)
  $b.FlatStyle = 'Flat'; $b.BackColor = $cPanel; $b.ForeColor = $cFg; $b.Font = $fBold
  $b.FlatAppearance.BorderColor = $cFg; $b.FlatAppearance.MouseOverBackColor = $cHover
  $form.Controls.Add($b)
  return $b
}

$null      = New-Label 'FALLOUT 34 SETUP' 15 10 870 42 $fBig $cFg
$null      = New-Label 'Fallout 3 + New Vegas inside Fallout 4' 18 54 870 20 $fMono $cDim
$lblVer    = New-Label '' 18 84 870 22 $fMono $cFg
$lblSpace  = New-Label '' 18 106 870 22 $fMono $cFg
$lblInst   = New-Label '' 18 128 870 22 $fMono $cFg
$null      = New-Label 'MODS' 15 160 400 20 $fBold $cDim
$null      = New-Label 'CHECKS' 520 160 300 20 $fBold $cDim
$lvMods    = New-List 15 184 490 340 330 138
$lvReq     = New-List 520 184 365 340 235 108
$lblNext   = New-Label '' 15 536 870 26 $fBold $cWarn
$btn1      = New-Button '1  DOWNGRADE'     15 570 150
$btn2      = New-Button '2  DOWNLOAD MODS' 175 570 150
$btn3      = New-Button '3  INSTALL MODS'  335 570 150
$btn4      = New-Button '4  RUN CONVERTER' 495 570 170
$btnA      = New-Button 'DO EVERYTHING LEFT' 675 570 210
$btnR      = New-Button 'REPAIR MODS'      15 618 210
$btnF      = New-Button 'APPLY GAME FIXES' 235 618 210
$btnB      = New-Button 'FIX BLACK SCREEN' 455 618 210
$btnO      = New-Button 'ONLINE'           675 618 210
$btnPlay   = New-Button 'PLAY FALLOUT 34'  15 666 310
$btnFolder = New-Button 'OPEN PROJECT FOLDER' 335 666 330
$btnQuit   = New-Button 'QUIT' 675 666 210
$lblStatus = New-Label 'Ready.' 15 714 870 22 $fMono $cDim

$btn1.Tag = '1'; $btn2.Tag = '2'; $btn3.Tag = '3'; $btn4.Tag = '4'; $btnA.Tag = 'A'; $btnR.Tag = 'R'; $btnF.Tag = 'F'; $btnO.Tag = 'O'; $btnB.Tag = 'B'
$stepButtons = @($btn1, $btn2, $btn3, $btn4, $btnA, $btnR, $btnF, $btnO)

$modRows = @{}
foreach ($e in $Files) { $modRows[$e.m] = New-Row $lvMods $e.n }
$reqRows = @{}
foreach ($r in $Req.GetEnumerator()) { $reqRows[$r.Key] = New-Row $lvReq $r.Key }
$rowFo3  = New-Row $lvReq 'Fallout 3 plugins'
$rowFnv  = New-Row $lvReq 'New Vegas plugins'
$rowConv = New-Row $lvReq 'Fallout 34 converted'
$rowFix  = New-Row $lvReq 'Game fixes'
$rowOn   = New-Row $lvReq 'Fallout 34 Online'

$script:Child = $null
$script:ChildStep = ''

function Test-Busy { return [bool]($script:Child -and -not $script:Child.HasExited) }

function Start-Step($s) {
  if ((Test-Busy) -or (Test-ConverterRunning)) { return }
  if ((Test-GameRunning) -and $s -ne 'B') { return }
  $a = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Step {1} -Fo4 "{2}" -Fo3 "{3}" -Fnv "{4}" -Root "{5}" -Inst "{6}" -Docs "{7}"' -f $PSCommandPath, $s, $Fo4, $Fo3, $Fnv, $Root, $Inst, $Docs
  $script:Child = Start-Process "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $a -PassThru
  $script:ChildStep = $s
  Update-Ui
}

function Update-Ui {
  try {
    $v = Get-Fo4Version
    $lblVer.Text = "Fallout 4 version : $v   (needs $Want)"
    if ($v -like "$Want*") { $lblVer.ForeColor = $cFg } else { $lblVer.ForeColor = $cBad }
    $lblSpace.Text = 'Free space        : {0}: {1} GB    {2}: {3} GB' -f (Get-Item $Fo4).PSDrive.Name, (Get-FreeGB $Fo4), (Get-Item $Root).PSDrive.Name, (Get-FreeGB $Root)
    $iv = ''; if (Test-Path "$Inst\VERSION") { $iv = [string](Get-Content "$Inst\VERSION" | Select-Object -First 1) }
    if ($iv) { $lblInst.Text = "Installer         : Fallout 34 $iv"; $lblInst.ForeColor = $cFg } else { $lblInst.Text = "Installer         : NOT FOUND  $Inst"; $lblInst.ForeColor = $cBad }

    foreach ($e in $Files) {
      $st = Get-ModState $e
      if     ($st -eq 'installed')  { Set-Row $modRows[$e.m] $st $cFg }
      elseif ($st -eq 'MISSING')    { Set-Row $modRows[$e.m] $st $cBad }
      elseif ($st -eq 'not needed') { Set-Row $modRows[$e.m] $st $cDim }
      else                          { Set-Row $modRows[$e.m] $st $cWarn }
    }
    foreach ($r in $Req.GetEnumerator()) {
      if (Test-Path (Join-Path $Fo4 $r.Value)) { Set-Row $reqRows[$r.Key] 'OK' $cFg } else { Set-Row $reqRows[$r.Key] 'MISSING' $cBad }
    }
    if (Test-Path "$env:LOCALAPPDATA\Fallout3\plugins.txt")  { Set-Row $rowFo3 'enabled' $cFg } else { Set-Row $rowFo3 'not yet' $cDim }
    if (Test-Path "$env:LOCALAPPDATA\FalloutNV\plugins.txt") { Set-Row $rowFnv 'enabled' $cFg } else { Set-Row $rowFnv 'not yet' $cDim }
    $converted = Test-Path "$Fo4\Data\Fallout34.esm"
    if ($converted) { Set-Row $rowConv 'YES' $cFg } else { Set-Row $rowConv 'not yet' $cDim }
    if (Test-FixesApplied) { Set-Row $rowFix 'applied' $cFg } else { Set-Row $rowFix 'not applied' $cWarn }
    $online = Test-Online
    if ($online) { Set-Row $rowOn 'ON' $cFg; $btnO.Text = 'TURN ONLINE OFF' } else { Set-Row $rowOn 'off' $cDim; $btnO.Text = 'TURN ONLINE ON' }
    $gameUp = Test-GameRunning

    $conv = Test-ConverterRunning
    $busy = (Test-Busy) -or $conv -or $gameUp
    $next = Get-NextStep
    foreach ($b in $stepButtons) {
      $b.Enabled = -not $busy
      if ((-not $busy) -and $b.Tag -eq $next.s) { $b.FlatAppearance.BorderSize = 3 } else { $b.FlatAppearance.BorderSize = 1 }
    }
    $btnPlay.Enabled = ($converted -and -not $busy)
    $btnB.Enabled    = -not ((Test-Busy) -or $conv)
    if ($gameUp) {
      $lblNext.Text   = 'FALLOUT 4 IS RUNNING'
      $lblStatus.Text = 'Buttons unlock when you close the game. Stuck on a black screen? Press FIX BLACK SCREEN.'
    } elseif ($conv) {
      $lblNext.Text   = 'CONVERTER RUNNING   ' + (Get-ConverterStage)
      $lblStatus.Text = 'Leave it alone until the Fallout 34 setup window says it is finished (2-4 hours). Buttons are locked meanwhile.'
    } elseif ($busy) {
      $lblNext.Text   = "RUNNING STEP $($script:ChildStep) - follow the prompts in the console window that opened"
      $lblStatus.Text = 'Buttons unlock when that console window is closed.'
    } else {
      $lblNext.Text   = 'NEXT: ' + $next.t
      $lblStatus.Text = 'Ready.'
    }
  } catch { $lblStatus.Text = 'Status error: ' + $_.Exception.Message }
}

foreach ($b in $stepButtons) { $b.Add_Click({ Start-Step $this.Tag }) }
$btnB.Add_Click({ Start-Step $this.Tag })
$btnPlay.Add_Click({ Start-Process "$Fo4\f4se_loader.exe" -WorkingDirectory $Fo4 })
$btnFolder.Add_Click({ Start-Process explorer.exe $Root })
$btnQuit.Add_Click({ $form.Close() })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({ Update-Ui })
$form.Add_Shown({ Update-Ui; $timer.Start() })
$form.Add_FormClosed({ $timer.Stop() })
[void]$form.ShowDialog()
