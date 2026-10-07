# Zkouška Bránocesty: nejdřív instalace a odinstalování vydání (Apps.ps1), pak průchod oknem.
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
# Apps.ps1 si knihovny pro ZIP načítá, až když rozbaluje; Publish je potřebuje dřív.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

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

# Číslo verze je na dvou místech a při vydání se snadno změní jen jedno.
$inScript = if ([IO.File]::ReadAllText("$repo\Branocesta.ps1") -match "\`$version = '([\d.]+)'") { $Matches[1] }
$inChangelog = if ([IO.File]::ReadAllText("$repo\CHANGELOG.md") -match '(?m)^## \[(\d[\d.]*)\]') { $Matches[1] }
Check 'verze v Branocesta.ps1 sedí s nejnovější v CHANGELOG.md' $inScript $inChangelog

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
try {
    Check 'běžící aplikace se nepřepisuje' (Fails { Install-Release $context $spac (Get-LatestRelease $context $spac) }) 'Busy: Spáč právě běží. Zavři ho a zkus to znovu.'
    Check 'běžící aplikace se neodinstaluje' (Fails { Uninstall-App $context $spac }) 'Busy: Spáč právě běží. Zavři ho a zkus to znovu.'
} finally { $lock.Dispose() }
Check 'po všech nepovedených pokusech zůstala stará verze' "$(Get-Installed $context $spac) $([IO.File]::ReadAllText("$root\Spac\Spac.ps1")) $(Test-Path "$root\Spac.new") $(Test-Path "$root\Spac.old")" 'v1.1.0 druhá False False'

# ---- Odinstalování ----

Uninstall-App $context $spac
Check 'odinstalování smaže složku aplikace' "$(Test-Path "$root\Spac") $(Test-Path "$root\Spac.old") '$(Get-Installed $context $spac)'" "False False ''"
Check 'ostatní aplikace ve společné složce zůstanou' (Get-Installed $context $mesec) 'v1.0.0'
Check 'odinstalovat nenainstalované nic neudělá' (Fails { Uninstall-App $context $spac }) 'bez chyby'
$null = Install-Release $context $spac (Get-LatestRelease $context $spac)
Check 'po odinstalování jde nainstalovat znovu' (Get-Installed $context $spac) 'v1.2.0'

# ---- Paměť vydání ----

$memory = @{ Source = $source; Root = (Join-Path $temp 'pamet') }
Check 'bez souboru si brána nepamatuje nic' (Read-Known $memory).Count 0
$asked = [DateTime]::new(2026, 10, 6, 12, 0, 0, [DateTimeKind]::Utc)
Save-Known $memory @{
    Spac = @{ Checked = $asked; Release = @{ Tag = 'v1.2.0'; Url = 'https://x/spac.zip'; Accept = 'application/octet-stream' } }
    Mesec = @{ Checked = $asked.AddMinutes(5); Release = @{ Tag = 'v1.0.0'; Url = 'https://x/mesec'; Accept = 'application/vnd.github+json' } }
}
$known = Read-Known $memory
Check 'co si brána zapíše, to si přečte' "$($known.Spac.Release.Tag) $($known.Spac.Release.Url) $($known.Spac.Release.Accept) $($known.Mesec.Release.Tag)" 'v1.2.0 https://x/spac.zip application/octet-stream v1.0.0'
Check 'i s časem dotazu' "$($known.Spac.Checked -eq $asked) $($known.Spac.Checked.Kind) $($known.Mesec.Checked -eq $asked.AddMinutes(5))" 'True Utc True'
[IO.File]::WriteAllText("$($memory.Root)\.releases", "nesmysl`r`nSpac`tnení číslo`tv1`thttps://x`ta`r`n")
Check 'soubor, který nejde přečíst, je jako žádný' (Read-Known $memory).Count 0

# ---- Brána sama ----

Check 'novější je jen vyšší číslo verze' ((@('v1.1.0', '1.0.0'), @('v1.0.0', '1.0.0'), @('v0.9.0', '1.0.0'), @('v1.10.0', '1.9.0'), @('nocni', '1.0.0') |
    ForEach-Object { Test-Newer $_[0] $_[1] }) -join ' ') 'True False False True False'

