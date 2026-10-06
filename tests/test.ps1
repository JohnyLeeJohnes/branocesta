# Zkouška Bránocesty: nejdřív instalace vydání (Apps.ps1), pak průchod oknem.
#   powershell -ExecutionPolicy Bypass -File tests/test.ps1
#
# Na GitHub test nesahá: vydání jsou vymyšlená v dočasné složce (-Source) a instalují se tamtéž (-AppsPath).
# Okno běží přímo v tomhle procesu a na chvíli se ukáže. Na konci brána doopravdy spustí vymyšleného Spáče,
# který jen zapíše soubor; podle něj se pozná, že ho pustila.
$repo = Split-Path $PSScriptRoot
$temp = Join-Path ([IO.Path]::GetTempPath()) "branocesta-test-$PID"
$source = Join-Path $temp 'vydani'
$null = New-Item -ItemType Directory -Force $source
$script:fail = 0
# Co se vypíše z obsluhy události, se ztratí; řádky se proto sbírají a vypíšou až na konci.
$script:lines = New-Object System.Collections.ArrayList

function Note([string]$line) { $null = $script:lines.Add($line) }
function Check($what, $actual, $expected) {
    if ("$actual" -ceq "$expected") { Note "ok    $what" }
    else { $script:fail++; Note "FAIL  $what = '$actual' (čekáno '$expected')" }
}
# Druh a hláška chyby, kterou blok skončil.
function Fails([scriptblock]$action) {
    try { $null = & $action; 'bez chyby' }
    catch { "$($_.Exception.Data['Kind']): $($_.Exception.Message)" }
}

. (Join-Path $repo 'Apps.ps1')

# Vymyšlené vydání ve složce $source: popis <repozitář>.json a ZIP se soubory ($entries = cesta v ZIPu -> obsah).
function Publish([string]$repository, [string]$tag, $entries) {
    [IO.File]::WriteAllText((Join-Path $source "$repository.json"), (@{ tag_name = $tag; name = "Vydání $tag" } | ConvertTo-Json))
    $path = Join-Path $source "$repository.zip"
    if (Test-Path $path) { Remove-Item $path }
    $zip = [IO.Compression.ZipFile]::Open($path, 'Create')
    try {
        foreach ($name in $entries.Keys) {
            $writer = New-Object System.IO.StreamWriter ($zip.CreateEntry($name).Open())
            $writer.Write($entries[$name])
            $writer.Dispose()
        }
    } finally { $zip.Dispose() }
}

# ---- Soubory ----

# Bez BOM čte PowerShell 5.1 skript jako ANSI a rozbije češtinu.
foreach ($file in Get-ChildItem $repo, "$repo\tests", "$repo\tools" -Filter *.ps1) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    Check "$($file.Name) je UTF-8 s BOM" ('{0:X2}{1:X2}{2:X2}' -f $bytes[0], $bytes[1], $bytes[2]) 'EFBBBF'
}
# cmd.exe čte spolehlivě jen ASCII a konce řádků CRLF.
foreach ($file in Get-ChildItem $repo -Filter *.cmd) {
    $text = [IO.File]::ReadAllText($file.FullName)
    Check "$($file.Name) je ASCII s konci řádků CRLF" "$($text -notmatch '[^\x00-\x7F]') $($text -notmatch '(?<!\r)\n')" 'True True'
}

# ---- Popis vydání ----

$spac, $sluzbak, $mesec = $apps
Check 'brána zná tři aplikace' (($apps | ForEach-Object { "$($_.Id)=$($_.Script)" }) -join ' ') 'Spac=Spac.ps1 Sluzbak=Sluzbak.ps1 Mesec=Mesec.ps1'

# Síť zastupuje vlastní Invoke-Http: vrátí, co má v $script:answer, a zapamatuje si, na co se kdo ptal.
function Invoke-Http([string]$uri, [string]$accept) {
    $script:asked = $uri
    , [Text.Encoding]::UTF8.GetBytes($script:answer)
}
$online = @{ Source = $null; Root = (Join-Path $temp 'nic') }

