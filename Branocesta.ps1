# Bránocesta: brána ke Spáči, Službákovi a Měšci. Každou z nich jde na její kartě nainstalovat z nejnovějšího
# vydání na GitHubu, aktualizovat, odinstalovat a spustit; při spuštění se brána zavře.
# Okno je popsané v Branocesta.xaml, vydání řeší Apps.ps1.
#   Branocesta.ps1                      spustí bránu
#   Branocesta.ps1 -Install             vytvoří zástupce s ikonou v nabídce Start, na ploše a ve složce s bránou
#   Branocesta.ps1 -AppsPath <složka>   aplikace instaluje jinam než do %LOCALAPPDATA% (testy)
#   Branocesta.ps1 -Source <složka>     vydání bere ze složky místo z GitHubu (testy)
#   Branocesta.ps1 -Screenshot <png>    po kontrole vydání uloží obrázek okna a skončí (obrázky do README)
param([switch]$Install, [string]$AppsPath, [string]$Source, [string]$Screenshot)

$ErrorActionPreference = 'Stop'
# Číslo vydání. Musí sedět s nejnovější verzí v CHANGELOG.md (hlídá tests/test.ps1).
$version = '1.2.1'
$icon = Join-Path $PSScriptRoot 'assets\branocesta.ico'

if ($Install) {
    # Soubory rozbalené ze ZIPu staženého prohlížečem nesou značku "z internetu" a Windows se u nich
    # může ptát nebo je odmítnout. Po instalaci už značku nemají. (Kde to nejde, zůstane vše při starém.)
    Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

    $shell = New-Object -ComObject WScript.Shell
    # Nabídka Start, plocha a složka s bránou (ať je i tam na co kliknout).
    foreach ($directory in [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('DesktopDirectory'), $PSScriptRoot) {
        # WScript.Shell ukládá texty v kódové stránce systému a "á" v ní být nemusí.
        # Proto se zástupce uloží jako Branocesta.lnk a přejmenuje až potom, a popisek je bez háčků a čárek.
        $path = Join-Path $directory 'Branocesta.lnk'
        $link = $shell.CreateShortcut($path)
        # conhost --headless spustí PowerShell bez okna konzole.
        $link.TargetPath = "$env:SystemRoot\System32\conhost.exe"
        $link.Arguments = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $link.WorkingDirectory = $PSScriptRoot
        $link.IconLocation = $icon
        $link.Description = 'Brana ke Spaci, Sluzbakovi a Mesci'
        $link.Save()
        if ($shell.CreateShortcut($path).Arguments -ne $link.Arguments) {
            Remove-Item $path
            throw "Cesta $PSScriptRoot obsahuje znaky, které zástupce neunese. Přesuň složku jinam a zkus to znovu."
        }
        Move-Item $path (Join-Path $directory 'Bránocesta.lnk') -Force
    }
    'Hotovo. Zástupce Bránocesta je v nabídce Start, na ploše a v téhle složce.'
    return
}

# Microsoft.VisualBasic je tu kvůli AppActivate: pošle okno jiného procesu dopředu (viz Complete-Launch).
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, Microsoft.VisualBasic
. (Join-Path $PSScriptRoot 'Apps.ps1')
# Úlohy na pozadí si Apps.ps1 nenačítají z disku, ale z tohohle textu: běží tak ze stejné verze jako okno,
# i když si brána mezitím přepíše vlastní soubory novým vydáním.
$library = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Apps.ps1'))

# Volání Windows API pro tmavý titulek. Když se Add-Type nepovede (třeba kvůli zásadám počítače),
# brána běží dál, jen má titulek světlý.
$native = $null
try {
    $native = Add-Type -Namespace Branocesta -Name Native -PassThru -MemberDefinition @'
[DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
'@
} catch { }

# Cesty z parametrů mohou být relativní k aktuální složce PowerShellu; .NET by je bral od složky procesu.
function Resolve-Target([string]$path) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path) }
# Všechny aplikace jsou v jedné složce, ať brána leží kdekoli. Aktualizace brány na ni nesahá a do repozitáře
# se nedostane.
$AppsPath = if ($AppsPath) { Resolve-Target $AppsPath } else { Join-Path $env:LOCALAPPDATA 'Branocesta\apps' }
if ($Source) { $Source = Resolve-Target $Source }
if ($Screenshot) { $Screenshot = Resolve-Target $Screenshot }
$context = @{ Source = $Source; Root = $AppsPath }
# Sama sebe brána přepisuje jen tam, kde je nainstalovaná. V pracovní kopii z gitu by jí vydání přepsalo
# rozdělanou práci.
$selfUpdates = -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.git'))