# Složka, ve které brána jako by běžela: staré soubory a zástupce, který ve vydání není.
$gatewayHome = Join-Path $temp 'doma'
$null = New-Item -ItemType Directory -Force "$gatewayHome\assets"
foreach ($name in 'Branocesta.ps1', 'Apps.ps1', 'Branocesta.xaml', 'assets\branocesta.ico', 'Zastupce.lnk') { [IO.File]::WriteAllText("$gatewayHome\$name", 'staré') }
function Get-HomeFiles { (Get-ChildItem $gatewayHome -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.Name)=$([IO.File]::ReadAllText($_.FullName))" }) -join ' ' }

Publish 'branocesta' 'v9.0.0' @{ 'Branocesta/Branocesta.ps1' = 'nové'; 'Branocesta/Branocesta.xaml' = 'nové' }
Check 'neúplné vydání brány se odmítne' (Fails { Update-Gateway $context (Get-LatestRelease $context $gateway) $gatewayHome }) 'Unexpected: Ve vydání v9.0.0 chybí Apps.ps1.'
Check 'a na soubory brány nesáhne' (Get-HomeFiles) 'Apps.ps1=staré branocesta.ico=staré Branocesta.ps1=staré Branocesta.xaml=staré Zastupce.lnk=staré'

Publish 'branocesta' 'v9.0.0' @{
    'Branocesta/Branocesta.ps1' = 'nové'; 'Branocesta/Apps.ps1' = 'nové'; 'Branocesta/Branocesta.xaml' = 'nové'
    'Branocesta/assets/branocesta.ico' = 'nové'; 'Branocesta/README.md' = 'nové'
}
Check 'aktualizace brány vrátí tag vydání' (Update-Gateway $context (Get-LatestRelease $context $gateway) $gatewayHome) 'v9.0.0'
Check 'přepíše soubory na místě, přidá nové a cizí nechá' (Get-HomeFiles) 'Apps.ps1=nové branocesta.ico=nové Branocesta.ps1=nové Branocesta.xaml=nové README.md=nové Zastupce.lnk=staré'
Remove-Item "$source\branocesta.json", "$source\branocesta.zip"

# ---- Okno ----

$appRoot = Join-Path $temp 'okno'
$marker = Join-Path $temp 'spusteno.txt'
# Vymyšlený Spáč zapíše, ve které složce ho brána pustila a kam se má vrátit, a na chvíli ukáže okno: na to
# brána čeká, než se zavře.
# (Jen ASCII: skript v ZIPu nemá BOM.)
$fakeWindow = @'
Add-Type -AssemblyName PresentationFramework, WindowsBase
$window = New-Object Windows.Window
$window.Title = 'Zkusebni okno'; $window.Width = 260; $window.Height = 120
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ $window.Close() })
$timer.Start()
$null = $window.ShowDialog()
'@
$fakeSpac = "[IO.File]::WriteAllText('$marker', (Get-Location).Path + '|' + `$env:BRANOCESTA + '|' + [Environment]::CurrentDirectory)`n$fakeWindow"
# Vymyšlená aplikace, která umí bránu zavolat zpátky (čte BRANOCESTA_PID): chvíli ukazuje okno a pak buď
# nastaví událost brány a zavře se ('zpet'), nebo se jen zavře ('konec').
function New-FakeReturning([string]$how) {
    "[IO.File]::WriteAllText('$temp\proces-$how.txt', `$PID)`n" + @'
Add-Type -AssemblyName PresentationFramework, WindowsBase
$window = New-Object Windows.Window
$window.Title = 'Zkusebni okno'; $window.Width = 260; $window.Height = 120
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(1500)
$timer.Add_Tick({
    $timer.Stop()
    if ('HOW' -eq 'zpet') {
        $signal = [Threading.EventWaitHandle]::OpenExisting("Branocesta.$env:BRANOCESTA_PID")
        $null = $signal.Set()
        Start-Sleep -Milliseconds 400
    }
    $window.Close()
})
$timer.Start()
$null = $window.ShowDialog()
'@.Replace('HOW', $how)
}
Publish 'spac' 'v1.0.0' @{ 'Spac/Spac.ps1' = $fakeSpac }
Publish 'sluzbak' 'v0.4.0' @{ 'Sluzbak/Sluzbak.ps1' = '# nic' }
Publish 'mesec' 'v1.0.0' @{ 'Mesec/Mesec.ps1' = '# nic' }

