# Bránocesta: brána ke Spáči, Službákovi a Měšci. Stáhne z GitHubu jejich nejnovější vydání, nainstaluje je
# a vybranou aplikaci spustí; sama se přitom zavře. Okno je popsané v Branocesta.xaml, vydání řeší Apps.ps1.
#   Branocesta.ps1                      spustí bránu
#   Branocesta.ps1 -Install             vytvoří zástupce s ikonou v nabídce Start, na ploše a ve složce s bránou
#   Branocesta.ps1 -AppsPath <složka>   aplikace instaluje jinam než do %LOCALAPPDATA% (testy)
#   Branocesta.ps1 -Source <složka>     vydání bere ze složky místo z GitHubu (testy)
#   Branocesta.ps1 -Screenshot <png>    po kontrole vydání uloží obrázek okna a skončí (obrázky do README)
param([switch]$Install, [string]$AppsPath, [string]$Source, [string]$Screenshot)

$ErrorActionPreference = 'Stop'
# Číslo vydání. Musí sedět s nejnovější verzí v CHANGELOG.md (hlídá tests/test.ps1).
$version = '1.1.0'
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

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
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
# Aplikace jsou mimo složku s bránou: aktualizace brány je nesmaže a do repozitáře se nedostanou.
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
    #   Phase      'Checking' (hledá se vydání), 'Installing' nebo 'Idle'
    #   Error      hláška, proč se kontrola nebo instalace nepovedla
    #   Fresh      co se při tomhle spuštění stalo: 'Installed', 'Updated' nebo $null
    Apps = @{}
    # Vydání brány samotné: Checked = při tomhle otevření se už našlo novější, Note = co o tom říct v zápatí.
    Gateway = @{ Checked = $false; Note = $null; IsError = $false }
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

    $ui["${id}Version"].Text = if ($entry.Installed) { "verze $(Format-Tag $entry.Installed)" } else { 'není nainstalováno' }
    $ui["${id}Busy"].Visibility = if ($busy) { 'Visible' } else { 'Hidden' }
    # Co je nainstalované, jde spustit i bez internetu; jen ne ve chvíli, kdy se mění soubory.
    $ui["${id}Launch"].IsEnabled = [bool]$entry.Installed -and $entry.Phase -ne 'Installing'

    $ui["${id}Status"].Foreground = $window.FindResource($(if ($entry.Error -and -not $busy) { 'Danger' } else { 'Muted' }))
    $ui["${id}Status"].Text =
        if ($entry.Phase -eq 'Checking') { 'Hledám nejnovější vydání…' }
        elseif ($entry.Phase -eq 'Installing') {
            $(if ($entry.Installed) { 'Aktualizuju na ' } else { 'Instaluju ' }) + (Format-Tag $entry.Latest.Tag) + '…'
        }
        elseif ($entry.Error) { $entry.Error }
        elseif ($entry.Fresh -eq 'Installed') { 'Právě nainstalováno.' }
        elseif ($entry.Fresh -eq 'Updated') { 'Právě aktualizováno.' }
        elseif ($entry.Latest) { 'Máš nejnovější vydání.' }
        else { '' }
}

# ---- Kontrola a instalace vydání ----
# Pro každou aplikaci zvlášť se zjistí nejnovější vydání; co není nainstalované nebo je starší, se hned
# stáhne. Chyba u jedné aplikace ostatní nezastaví.

function Start-Refresh {
    # Dvě kontroly naráz by si navzájem přepisovaly rozdělané soubory.
    if ($jobs.Count) { return }
    foreach ($app in $apps) {
        $entry = $state.Apps[$app.Id]
        $entry.Phase = 'Checking'
        $entry.Error = $null
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
    if (-not $result.Ok) { $entry.Error = $result.Message }
    else {
        $entry.Latest = $result.Data
        if ($entry.Installed -ne $entry.Latest.Tag) {
            $entry.Phase = 'Installing'
            Start-Work 'Install-Release' @($context, $app, $entry.Latest) 'Complete-Install' $app
        }
    }
    Update-App $app
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

# Spustí aplikaci a bránu zavře: dál už je vidět jen ta aplikace.
function Start-App($app) {
    $directory = Get-AppDirectory $context $app
    try {
        # conhost --headless spustí PowerShell bez okna konzole, stejně jako zástupci samotných aplikací.
        Start-Process -FilePath "$env:SystemRoot\System32\conhost.exe" -WorkingDirectory $directory `
            -ArgumentList "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $directory $app.Script)`""
    } catch {
        $state.Apps[$app.Id].Error = "Spuštění se nepovedlo: $($_.Exception.Message)"
        Update-App $app
        return
    }
    $window.Close()
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
    'RefreshButton', 'FooterText', 'VersionText' | ForEach-Object { $ui[$_] = $window.FindName($_) }
    foreach ($app in $apps) {
        'Version', 'Status', 'Busy', 'Launch' | ForEach-Object { $ui["$($app.Id)$_"] = $window.FindName("$($app.Id)$_") }
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
        $ui["$($app.Id)Launch"].Tag = $app
        $ui["$($app.Id)Launch"].Add_Click({ param($button) Start-App $button.Tag })
    }

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
        $ui.RefreshButton.IsEnabled = -not $jobs.Count

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
    # Rozdělaná instalace se nechá doběhnout: konec procesu uprostřed výměny souborů by aplikaci nebo bránu
    # nechal rozbitou. Ostatní úlohy jen čtou a na jejich dokončení se nečeká.
    foreach ($job in $jobs) {
        if ($job.Done -in 'Complete-Install', 'Complete-GatewayUpdate') { $null = $job.Handle.AsyncWaitHandle.WaitOne(90000) }
        else { $null = $job.Shell.BeginStop($null, $null) }
    }
}
catch {
    # Konzole je schovaná, takže chybu jinak nikdo neuvidí.
    $null = [Windows.MessageBox]::Show("$_", 'Bránocesta', 'OK', 'Error')
}