$state = @{
    # Id aplikace -> @{ Installed; Latest; Phase; Error; Fresh }
    #   Installed  tag nainstalovaného vydání, '' = nainstalovaná není
    #   Latest     nejnovější vydání z Get-LatestRelease, $null = ještě ho neznáme
    #   Phase      'Checking' (hledá se vydání), 'Installing', 'Removing', 'Launching' nebo 'Idle'
    #   Error      hláška, proč se poslední kontrola, instalace, odinstalování nebo spuštění nepovedly
    #   Fresh      co se s aplikací stalo od poslední kontroly: 'Installed', 'Updated', 'Removed' nebo $null
    Apps = @{}
    # Vydání brány samotné: Checked = při tomhle otevření se už našlo novější, Note = co o tom říct v zápatí.
    Gateway = @{ Checked = $false; Note = $null; IsError = $false }
    # Aplikace, na jejíž okno brána čeká: @{ App; Process; Since; GiveUp }, jinak $null (viz Start-App).
    Launch = $null
    ShotDue = $null
}

# ---- Úlohy na pozadí ----
# Síť ani rozbalování nesmí běžet ve vlákně okna, jinak by zamrzlo. Každá úloha si v jiném vlákně načte
# Apps.ps1, zavolá jednu jeho funkci a vrátí @{ Ok; Data } nebo @{ Ok; Kind; Message }.

$worker = {
    param($library, $command, $arguments)
    $ErrorActionPreference = 'Stop'
    try {
        . ([scriptblock]::Create($library))
        $data = & $command @arguments
        @{ Ok = $true; Data = $data }
    } catch {
        $kind = [string]$_.Exception.Data['Kind']
        # Chyby bez druhu nejsou ze sítě, ale z našeho kódu; ať je to z hlášky poznat.
        $message = if ($kind) { $_.Exception.Message } else { "Tohle se nepovedlo: $($_.Exception.Message)" }
        @{ Ok = $false; Kind = $kind; Message = $message }
    }
}.ToString()

$pool = [RunspaceFactory]::CreateRunspacePool(1, 4)
$pool.Open()
$jobs = New-Object System.Collections.ArrayList

# $done je jméno funkce, která dostane $tag (čeho se úloha týká) a její výsledek.
# Jméno, ne blok: uzávěr by neviděl funkce skriptu.
function Start-Work([string]$command, $arguments, [string]$done, $tag) {
    $shell = [PowerShell]::Create()
    $shell.RunspacePool = $pool
    $null = $shell.AddScript($worker).AddArgument($library).AddArgument($command).AddArgument($arguments)
    $null = $jobs.Add(@{ Done = $done; Tag = $tag; Shell = $shell; Handle = $shell.BeginInvoke() })
}

function Complete-Work {
    foreach ($job in @($jobs | Where-Object { $_.Handle.IsCompleted })) {
        $jobs.Remove($job)
        $result = $null
        try { $result = @($job.Shell.EndInvoke($job.Handle))[0] }
        catch { $result = @{ Ok = $false; Kind = ''; Message = "Úloha na pozadí spadla: $($_.Exception.Message)" } }
        finally { $job.Shell.Dispose() }
        if (-not $result) { $result = @{ Ok = $false; Kind = ''; Message = 'Úloha na pozadí nic nevrátila.' } }
        & $job.Done $job.Tag $result
    }
}

# ---- Karty aplikací ----