$script:answer = '{"tag_name":"v2.0.0","zipball_url":"https://api.github.com/zipball/v2.0.0","assets":[{"name":"poznamky.txt","url":"https://x/1"},{"name":"Spac-2.0.0.zip","url":"https://x/2"}]}'
$release = Get-LatestRelease $online $spac
Check 'ptá se na nejnovější vydání repozitáře' $script:asked 'https://api.github.com/repos/JohnyLeeJohnes/spac/releases/latest'
Check 'ZIP přiložený k vydání má přednost' "$($release.Tag) $($release.Url) $($release.Accept)" 'v2.0.0 https://x/2 application/octet-stream'

$script:answer = '{"tag_name":"v2.0.0","zipball_url":"https://api.github.com/zipball/v2.0.0","assets":[]}'
$release = Get-LatestRelease $online $spac
Check 'bez přiloženého ZIPu se bere archiv zdrojáků' "$($release.Url) $($release.Accept)" 'https://api.github.com/zipball/v2.0.0 application/vnd.github+json'

$script:answer = '<html>'
Check 'odpověď, která není JSON' (Fails { Get-LatestRelease $online $spac }) 'Unexpected: GitHub poslal odpověď, které nerozumím.'
$script:answer = '{"message":"hm"}'
Check 'vydání bez tagu' (Fails { Get-LatestRelease $online $spac }) 'Unexpected: GitHub poslal vydání bez čísla verze.'

Check 'chyby GitHubu mají druh' ((404, 403, 429, 500 | ForEach-Object { (ConvertTo-AppError $_).Data['Kind'] }) -join ' ') 'NotFound RateLimited RateLimited Unexpected'

# ---- Instalace ----

$root = Join-Path $temp 'aplikace'
$context = @{ Source = $source; Root = $root }

# Archiv zdrojáků z GitHubu má všechno ve složce pojmenované po repozitáři a commitu.
Publish 'spac' 'v1.0.0' @{
    'JohnyLeeJohnes-spac-abc1234/Spac.ps1' = 'první'
    'JohnyLeeJohnes-spac-abc1234/assets/spac.ico' = 'ikona'
    'JohnyLeeJohnes-spac-abc1234/stary.txt' = 'jen v první verzi'
}
Check 'napoprvé nic nainstalovaného není' (Get-Installed $context $spac) ''
$release = Get-LatestRelease $context $spac
Check 'instalace vrátí tag vydání' (Install-Release $context $spac $release) 'v1.0.0'
Check 'složka z archivu se vynechá' "$(Test-Path "$root\Spac\Spac.ps1") $(Test-Path "$root\Spac\assets\spac.ico")" 'True True'
Check 'nainstalovaná verze se pozná' (Get-Installed $context $spac) 'v1.0.0'

Publish 'spac' 'v1.1.0' @{ 'Spac/Spac.ps1' = 'druhá'; 'Spac/Spac.xaml' = '<Window/>' }
$null = Install-Release $context $spac (Get-LatestRelease $context $spac)
Check 'aktualizace vymění celou složku' "$(Get-Installed $context $spac) $([IO.File]::ReadAllText("$root\Spac\Spac.ps1")) $(Test-Path "$root\Spac\stary.txt")" 'v1.1.0 druhá False'
Check 'po aktualizaci nezbydou pracovní složky' "$(Test-Path "$root\Spac.new") $(Test-Path "$root\Spac.old")" 'False False'

# Soubory rovnou v kořeni ZIPu, bez společné složky.
Publish 'mesec' 'v1.0.0' @{ 'Mesec.ps1' = 'okno'; 'Data.ps1' = 'data' }
$null = Install-Release $context $mesec (Get-LatestRelease $context $mesec)
Check 'ZIP bez společné složky se rozbalí, jak je' "$(Test-Path "$root\Mesec\Mesec.ps1") $(Test-Path "$root\Mesec\Data.ps1")" 'True True'