function Click($button) { $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
# Co je na kartě aplikace vidět: verze | stav | tlačítka (vypnutá v závorce) | běží linka
function Card([string]$id) {
    $buttons = foreach ($name in 'Install', 'Launch', 'Update', 'Remove') {
        $button = $ui["$id$name"]
        if ($button.Visibility -eq 'Visible') { if ($button.IsEnabled) { $name } else { "($name)" } }
    }
    "$($ui["${id}Version"].Text) | $($ui["${id}Status"].Text) | $buttons | $($ui["${id}Busy"].Visibility)"
}
function Red($element) { $element.Foreground -eq $window.FindResource('Danger') }

# Otevře bránu a projde kroky. Další krok přijde na řadu, až brána dokončí, co má rozdělané; po posledním se okno zavře.
# $from je složka, ze které brána běží: pracovní kopie, nebo její kopie bez gitu (jen ta se smí sama přepsat).
function Open-Gateway([scriptblock[]]$steps, [string]$from = $repo) {
    $queue = New-Object System.Collections.Queue (, $steps)
    $giveUp = [DateTime]::UtcNow.AddSeconds(60)
    # Zavřel okno test, nebo se brána zavřela sama? Sama se zavírá jen po spuštění aplikace.
    $script:closedByTest = $false
    # Bylo okno brány vidět, když čekala schovaná za aplikací?
    $script:seenAway = ''
    $driver = [Windows.Threading.DispatcherTimer]::new()
    $driver.Interval = [TimeSpan]::FromMilliseconds(100)
    $driver.Add_Tick({
        # Na vydání se brána ptá až po vykreslení okna; do té doby není co zkoušet.
        if (-not ($window -and $window.IsLoaded -and $state.Started)) { return }
        try {
            # Okno visí nebo úlohy nedoběhly; bez tohohle by test nikdy neskončil.
            if ([DateTime]::UtcNow -gt $giveUp) { throw 'brána do minuty nedokončila, co měla rozdělané' }
            if ($state.Away) { $script:seenAway = "schovaná=$(-not $window.IsVisible)"; return }
            if ($jobs.Count -or $state.Launch) { return }
            if ($queue.Count) { & $queue.Dequeue(); return }
        } catch { $script:fail++; Note "FAIL  průchod oknem spadl na řádku $($_.InvocationInfo.ScriptLineNumber): $_" }
        $driver.Stop()
        if ($window.IsVisible) { $script:closedByTest = $true; $window.Close() }
    })
    $driver.Start()
    . (Join-Path $from 'Branocesta.ps1') -AppsPath $appRoot -Source $source
    $driver.Stop()
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Open-Gateway @(
    {
        Check 'napoprvé není nainstalovaný Spáč' (Card 'Spac') 'není nainstalováno | Ke stažení je verze 1.0.0. | Install | Hidden'
        Check 'ani Službák' (Card 'Sluzbak') 'není nainstalováno | Ke stažení je verze 0.4.0. | Install | Hidden'
        Check 'ani Měšec' (Card 'Mesec') 'není nainstalováno | Ke stažení je verze 1.0.0. | Install | Hidden'
        Check 'a sama brána nic nestáhne' (@(Get-ChildItem $appRoot -Directory).Count) 0
        Check 'co se dozvěděla, si zapamatuje' ((Read-Known $context).Keys | Sort-Object) 'Mesec Sluzbak Spac'
        Check 'v záloze čeká PowerShell na příští aplikaci' ($state.Standby -and -not $state.Standby.HasExited) $true
        Check 'ikona nenainstalované aplikace je ztlumená' ($ui.SpacIcon.Opacity -lt 1) $true
        Check 'dole je verze brány' ($ui.VersionText.Text -match '^Bránocesta \d+\.\d+\.\d+$') $true

        Click $ui.SpacInstall
        Click $ui.SluzbakInstall
        Check 'instalace je na kartě vidět' (Card 'Spac') 'není nainstalováno | Instaluju 1.0.0… | (Install) | Visible'
    }
    {
        Check 'Nainstalovat nainstaluje Spáče' (Card 'Spac') 'verze 1.0.0 | Právě nainstalováno. | Launch Remove | Hidden'
        Check 'a Službák' (Card 'Sluzbak') 'verze 0.4.0 | Právě nainstalováno. | Launch Remove | Hidden'
        Check 'na co se nekliklo, nainstalované není' (Card 'Mesec') 'není nainstalováno | Ke stažení je verze 1.0.0. | Install | Hidden'
        Check 'soubory jsou v jedné složce z -AppsPath' "$(Test-Path "$appRoot\Spac\Spac.ps1") $(Test-Path "$appRoot\Sluzbak\Sluzbak.ps1") $(Test-Path "$appRoot\Mesec")" 'True True False'
        Check 'ikona nainstalované aplikace svítí naplno' $ui.SpacIcon.Opacity 1

        # Spáč a Službák vydaly novou verzi a vydání Měšce se nedá přečíst.
        Publish 'spac' 'v1.1.0' @{ 'Spac/Spac.ps1' = $fakeSpac }
        Publish 'sluzbak' 'v0.5.0' @{ 'Sluzbak/Sluzbak.ps1' = '# nic' }
        Remove-Item "$source\mesec.json"
        $script:before = (Get-Item "$appRoot\Spac\Spac.ps1").LastWriteTimeUtc
        Click $ui.RefreshButton
        Check 'kontrola je na kartě vidět a spustit jde i během ní' (Card 'Spac') 'verze 1.0.0 | Hledám nejnovější vydání… | Launch (Remove) | Visible'
    }
    {
        Check 'nové vydání se nabídne, ale samo se neinstaluje' "$(Card 'Spac') | $((Get-Item "$appRoot\Spac\Spac.ps1").LastWriteTimeUtc -eq $script:before)" 'verze 1.0.0 | Vyšla verze 1.1.0. | Launch Update Remove | Hidden | True'
        # Vydání Měšce brána zná z první kontroly, takže ho nainstalovat jde dál.
        Check 'chyba u jedné aplikace ostatní nezastaví' (Card 'Mesec') 'není nainstalováno | Ve složce s vydáními chybí mesec.json. | Install | Hidden'
        Check 'chyba je červeně, nabídka ne' "$(Red $ui.MesecStatus) $(Red $ui.SpacStatus)" 'True False'

        # Službák zrovna běží: drží svou složku.
        $script:lock = [IO.File]::Open("$appRoot\Sluzbak\Sluzbak.ps1", 'Open', 'Read', 'None')
        Click $ui.SpacUpdate
        Click $ui.SluzbakUpdate
        Check 'aktualizace je na kartě vidět' (Card 'Spac') 'verze 1.0.0 | Aktualizuju na 1.1.0… | (Launch) (Update) (Remove) | Visible'
    }
    {
        Check 'Aktualizovat nainstaluje nové vydání' (Card 'Spac') 'verze 1.1.0 | Právě aktualizováno. | Launch Remove | Hidden'
        Check 'běžící aplikace zůstane, jak je, a jde spustit' (Card 'Sluzbak') 'verze 0.4.0 | Službák právě běží. Zavři ho a zkus to znovu. | Launch Update Remove | Hidden'
        Click $ui.SluzbakRemove
        Check 'odinstalování je na kartě vidět' (Card 'Sluzbak') 'verze 0.4.0 | Odinstalovávám… | (Launch) (Update) (Remove) | Visible'
    }
    {
        Check 'běžící aplikace se neodinstaluje' "$(Card 'Sluzbak') | $(Red $ui.SluzbakStatus) | $(Test-Path "$appRoot\Sluzbak\Sluzbak.ps1")" 'verze 0.4.0 | Službák právě běží. Zavři ho a zkus to znovu. | Launch Update Remove | Hidden | True | True'
        $script:lock.Dispose()
        Click $ui.SluzbakRemove
    }
    {
        Check 'Odinstalovat aplikaci odebere' (Card 'Sluzbak') 'není nainstalováno | Odinstalováno. Tvoje data zůstala. | Install | Hidden'
        Check 'ze společné složky zmizí jen ona' "$(Test-Path "$appRoot\Sluzbak") $(Test-Path "$appRoot\Sluzbak.old") $(Test-Path "$appRoot\Spac\Spac.ps1")" 'False False True'

        Click $ui.SpacLaunch
        Check 'po kliknutí na Spustit brána čeká na okno aplikace' "$(Card 'Spac') | $($window.IsVisible)" 'verze 1.1.0 | Spouštím… | (Launch) (Remove) | Visible | True'
    }
)

Check 'a zavře se sama, jakmile aplikace okno ukáže' $script:closedByTest $false
Check 'brána pustila Spáče v jeho složce a řekla mu, kam se vrátit' $(if (Test-Path $marker) { [IO.File]::ReadAllText($marker) } else { 'nespustil se' }) "$appRoot\Spac|$repo\Branocesta.ps1|$appRoot\Spac"

# Podruhé brána ukáže, co je na disku, a nic nemění: co je odinstalované, se samo nevrátí.
# (Bez paměti z prvního otevření, ať se na vydání ptá znovu; paměť se zkouší až na konci.)
Remove-Item "$appRoot\.releases"
$before = (Get-Item "$appRoot\Spac\Spac.ps1").LastWriteTimeUtc
Open-Gateway @(
    {
        Check 'aktuální aplikace se znovu neinstaluje' "$(Card 'Spac') | $((Get-Item "$appRoot\Spac\Spac.ps1").LastWriteTimeUtc -eq $before)" 'verze 1.1.0 | Máš nejnovější vydání. | Launch Remove | Hidden | True'
        Check 'odinstalovaná aplikace se sama nevrátí' "$(Card 'Sluzbak') | $(Test-Path "$appRoot\Sluzbak")" 'není nainstalováno | Ke stažení je verze 0.5.0. | Install | Hidden | False'
        # Tentokrát brána vydání Měšce nezná vůbec.
        Click $ui.MesecInstall
        Check 'bez známého vydání instalovat nejde' "$(Card 'Mesec') | $($jobs.Count)" 'není nainstalováno | Ve složce s vydáními chybí mesec.json. | (Install) | Hidden | 0'
        Click $ui.SluzbakInstall
    }
    {
        # Vymyšlený Službák žádné okno neukáže a hned skončí.
        Click $ui.SluzbakLaunch
    }
    {
        Check 'aplikace, která hned skončí, bránu nezavře' "$(Card 'Sluzbak') | $(Red $ui.SluzbakStatus) | $($window.IsVisible)" 'verze 0.5.0 | Službák skončil hned po spuštění. | Launch Remove | Hidden | True | True'
    }
)

# ---- Brána aktualizuje sama sebe ----
# Zkouší se na kopiích v dočasné složce: vydání brány je vymyšlené a skutečné soubory by přepsalo nesmyslem.

function New-GatewayCopy([string]$name) {
    $path = Join-Path $temp $name
    $null = New-Item -ItemType Directory -Force "$path\assets"
    foreach ($file in 'Branocesta.ps1', 'Apps.ps1', 'Standby.ps1', 'Branocesta.xaml', 'assets\branocesta.ico') { Copy-Item "$repo\$file" "$path\$file" }
    $path
}
$hint = 'Po spuštění aplikace se brána zavře. Všechno, co nainstaluješ, leží v jedné složce.'
# Vymyšlená nová brána zapíše, s jakými parametry ji ta stará otevřela, a na chvíli ukáže okno.
$reopened = Join-Path $temp 'znovu.txt'
$fakeGateway = "param([string]`$AppsPath, [string]`$Source)`n[IO.File]::WriteAllText('$reopened', `"`$AppsPath|`$Source`")`n$fakeWindow"
Publish 'branocesta' 'v99.0.0' @{
    'Branocesta/Branocesta.ps1' = $fakeGateway; 'Branocesta/Apps.ps1' = 'nové aplikace'
    'Branocesta/Branocesta.xaml' = 'nové okno'; 'Branocesta/assets/branocesta.ico' = 'nová ikona'
}

$copy = New-GatewayCopy 'brana'
$null = New-Item -ItemType Directory "$copy\.git"
Open-Gateway -from $copy @(
    {
        Check 'pracovní kopii z gitu brána aktualizaci nenabízí' "$($ui.FooterText.Text) | $($ui.GatewayUpdate.Visibility)" "$hint | Collapsed"
    }
)

Remove-Item "$copy\.git"
Open-Gateway -from $copy @(
    {
        Check 'nainstalovaná brána novou verzi nabídne, ale sama se nepřepíše' "$($ui.FooterText.Text) | $($ui.GatewayUpdate.Visibility) | $([IO.File]::ReadAllText("$copy\Apps.ps1") -eq 'nové aplikace')" 'Vyšla verze 99.0.0 brány. | Visible | False'
        Click $ui.GatewayUpdate
        Check 'aktualizace brány je vidět a karty jsou po tu dobu zamčené' "$($ui.FooterText.Text) | $(Card 'Spac')" 'Stahuju verzi 99.0.0 brány… | verze 1.1.0 | Máš nejnovější vydání. | (Launch) (Remove) | Hidden'
    }
)
Check 'po aktualizaci se stará brána zavře sama, až nová ukáže okno' $script:closedByTest $false
Check 'brána přepíše své soubory, i ikonu, kterou má okno načtenou' (('Apps.ps1', 'Branocesta.xaml', 'assets\branocesta.ico' | ForEach-Object { [IO.File]::ReadAllText("$copy\$_") }) -join ' | ') 'nové aplikace | nové okno | nová ikona'
Check 'vedle nezbydou rozdělané soubory' (@(Get-ChildItem $copy -Recurse -Filter *.new).Count) 0
Check 'nová brána se otevře se stejnými parametry' $(if (Test-Path $reopened) { [IO.File]::ReadAllText($reopened) } else { 'neotevřela se' }) "$appRoot|$source"

# Nová brána, která se neotevře: stará musí zůstat a dál fungovat.
$broken = New-GatewayCopy 'rozbita'
Publish 'branocesta' 'v99.0.0' @{ 'Branocesta/Branocesta.ps1' = '# nic'; 'Branocesta/Apps.ps1' = 'nové aplikace'; 'Branocesta/Branocesta.xaml' = 'nové okno' }
Open-Gateway -from $broken @(
    {
        Click $ui.GatewayUpdate
    }
    {
        Check 'když se nová brána neotevře, stará zůstane a řekne to' "$($ui.FooterText.Text) | $($ui.GatewayUpdate.Visibility) | $($window.IsVisible)" 'Brána se aktualizovala na verzi 99.0.0. Zavři ji a otevři znovu, ať běží ta nová. | Collapsed | True'
        Click $ui.RefreshButton
    }
    {
        # Na disku je teď z Apps.ps1 nesmysl; okno, které už běží, musí dál pracovat s tím, co načetlo při startu.
        Check 'běžící okno po aktualizaci brány funguje dál' (Card 'Spac') 'verze 1.1.0 | Máš nejnovější vydání. | Launch Remove | Hidden'
        Check 'a aktualizaci už znovu nenabízí' "$($ui.FooterText.Text -match '^Brána se aktualizovala') | $($ui.GatewayUpdate.Visibility)" 'True | Collapsed'
    }
)

# ---- Paměť vydání a návrat z aplikace ----

# Měšec a Službák umějí bránu zavolat zpátky: Měšec to udělá, Službák se jen zavře.
Publish 'mesec' 'v1.0.0' @{ 'Mesec/Mesec.ps1' = (New-FakeReturning 'zpet') }
Publish 'sluzbak' 'v0.6.0' @{ 'Sluzbak/Sluzbak.ps1' = (New-FakeReturning 'konec') }
Publish 'spac' 'v1.5.0' @{ 'Spac/Spac.ps1' = $fakeSpac }
Open-Gateway @(
    {
        Check 'na vydání, která zná z minula, se brána při otevření neptá' "$(Card 'Spac') || $(Card 'Sluzbak')" 'verze 1.1.0 | Máš nejnovější vydání. | Launch Remove | Hidden || verze 0.5.0 | Máš nejnovější vydání. | Launch Remove | Hidden'
        # Vydání Měšce se minule zjistit nepodařilo.
        Check 'na to, co nezná, se zeptá' (Card 'Mesec') 'není nainstalováno | Ke stažení je verze 1.0.0. | Install | Hidden'
        Click $ui.RefreshButton
    }
    {
        Check 'Zkontrolovat vydání se ptá vždycky' "$(Card 'Spac') || $(Card 'Sluzbak')" 'verze 1.1.0 | Vyšla verze 1.5.0. | Launch Update Remove | Hidden || verze 0.5.0 | Vyšla verze 0.6.0. | Launch Update Remove | Hidden'
        Click $ui.MesecInstall
        Click $ui.SluzbakUpdate
    }
    {
        $script:standby = $state.Standby.Id
        Click $ui.MesecLaunch
    }
    {
        # Sem se dojde, až Měšec bránu zavolá zpátky.
        Check 'za aplikací, která ji umí zavolat, čeká brána schovaná' $script:seenAway 'schovaná=True'
        Check 'aplikace se rozběhla v záloze, ne v novém PowerShellu' ([IO.File]::ReadAllText("$temp\proces-zpet.txt")) $script:standby
        Check 'na zavolání se brána ukáže znovu' "$($window.IsVisible) | $(Card 'Mesec')" 'True | verze 1.0.0 | Máš nejnovější vydání. | Launch Remove | Hidden'
        Check 'na vydání se přitom neptá' "$(Card 'Spac') | $($jobs.Count)" 'verze 1.1.0 | Vyšla verze 1.5.0. | Launch Update Remove | Hidden | 0'
        Check 'a připraví si novou zálohu' ($state.Standby -and $state.Standby.Id -ne $script:standby) $true
        $script:seenAway = ''
        Click $ui.SluzbakLaunch
    }
)
Check 'když aplikace skončí a bránu nezavolá, skončí brána taky' "$script:seenAway | $script:closedByTest" 'schovaná=True | False'

# Co brána ví déle než čtvrt hodiny, si při otevření ověří.
Publish 'spac' 'v1.6.0' @{ 'Spac/Spac.ps1' = $fakeSpac }
Open-Gateway @(
    { Check 'čerstvou paměť brána neověřuje' (Card 'Spac') 'verze 1.1.0 | Vyšla verze 1.5.0. | Launch Update Remove | Hidden' }
)
$windowContext = @{ Source = $source; Root = $appRoot }
$known = Read-Known $windowContext
foreach ($id in @($known.Keys)) { $known[$id].Checked = [DateTime]::UtcNow.AddMinutes(-20) }
Save-Known $windowContext $known
Open-Gateway @(
    { Check 'starou si ověří sama' (Card 'Spac') 'verze 1.1.0 | Vyšla verze 1.6.0. | Launch Update Remove | Hidden' }
)

$script:lines
# Vymyšlený Spáč zavře své okno až za chvíli a do té doby drží svou složku.
for ($i = 0; $i -lt 100 -and (Test-Path $temp); $i++) {
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
    if (Test-Path $temp) { Start-Sleep -Milliseconds 100 }
}
if ($script:fail) { "`n$($script:fail) chyb" } else { "`nVšechno prošlo." }
exit $script:fail