# "v1.1.0" -> "1.1.0"; tag, který takhle nevypadá, zůstane, jak je.
function Format-Tag([string]$tag) { $tag -replace '^v(?=\d)' }

function Update-App($app) {
    $id = $app.Id
    $entry = $state.Apps[$id]
    $busy = $entry.Phase -ne 'Idle'
    $installed = [bool]$entry.Installed
    # Venku je jiné vydání, než jaké je nainstalované. Dokud se vydání nepodařilo zjistit, neví se.
    $outdated = $installed -and $entry.Latest -and $entry.Latest.Tag -ne $entry.Installed

    $ui["${id}Icon"].Opacity = if ($installed) { 1 } else { 0.45 }
    $ui["${id}Version"].Text = if ($installed) { "verze $(Format-Tag $entry.Installed)" } else { 'není nainstalováno' }
    $ui["${id}Busy"].Visibility = if ($busy) { 'Visible' } else { 'Hidden' }

    # Hlavní tlačítko je buď Spustit, nebo Nainstalovat. Dvě vedlejší se jen schovávají (Hidden), ať karta
    # drží výšku.
    $ui["${id}Launch"].Visibility = if ($installed) { 'Visible' } else { 'Collapsed' }
    $ui["${id}Install"].Visibility = if ($installed) { 'Collapsed' } else { 'Visible' }
    $ui["${id}Update"].Visibility = if ($outdated) { 'Visible' } else { 'Hidden' }
    $ui["${id}Remove"].Visibility = if ($installed) { 'Visible' } else { 'Hidden' }
    # Co je nainstalované, jde spustit i bez internetu a během kontroly; jen ne ve chvíli, kdy se mění soubory.
    $ui["${id}Launch"].IsEnabled = $installed -and $entry.Phase -notin 'Installing', 'Removing', 'Launching'
    # Nainstalovat jde jen vydání, o kterém brána ví.
    $ui["${id}Install"].IsEnabled = -not $busy -and [bool]$entry.Latest
    $ui["${id}Update"].IsEnabled = -not $busy
    $ui["${id}Remove"].IsEnabled = -not $busy

    $ui["${id}Status"].Foreground = $window.FindResource($(if ($entry.Error -and -not $busy) { 'Danger' } else { 'Muted' }))
    $ui["${id}Status"].Text =
        if ($entry.Phase -eq 'Checking') { 'Hledám nejnovější vydání…' }
        elseif ($entry.Phase -eq 'Installing') {
            $(if ($installed) { 'Aktualizuju na ' } else { 'Instaluju ' }) + (Format-Tag $entry.Latest.Tag) + '…'
        }
        elseif ($entry.Phase -eq 'Removing') { 'Odinstalovávám…' }
        elseif ($entry.Phase -eq 'Launching') { 'Spouštím…' }
        elseif ($entry.Error) { $entry.Error }
        elseif ($entry.Fresh -eq 'Installed') { 'Právě nainstalováno.' }
        elseif ($entry.Fresh -eq 'Updated') { 'Právě aktualizováno.' }
        elseif ($entry.Fresh -eq 'Removed') { 'Odinstalováno. Tvoje data zůstala.' }
        elseif (-not $entry.Latest) { '' }
        elseif (-not $installed) { "Ke stažení je verze $(Format-Tag $entry.Latest.Tag)." }
        elseif ($outdated) { "Vyšla verze $(Format-Tag $entry.Latest.Tag)." }
        else { 'Máš nejnovější vydání.' }
}

# ---- Kontrola vydání ----
# Brána sama jen zjistí, jaké vydání je u každé aplikace nejnovější. Instalaci, aktualizaci i odinstalování
# spouští až tlačítko na kartě. Chyba u jedné aplikace ostatní nezastaví.