# Vadné vydání nesmí rozbít verzi, která už nainstalovaná je.
Publish 'spac' 'v1.2.0' @{ 'Spac/README.md' = 'bez skriptu' }
Check 'vydání bez skriptu aplikace se odmítne' (Fails { Install-Release $context $spac (Get-LatestRelease $context $spac) }) 'Unexpected: Ve vydání v1.2.0 chybí Spac.ps1.'
Publish 'spac' 'v1.2.0' @{ 'Spac/Spac.ps1' = 'třetí'; 'Spac/../../venku.txt' = 'mimo složku' }
Check 'soubor mířící mimo složku aplikace se odmítne' (Fails { Install-Release $context $spac (Get-LatestRelease $context $spac) }) 'Unexpected: Vydání obsahuje soubor, který míří mimo složku aplikace.'
Check 'a mimo složku se nic nezapíše' "$(Test-Path "$temp\venku.txt") $(Test-Path "$root\venku.txt")" 'False False'
[IO.File]::WriteAllText("$source\spac.zip", 'tohle není ZIP')
Check 'soubor, který není ZIP' (Fails { Install-Release $context $spac (Get-LatestRelease $context $spac) }) 'Unexpected: Stažené vydání není ZIP.'
Remove-Item "$source\spac.zip"
Check 'chybějící soubor vydání' (Fails { Install-Release $context $spac (Get-LatestRelease $context $spac) }) 'NotFound: Ve složce s vydáními chybí spac.zip.'

# Běžící aplikace drží svou složku; tady ji zastoupí otevřený soubor.
Publish 'spac' 'v1.2.0' @{ 'Spac/Spac.ps1' = 'třetí' }
$lock = [IO.File]::Open("$root\Spac\Spac.ps1", 'Open', 'Read', 'None')
try { Check 'běžící aplikace se nepřepisuje' (Fails { Install-Release $context $spac (Get-LatestRelease $context $spac) }) 'Busy: Spáč právě běží, novou verzi nainstaluju, až ho zavřeš.' }
finally { $lock.Dispose() }
Check 'po všech nepovedených pokusech zůstala stará verze' "$(Get-Installed $context $spac) $([IO.File]::ReadAllText("$root\Spac\Spac.ps1")) $(Test-Path "$root\Spac.new")" 'v1.1.0 druhá False'

# ---- Okno ----

$appRoot = Join-Path $temp 'okno'
$marker = Join-Path $temp 'spusteno.txt'
# Vymyšlený Spáč zapíše, ve které složce ho brána pustila.
Publish 'spac' 'v1.0.0' @{ 'Spac/Spac.ps1' = "[IO.File]::WriteAllText('$marker', (Get-Location).Path)" }
Publish 'sluzbak' 'v0.4.0' @{ 'Sluzbak/Sluzbak.ps1' = "'nic'" }
Publish 'mesec' 'v1.0.0' @{ 'Mesec/Mesec.ps1' = "'nic'" }