function Start-Refresh {
    # Dokud něco běží, další kontrola nezačne: přepsala by stav karty, na které se zrovna pracuje.
    if ($jobs.Count -or $state.Launch) { return }
    foreach ($app in $apps) {
        $entry = $state.Apps[$app.Id]
        $entry.Phase = 'Checking'
        $entry.Error = $null
        $entry.Fresh = $null
        Update-App $app
        Start-Work 'Get-LatestRelease' @($context, $app) 'Complete-Check' $app
    }
    if ($selfUpdates -and -not $state.Gateway.Checked) {
        Start-Work 'Get-LatestRelease' @($context, $gateway) 'Complete-GatewayCheck' $gateway
    }
}

function Complete-Check($app, $result) {
    $entry = $state.Apps[$app.Id]
    $entry.Phase = 'Idle'
    if ($result.Ok) { $entry.Latest = $result.Data } else { $entry.Error = $result.Message }
    Update-App $app
}

# ---- Instalace, aktualizace a odinstalování ----
# Nainstalovat a Aktualizovat jsou tatáž úloha: stáhne nejnovější vydání a vymění jím složku aplikace.

function Start-Install($app) {
    $entry = $state.Apps[$app.Id]
    if ($entry.Phase -ne 'Idle' -or -not $entry.Latest) { return }
    $entry.Phase = 'Installing'
    $entry.Error = $null
    Update-App $app
    Start-Work 'Install-Release' @($context, $app, $entry.Latest) 'Complete-Install' $app
}

function Complete-Install($app, $result) {
    $entry = $state.Apps[$app.Id]
    $entry.Phase = 'Idle'
    if (-not $result.Ok) { $entry.Error = $result.Message }
    else {
        $entry.Fresh = if ($entry.Installed) { 'Updated' } else { 'Installed' }
        $entry.Installed = [string]$result.Data
    }
    Update-App $app
}

function Start-Uninstall($app) {
    $entry = $state.Apps[$app.Id]
    if ($entry.Phase -ne 'Idle' -or -not $entry.Installed) { return }
    $entry.Phase = 'Removing'
    $entry.Error = $null
    Update-App $app
    Start-Work 'Uninstall-App' @($context, $app) 'Complete-Uninstall' $app
}

function Complete-Uninstall($app, $result) {
    $entry = $state.Apps[$app.Id]
    $entry.Phase = 'Idle'
    if (-not $result.Ok) { $entry.Error = $result.Message }
    else {
        $entry.Fresh = 'Removed'
        $entry.Installed = ''
    }
    Update-App $app
}

# ---- Vydání brány samotné ----
# Nové vydání brány se nainstaluje na pozadí a projeví se až při příštím otevření: okno, které už běží,
# se pod rukama nemění. Když se vydání zjistit nepodaří, nic se nehlásí; karty aplikací mají hlášky vlastní.

function Update-Footer {
    $brush = if ($state.Gateway.IsError) { 'Danger' } elseif ($state.Gateway.Note) { 'Text' } else { 'Muted' }
    $ui.FooterText.Foreground = $window.FindResource($brush)
    $ui.FooterText.Text = if ($state.Gateway.Note) { $state.Gateway.Note } else { $footerHint }
}

function Complete-GatewayCheck($app, $result) {
    if (-not $result.Ok -or -not (Test-Newer $result.Data.Tag $version)) { return }
    # Jednou za otevření stačí; další kontrola by přepisovala soubory, které se právě vyměnily.
    $state.Gateway.Checked = $true
    $state.Gateway.Note = "Stahuju novou verzi brány $(Format-Tag $result.Data.Tag)…"
    Update-Footer
    Start-Work 'Update-Gateway' @($context, $result.Data, $PSScriptRoot) 'Complete-GatewayUpdate' $result.Data
}

function Complete-GatewayUpdate($release, $result) {
    $state.Gateway.IsError = -not $result.Ok
    $state.Gateway.Note =
        if ($result.Ok) { "Brána se aktualizovala na verzi $(Format-Tag $release.Tag). Uvidíš ji při příštím otevření." }
        else { "Novou verzi brány $(Format-Tag $release.Tag) se nepodařilo nainstalovat. $($result.Message)" }
    Update-Footer
}