function Click($button) { $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
# Co je na kartě aplikace vidět: verze | stav | jde spustit | běží linka
function Card([string]$id) {
    "$($ui["${id}Version"].Text) | $($ui["${id}Status"].Text) | $($ui["${id}Launch"].IsEnabled) | $($ui["${id}Busy"].Visibility)"
}
function Red($element) { $element.Foreground -eq $window.FindResource('Danger') }

# Otevře bránu a projde kroky. Další krok přijde na řadu, až brána dokončí, co má rozdělané; po posledním se okno zavře.
function Open-Gateway([scriptblock[]]$steps) {
    $queue = New-Object System.Collections.Queue (, $steps)
    $giveUp = [DateTime]::UtcNow.AddSeconds(60)
    $driver = [Windows.Threading.DispatcherTimer]::new()
    $driver.Interval = [TimeSpan]::FromMilliseconds(100)
    $driver.Add_Tick({
        if (-not ($window -and $window.IsLoaded)) { return }
        try {
            # Okno visí nebo úlohy nedoběhly; bez tohohle by test nikdy neskončil.
            if ([DateTime]::UtcNow -gt $giveUp) { throw 'brána do minuty nedokončila, co měla rozdělané' }
            if ($jobs.Count) { return }
            & $queue.Dequeue()
            if ($queue.Count) { return }
        } catch { $script:fail++; Note "FAIL  průchod oknem spadl na řádku $($_.InvocationInfo.ScriptLineNumber): $_" }
        $driver.Stop()
        if ($window.IsVisible) { $window.Close() }
    })
    $driver.Start()
    . (Join-Path $repo 'Branocesta.ps1') -AppsPath $appRoot -Source $source
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Open-Gateway @(
    {
        Check 'první spuštění nainstaluje Spáče' (Card 'Spac') 'verze 1.0.0 | Právě nainstalováno. | True | Hidden'
        Check 'první spuštění nainstaluje Službák' (Card 'Sluzbak') 'verze 0.4.0 | Právě nainstalováno. | True | Hidden'
        Check 'první spuštění nainstaluje Měšec' (Card 'Mesec') 'verze 1.0.0 | Právě nainstalováno. | True | Hidden'
        Check 'soubory jsou ve složce z -AppsPath' "$(Test-Path "$appRoot\Spac\Spac.ps1") $(Test-Path "$appRoot\Sluzbak\Sluzbak.ps1") $(Test-Path "$appRoot\Mesec\Mesec.ps1")" 'True True True'
        Check 'dole je verze brány' ($ui.VersionText.Text -match '^Bránocesta \d+\.\d+\.\d+$') $true

        # Spáč vydal novou verzi, vydání Měšce se nedá přečíst a Službák s novou verzí zrovna běží.
        Publish 'spac' 'v1.1.0' @{ 'Spac/Spac.ps1' = "[IO.File]::WriteAllText('$marker', (Get-Location).Path)" }
        Publish 'sluzbak' 'v0.5.0' @{ 'Sluzbak/Sluzbak.ps1' = "'nic'" }
        Remove-Item "$source\mesec.json"
        $script:lock = [IO.File]::Open("$appRoot\Sluzbak\Sluzbak.ps1", 'Open', 'Read', 'None')
        Click $ui.RefreshButton
        Check 'kontrola je na kartě vidět a spustit jde i během ní' (Card 'Spac') 'verze 1.0.0 | Hledám nejnovější vydání… | True | Visible'
    }
    {
        $script:lock.Dispose()
        Check 'nové vydání se nainstaluje samo' (Card 'Spac') 'verze 1.1.0 | Právě aktualizováno. | True | Hidden'
        Check 'běžící aplikace zůstane, jak je, a jde spustit' (Card 'Sluzbak') 'verze 0.4.0 | Službák právě běží, novou verzi nainstaluju, až ho zavřeš. | True | Hidden'
        Check 'chyba u jedné aplikace ostatní nezastaví' (Card 'Mesec') 'verze 1.0.0 | Ve složce s vydáními chybí mesec.json. | True | Hidden'
        Check 'chyba je červeně, úspěch ne' "$(Red $ui.MesecStatus) $(Red $ui.SpacStatus)" 'True False'

        Click $ui.SpacLaunch
        Check 'spuštění aplikace bránu zavře' $window.IsVisible $false
    }
)

# Spáč startuje v jiném procesu; chvilku mu to trvá.
for ($i = 0; $i -lt 150 -and -not (Test-Path $marker); $i++) { Start-Sleep -Milliseconds 100 }
Check 'brána pustila Spáče a v jeho složce' $(if (Test-Path $marker) { [IO.File]::ReadAllText($marker) } else { 'nespustil se' }) "$appRoot\Spac"

# Podruhé už je nainstalováno: nic se nestahuje a Službák, který mezitím skončil, se doaktualizuje.
$before = (Get-Item "$appRoot\Spac\Spac.ps1").LastWriteTimeUtc
Open-Gateway @(
    {
        Check 'aktuální aplikace se znovu neinstaluje' "$(Card 'Spac') | $((Get-Item "$appRoot\Spac\Spac.ps1").LastWriteTimeUtc -eq $before)" 'verze 1.1.0 | Máš nejnovější vydání. | True | Hidden | True'
        Check 'odložená aktualizace se dožene' (Card 'Sluzbak') 'verze 0.5.0 | Právě aktualizováno. | True | Hidden'
    }
)

$script:lines
Remove-Item -Recurse -Force $temp
if ($script:fail) { "`n$($script:fail) chyb" } else { "`nVšechno prošlo." }
exit $script:fail