# ---- Spuštění aplikace ----
# Brána aplikaci pustí, počká, až ukáže své okno, pošle ho dopředu a teprve pak se zavře. Kdyby se zavřela
# hned, Windows by mezitím aktivovaly jiné okno a aplikace by se otevřela schovaná za ním: vypadalo by to,
# že se nestalo nic.

function Start-App($app) {
    $entry = $state.Apps[$app.Id]
    if ($state.Launch -or -not $entry.Installed) { return }
    $directory = Get-AppDirectory $context $app
    $since = Get-Date
    try {
        # conhost --headless spustí PowerShell bez okna konzole, stejně jako zástupci samotných aplikací.
        $process = Start-Process -FilePath "$env:SystemRoot\System32\conhost.exe" -WorkingDirectory $directory -PassThru `
            -ArgumentList "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $directory $app.Script)`""
    } catch {
        $entry.Error = "Spuštění se nepovedlo: $($_.Exception.Message)"
        Update-App $app
        return
    }
    $state.Launch = @{ App = $app; Process = $process; Since = $since; GiveUp = [DateTime]::UtcNow.AddSeconds(30) }
    $entry.Phase = 'Launching'
    $entry.Error = $null
    Update-App $app
}

# Id procesu PowerShellu, který vznikl po $since a už má okno; $null, dokud žádný takový není.
function Find-AppProcess([datetime]$since) {
    foreach ($process in [Diagnostics.Process]::GetProcessesByName('powershell')) {
        try {
            if ($process.Id -ne $PID -and $process.StartTime -ge $since -and $process.MainWindowHandle -ne [IntPtr]::Zero) { return $process.Id }
        }
        catch { }   # Proces mezitím skončil nebo k němu není přístup.
        finally { $process.Dispose() }
    }
}

# Volá se z časovače, dokud brána čeká na okno spuštěné aplikace.
function Complete-Launch {
    $launch = $state.Launch
    if (-not $launch) { return }

    $id = Find-AppProcess $launch.Since
    if ($id) {
        $state.Launch = $null
        # Brána je teď v popředí, takže smí dopředu poslat i cizí okno. Když to nevyjde, okno aplikace
        # zůstane tam, kde je.
        try { [Microsoft.VisualBasic.Interaction]::AppActivate($id) } catch { }
        $window.Close()
        return
    }

    $name = $launch.App.Name
    # conhost žije, dokud běží PowerShell, který hostí; když skončil, skončila i aplikace.
    $problem = if ($launch.Process.HasExited) { "$name skončil hned po spuštění." }
        elseif ([DateTime]::UtcNow -gt $launch.GiveUp) { "$name se zatím neukázal. Jestli se neotevře, zkus to znovu." }
    if (-not $problem) { return }
    $state.Launch = $null
    $entry = $state.Apps[$launch.App.Id]
    $entry.Phase = 'Idle'
    $entry.Error = $problem
    Update-App $launch.App
}

# ---- Obrázek okna ----

function Save-Screenshot([string]$path) {
    $root = $window.Content
    $scale = [Windows.Media.VisualTreeHelper]::GetDpi($root).DpiScaleX
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(
        [int][Math]::Ceiling($root.ActualWidth * $scale), [int][Math]::Ceiling($root.ActualHeight * $scale),
        96 * $scale, 96 * $scale, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($root)

    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create($path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

# ---- Okno ----

try {
    $window = [Windows.Markup.XamlReader]::Load([Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'Branocesta.xaml')))
    if (Test-Path -LiteralPath $icon) {
        # Ikona se čte z paměti, ne přímo ze souboru: ten zůstane volný a aktualizace brány ho může přepsat.
        $iconBytes = New-Object System.IO.MemoryStream (, [IO.File]::ReadAllBytes($icon))
        $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create($iconBytes, 'None', 'OnLoad')
    }

    $ui = @{}
    'FolderButton', 'RefreshButton', 'FooterText', 'VersionText' | ForEach-Object { $ui[$_] = $window.FindName($_) }
    foreach ($app in $apps) {
        'Icon', 'Version', 'Status', 'Busy', 'Launch', 'Install', 'Update', 'Remove' |
            ForEach-Object { $ui["$($app.Id)$_"] = $window.FindName("$($app.Id)$_") }
    }
    $missing = @($ui.Keys | Where-Object { $null -eq $ui[$_] } | Sort-Object)
    if ($missing) { throw "V Branocesta.xaml chybí prvky: $($missing -join ', ')" }

    $window.Add_SourceInitialized({
        if (-not $native) { return }
        $hwnd = [Windows.Interop.WindowInteropHelper]::new($window).Handle
        # 20 = tmavý režim, 35 = barva titulku, 34 = barva rámečku; barva je #12111C jako COLORREF (0x00BBGGRR).
        # Starší Windows volání jen odmítnou a titulek zůstane výchozí.
        foreach ($attribute in @(20, 1), @(35, 0x001C1112), @(34, 0x001C1112)) {
            $value = $attribute[1]
            $null = $native::DwmSetWindowAttribute($hwnd, $attribute[0], [ref]$value, 4)
        }
    })

    foreach ($app in $apps) {
        $id = $app.Id
        'Launch', 'Install', 'Update', 'Remove' | ForEach-Object { $ui["$id$_"].Tag = $app }
        $ui["${id}Launch"].Add_Click({ param($button) Start-App $button.Tag })
        $ui["${id}Install"].Add_Click({ param($button) Start-Install $button.Tag })
        $ui["${id}Update"].Add_Click({ param($button) Start-Install $button.Tag })
        $ui["${id}Remove"].Add_Click({ param($button) Start-Uninstall $button.Tag })
    }

    $ui.FolderButton.ToolTip = "Otevře složku, ve které jsou nainstalované aplikace: $AppsPath"
    $ui.FolderButton.Add_Click({
        # Dokud není nic nainstalované, složka ještě neexistuje.
        $null = [IO.Directory]::CreateDirectory($AppsPath)
        Start-Process -FilePath $AppsPath
    })
    $ui.RefreshButton.Add_Click({ Start-Refresh })
    $window.Add_KeyDown({
        param($source, $e)
        if ($e.Key -ne 'F5') { return }
        Start-Refresh
        $e.Handled = $true
    })

    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)
    $timer.Add_Tick({
        Complete-Work
        Complete-Launch
        $ui.RefreshButton.IsEnabled = -not ($jobs.Count -or $state.Launch)

        if ($Screenshot -and -not $jobs.Count) {
            # Po poslední úloze ještě chvilka na vykreslení.
            if (-not $state.ShotDue) { $state.ShotDue = [DateTime]::UtcNow.AddMilliseconds(600) }
            elseif ([DateTime]::UtcNow -ge $state.ShotDue) {
                Save-Screenshot $Screenshot
                $window.Close()
            }
        }
    })

    $ui.VersionText.Text = "Bránocesta $version"
    # Co je v zápatí napsané v XAML, platí, dokud není co říct o vydání brány.
    $footerHint = $ui.FooterText.Text
    foreach ($app in $apps) {
        $state.Apps[$app.Id] = @{ Installed = Get-Installed $context $app; Latest = $null; Phase = 'Idle'; Error = $null; Fresh = $null }
    }
    Start-Refresh

    $timer.Start()
    $null = $window.ShowDialog()
    $timer.Stop()
    # Rozdělaná instalace nebo odinstalování se nechají doběhnout: konec procesu uprostřed výměny souborů by
    # aplikaci nebo bránu nechal rozbitou. Ostatní úlohy jen čtou a na jejich dokončení se nečeká.
    foreach ($job in $jobs) {
        if ($job.Done -in 'Complete-Install', 'Complete-Uninstall', 'Complete-GatewayUpdate') { $null = $job.Handle.AsyncWaitHandle.WaitOne(90000) }
        else { $null = $job.Shell.BeginStop($null, $null) }
    }
}
catch {
    # Konzole je schovaná, takže chybu jinak nikdo neuvidí.
    $null = [Windows.MessageBox]::Show("$_", 'Bránocesta', 'OK', 'Error')
}
