# Bránocesta: brána ke Spáči, Službákovi a Měšci. Každou z nich jde na její kartě nainstalovat z nejnovějšího
# vydání na GitHubu, aktualizovat, odinstalovat a spustit; při spuštění brána zmizí.
# Okno je popsané v Branocesta.xaml, vydání řeší Apps.ps1, aplikace se rozbíhají ve Standby.ps1.
#   Branocesta.ps1                      spustí bránu
#   Branocesta.ps1 -Install             vytvoří zástupce s ikonou v nabídce Start, na ploše a ve složce s bránou
#   Branocesta.ps1 -AppsPath <složka>   aplikace instaluje jinam než do %LOCALAPPDATA% (testy)
#   Branocesta.ps1 -Source <složka>     vydání bere ze složky místo z GitHubu (testy)
#   Branocesta.ps1 -Screenshot <png>    po kontrole vydání uloží obrázek okna a skončí (obrázky do README)
param([switch]$Install, [string]$AppsPath, [string]$Source, [string]$Screenshot)

$ErrorActionPreference = 'Stop'
# Číslo vydání. Musí sedět s nejnovější verzí v CHANGELOG.md (hlídá tests/test.ps1).
$version = '1.4.0'
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

# Start brány je vidět: po kliknutí na zástupce i po návratu z aplikace se čeká, až se okno ukáže. Proto se
# před jeho vykreslením dělá jen to, co je k němu potřeba; síť, vlákna na pozadí a ostatní přijdou až potom.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
. (Join-Path $PSScriptRoot 'Apps.ps1')
# Úlohy na pozadí si Apps.ps1 nenačítají z disku, ale z tohohle textu: běží tak ze stejné verze jako okno,
# i když si brána mezitím přepíše vlastní soubory novým vydáním.
$library = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Apps.ps1'))

# Volání Windows API pro tmavý titulek, vlastní ikonu na hlavním panelu a uvolnění paměti schované brány.
# Typ se skládá za běhu (Reflection.Emit): Add-Type by kvůli pár deklaracím pouštěl kompilátor C# a start by
# to zdrželo o stovky milisekund. Když se to nepovede (třeba kvůli zásadám počítače), brána běží dál, jen má
# titulek světlý, na hlavním panelu ikonu PowerShellu a schovaná si paměť drží.
$native = $null
try {
    $assembly = [AppDomain]::CurrentDomain.DefineDynamicAssembly((New-Object Reflection.AssemblyName 'BranocestaNative'), 'Run')
    $type = $assembly.DefineDynamicModule('BranocestaNative').DefineType('Branocesta.Native', 'Public, Class')
    $imports = @('dwmapi.dll', 'DwmSetWindowAttribute', @([IntPtr], [int], [int].MakeByRefType(), [int])),
        @('shell32.dll', 'SetCurrentProcessExplicitAppUserModelID', @([string])),
        @('psapi.dll', 'EmptyWorkingSet', @([IntPtr]))
    foreach ($import in $imports) {
        $method = $type.DefinePInvokeMethod($import[1], $import[0], 'Public, Static, PinvokeImpl', 'Standard', [int], [Type[]]$import[2], 'Winapi', 'Unicode')
        $method.SetImplementationFlags('PreserveSig')
    }
    $native = $type.CreateType()
    # Okno hostí powershell.exe, takže by ho Windows na hlavním panelu přiřadily k PowerShellu a ukázaly jeho
    # ikonu. S vlastním označením je brána na panelu sama za sebe a s ikonou svého okna.
    $null = $native::SetCurrentProcessExplicitAppUserModelID('JohnyLeeJohnes.Branocesta')
} catch { }

# Cesty z parametrů mohou být relativní k aktuální složce PowerShellu; .NET by je bral od složky procesu.
function Resolve-Target([string]$path) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path) }
# Všechny aplikace jsou v jedné složce, ať brána leží kdekoli. Aktualizace brány na ni nesahá a do repozitáře
# se nedostane.
# $relaunch jsou parametry, se kterými brána běží; stejné dostane, až se po aktualizaci otevře znovu.
$relaunch = ''
if ($AppsPath) { $AppsPath = Resolve-Target $AppsPath; $relaunch += " -AppsPath `"$AppsPath`"" }
else { $AppsPath = Join-Path $env:LOCALAPPDATA 'Branocesta\apps' }
if ($Source) { $Source = Resolve-Target $Source; $relaunch += " -Source `"$Source`"" }
if ($Screenshot) { $Screenshot = Resolve-Target $Screenshot }
$context = @{ Source = $Source; Root = $AppsPath }
# Sama sebe brána aktualizuje jen tam, kde je nainstalovaná. V pracovní kopii z gitu by jí vydání přepsalo
# rozdělanou práci.
$selfUpdates = -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.git'))
# Podle tohohle aplikace poznají, že je pustila brána, a kam se mají vrátit. Proměnné zdědí každý proces,
# který brána pustí.
#   BRANOCESTA      cesta k tomuhle skriptu; tlačítko zpět ho umí otevřít znovu
#   BRANOCESTA_PID  proces brány, která aplikaci pustila. Když aplikace tuhle cestu umí, brána se po jejím
#                   spuštění nezavře, jen se schová a čeká na událost Branocesta.<PID> (viz Complete-Away):
#                   návrat je pak okamžitý, protože se nic nestartuje.
$env:BRANOCESTA = $PSCommandPath
$env:BRANOCESTA_PID = $PID
$back = New-Object Threading.EventWaitHandle $false, 'AutoReset', "Branocesta.$PID"

# Jak dlouho platí, co GitHub o vydáních řekl naposled. Tlačítko Zkontrolovat vydání se ptá vždycky.
$checkAfter = [TimeSpan]::FromMinutes(15)

$state = @{
    # Id aplikace -> @{ Installed; Latest; Phase; Error; Fresh }
    #   Installed  tag nainstalovaného vydání, '' = nainstalovaná není
    #   Latest     nejnovější vydání z Get-LatestRelease, $null = ještě ho neznáme
    #   Phase      'Checking' (hledá se vydání), 'Installing', 'Removing', 'Launching' nebo 'Idle'
    #   Error      hláška, proč se poslední kontrola, instalace, odinstalování nebo spuštění nepovedly
    #   Fresh      co se s aplikací stalo od poslední kontroly: 'Installed', 'Updated', 'Removed' nebo $null
    Apps = @{}
    # Vydání brány samotné: @{ Latest; Phase; Error }
    #   Latest  vydání novější než to, které běží; $null = žádné takové není, nebo se o něm neví
    #   Phase   'Idle', 'Updating' (stahuje se), 'Restarting' (nová brána se otevírá) nebo 'Done' (soubory
    #           jsou vyměněné, ale nová brána se sama neotevřela)
    #   Error   hláška, proč se aktualizace nepovedla
    Gateway = @{ Latest = $null; Phase = 'Idle'; Error = $null }
    # Co o vydáních řekl GitHub naposled a kdy: Id -> @{ Checked; Release } (viz Read-Known v Apps.ps1).
    Known = Read-Known $context
    # Vlákna pro úlohy na pozadí; vzniknou až s první úlohou.
    Pool = $null
    # PowerShell nastartovaný dopředu, ve kterém se rozběhne příští aplikace (viz Start-Standby), jinak $null.
    Standby = $null
    # Co brána pustila a na čí okno čeká: @{ App; Script; Process; GiveUp }, jinak $null (viz Start-Launch).
    Launch = $null
    # Aplikace, za kterou brána čeká schovaná: @{ App; Process }, jinak $null (viz Complete-Away).
    Away = $null
    # Okno už je vykreslené a první kontrola vydání začala.
    Started = $false
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

$jobs = New-Object System.Collections.ArrayList

# $done je jméno funkce, která dostane $tag (čeho se úloha týká) a její výsledek.
# Jméno, ne blok: uzávěr by neviděl funkce skriptu.
function Start-Work([string]$command, $arguments, [string]$done, $tag) {
    if (-not $state.Pool) {
        $state.Pool = [RunspaceFactory]::CreateRunspacePool(1, 4)
        $state.Pool.Open()
    }
    $shell = [PowerShell]::Create()
    $shell.RunspacePool = $state.Pool
    $null = $shell.AddScript($worker).AddArgument($library).AddArgument($command).AddArgument($arguments)
    $null = $jobs.Add(@{ Done = $done; Tag = $tag; Shell = $shell; Handle = $shell.BeginInvoke() })
}

function Complete-Work {
    if (-not $jobs.Count) { return }
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

function Test-SelfUpdating { $state.Gateway.Phase -in 'Updating', 'Restarting' }

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
    # Dokud brána aktualizuje sama sebe, s aplikacemi se nehýbe: za chvíli se otevře znovu.
    $free = -not $busy -and -not (Test-SelfUpdating)
    $ui["${id}Launch"].IsEnabled = $installed -and $entry.Phase -notin 'Installing', 'Removing', 'Launching' -and -not (Test-SelfUpdating)
    # Nainstalovat jde jen vydání, o kterém brána ví.
    $ui["${id}Install"].IsEnabled = $free -and [bool]$entry.Latest
    $ui["${id}Update"].IsEnabled = $free
    $ui["${id}Remove"].IsEnabled = $free

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

# Ptala se brána na vydání téhle aplikace před chvílí? Pak se při otevření neptá znovu.
function Test-Known($app) {
    $known = $state.Known[$app.Id]
    if (-not $known) { return $false }
    $age = [DateTime]::UtcNow - $known.Checked
    # Záporné stáří znamená přeřízené hodiny; takové odpovědi se nevěří.
    $age -ge [TimeSpan]::Zero -and $age -lt $checkAfter
}

function Save-Check($app, $release) {
    $state.Known[$app.Id] = @{ Checked = [DateTime]::UtcNow; Release = $release }
    Save-Known $context $state.Known
}

# Při otevření brány a po návratu z aplikace se ptá jen na vydání, která nezná nebo zná už dlouho.
# S -Force (tlačítko, F5) na všechna.
function Start-Refresh([switch]$Force) {
    # Dokud něco běží, další kontrola nezačne: přepsala by stav karty, na které se zrovna pracuje.
    if ($jobs.Count -or $state.Launch) { return }
    foreach ($app in $apps) {
        if (-not $Force -and (Test-Known $app)) { continue }
        $entry = $state.Apps[$app.Id]
        $entry.Phase = 'Checking'
        $entry.Error = $null
        $entry.Fresh = $null
        Update-App $app
        Start-Work 'Get-LatestRelease' @($context, $app) 'Complete-Check' $app
    }
    if ($selfUpdates -and $state.Gateway.Phase -eq 'Idle' -and ($Force -or -not (Test-Known $gateway))) {
        Start-Work 'Get-LatestRelease' @($context, $gateway) 'Complete-GatewayCheck' $gateway
    }
}

function Complete-Check($app, $result) {
    $entry = $state.Apps[$app.Id]
    $entry.Phase = 'Idle'
    if ($result.Ok) {
        $entry.Latest = $result.Data
        Save-Check $app $result.Data
    } else { $entry.Error = $result.Message }
    Update-App $app
}

# ---- Instalace, aktualizace a odinstalování ----
# Nainstalovat a Aktualizovat jsou tatáž úloha: stáhne nejnovější vydání a vymění jím složku aplikace.

function Start-Install($app) {
    $entry = $state.Apps[$app.Id]
    if ($entry.Phase -ne 'Idle' -or -not $entry.Latest -or (Test-SelfUpdating)) { return }
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
    if ($entry.Phase -ne 'Idle' -or -not $entry.Installed -or (Test-SelfUpdating)) { return }
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
# O své aktualizaci brána nerozhoduje sama, stejně jako u aplikací: když vyjde novější vydání, napíše to
# v zápatí a nabídne tlačítko. Po kliknutí si stáhne nové soubory, přepíše jimi své a otevře se znovu.
# Když se vydání zjistit nepodaří, nic se nehlásí; karty aplikací mají hlášky vlastní.

function Update-Footer {
    $own = $state.Gateway
    $latest = if ($own.Latest) { Format-Tag $own.Latest.Tag }
    $note =
        if ($own.Error) { $own.Error }
        elseif ($own.Phase -eq 'Updating') { "Stahuju verzi $latest brány…" }
        elseif ($own.Phase -eq 'Restarting') { "Brána se aktualizovala na verzi $latest. Otevírám ji znovu…" }
        elseif ($own.Phase -eq 'Done') { "Brána se aktualizovala na verzi $latest. Zavři ji a otevři znovu, ať běží ta nová." }
        elseif ($own.Latest) { "Vyšla verze $latest brány." }
    $brush = if ($own.Error) { 'Danger' } elseif ($note) { 'Text' } else { 'Muted' }
    $ui.FooterText.Foreground = $window.FindResource($brush)
    $ui.FooterText.Text = if ($note) { $note } else { $footerHint }
    $ui.GatewayUpdate.Visibility = if ($own.Latest -and $own.Phase -in 'Idle', 'Updating') { 'Visible' } else { 'Collapsed' }
    # Karty se během aktualizace brány zamykají (viz Update-App).
    foreach ($app in $apps) { Update-App $app }
}

function Complete-GatewayCheck($app, $result) {
    if (-not $result.Ok) { return }
    Save-Check $gateway $result.Data
    if ($state.Gateway.Phase -ne 'Idle') { return }
    $state.Gateway.Latest = if (Test-Newer $result.Data.Tag $version) { $result.Data }
    Update-Footer
}

function Start-GatewayUpdate {
    $own = $state.Gateway
    # Dokud se pracuje s aplikacemi, brána se nevyměňuje: zavřela by okno uprostřed jejich instalace.
    if ($own.Phase -ne 'Idle' -or -not $own.Latest -or $jobs.Count -or $state.Launch) { return }
    $own.Phase = 'Updating'
    $own.Error = $null
    Update-Footer
    Start-Work 'Update-Gateway' @($context, $own.Latest, $PSScriptRoot) 'Complete-GatewayUpdate' $own.Latest
}

function Complete-GatewayUpdate($release, $result) {
    $own = $state.Gateway
    if (-not $result.Ok) {
        $own.Phase = 'Idle'
        $own.Error = "Novou verzi brány $(Format-Tag $release.Tag) se nepodařilo nainstalovat. $($result.Message)"
        Update-Footer
        return
    }
    # Na disku už je nová brána. Otevře se se stejnými parametry jako tahle, a až ukáže okno, tahle se zavře.
    $problem = Start-Launch $gateway $PSCommandPath $relaunch
    $own.Phase = if ($problem) { 'Done' } else { 'Restarting' }
    Update-Footer
}

# ---- Spuštění aplikace ----
# Brána aplikaci pustí, počká, až ukáže své okno, pošle ho dopředu a teprve pak zmizí. Kdyby zmizela hned,
# Windows by mezitím aktivovaly jiné okno a aplikace by se otevřela schovaná za ním: vypadalo by to, že se
# nestalo nic. Stejně se brána po aktualizaci otevírá sama znovu.
#
# Nejdéle na spuštění trvá start PowerShellu a WPF. Brána si proto hned po svém otevření pustí schovaný
# PowerShell dopředu (Standby.ps1, dál "záloha"): ten si WPF načte a čeká. Po kliknutí na Spustit mu brána
# pošle cestu ke skriptu aplikace a aplikace se rozběhne v něm. Když brána skončí a nic nepustí, skončí
# záloha s ní.

# PowerShell bez okna konzole. Zástupci na to mají conhost --headless; brána pouští PowerShell rovnou, aby
# znala jeho proces a poznala, kdy ukázal okno nebo skončil. S -Piped mu může psát na standardní vstup.
function Start-Hidden([string]$arguments, [string]$directory, [switch]$Piped) {
    $info = New-Object Diagnostics.ProcessStartInfo (Join-Path $PSHOME 'powershell.exe')
    $info.Arguments = "-NoProfile -ExecutionPolicy Bypass $arguments"
    $info.WorkingDirectory = $directory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = [bool]$Piped
    [Diagnostics.Process]::Start($info)
}

function Start-Standby {
    # U -Screenshot se okno hned zase zavře a nic se nepouští.
    if ($state.Standby -or $Screenshot) { return }
    # Bez zálohy se aplikace pustí pomaleji, ale pustí (viz Start-Launch).
    try { $state.Standby = Start-Hidden "-File `"$(Join-Path $PSScriptRoot 'Standby.ps1')`"" $PSScriptRoot -Piped } catch { }
}

function Stop-Standby {
    $standby = $state.Standby
    $state.Standby = $null
    # Zavřený vstup je pro zálohu pokyn skončit.
    if ($standby) { try { $standby.StandardInput.Close() } catch { } }
}

# Pustí skript a zapamatuje si, že brána čeká na jeho okno. Vrací hlášku, když se to nepovede, jinak nic.
# Aplikace se rozběhne v záloze. Nový PowerShell se startuje, jen když záloha není (ještě nevznikla, nebo
# už skončila) a když brána po aktualizaci otevírá sama sebe: nová verze má začít v čistém procesu a se
# svými parametry.
function Start-Launch($app, [string]$script, [string]$extra) {
    $process = $state.Standby
    $sent = $false
    if ($process -and $app.Id -ne $gateway.Id) {
        $state.Standby = $null
        try {
            if (-not $process.HasExited) {
                # Cesta jde v Base64: kódování vstupu si každý proces drží po svém a háčky by cestou nepřežily.
                $line = [Text.Encoding]::ASCII.GetBytes([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script)) + "`n")
                $process.StandardInput.BaseStream.Write($line, 0, $line.Length)
                $sent = $true
            }
        } catch { }
        # Zavřený vstup bez cesty je pro zálohu pokyn skončit; s cestou už ho nepotřebuje.
        try { $process.StandardInput.Close() } catch { }
    }
    if (-not $sent) {
        try { $process = Start-Hidden "-File `"$script`"$extra" (Split-Path $script) }
        catch { return "Spuštění se nepovedlo: $($_.Exception.Message)" }
    }
    $state.Launch = @{ App = $app; Script = $script; Process = $process; GiveUp = [DateTime]::UtcNow.AddSeconds(30) }
}

function Start-App($app) {
    $entry = $state.Apps[$app.Id]
    if ($state.Launch -or $state.Away -or -not $entry.Installed -or (Test-SelfUpdating)) { return }
    # Co by teď přišlo po události Branocesta.<PID>, patří aplikaci, která už neběží.
    $null = $back.Reset()
    $entry.Error = Start-Launch $app (Join-Path (Get-AppDirectory $context $app) $app.Script) ''
    if (-not $entry.Error) { $entry.Phase = 'Launching' }
    Update-App $app
}

# Umí aplikace bránu zavolat zpátky? Pozná se to podle jejího skriptu: kdo tu cestu umí, čte proměnnou
# BRANOCESTA_PID. Starší vydání ji neznají a bránu si otevírají znovu samy; kvůli nim nemá smysl čekat.
function Test-Returns($launch) {
    if ($launch.App.Id -eq $gateway.Id) { return $false }
    try { [IO.File]::ReadAllText($launch.Script).Contains('BRANOCESTA_PID') } catch { $false }
}

# Volá se z časovače, dokud brána čeká na okno toho, co pustila.
function Complete-Launch {
    $launch = $state.Launch
    if (-not $launch) { return }
    $process = $launch.Process
    $app = $launch.App

    # Process si odpovědi pamatuje; bez Refresh by okno neviděl nikdy.
    $process.Refresh()
    $exited = $process.HasExited
    if (-not $exited -and $process.MainWindowHandle -ne [IntPtr]::Zero) {
        $state.Launch = $null
        # Brána je teď v popředí, takže smí dopředu poslat i cizí okno. Když to nevyjde, okno aplikace
        # zůstane tam, kde je.
        try { [Microsoft.VisualBasic.Interaction]::AppActivate($process.Id) } catch { }
        if (-not (Test-Returns $launch)) {
            $window.Close()
            return
        }
        # Aplikace umí bránu zavolat zpátky: brána se jen schová a čeká na ni (viz Complete-Away).
        $state.Apps[$app.Id].Phase = 'Idle'
        Update-App $app
        $state.Away = @{ App = $app; Process = $process }
        $window.Hide()
        # Schovaná brána může čekat hodiny. Okno WPF drží stovky megabajtů; takhle je Windows dostanou zpátky
        # hned a brána si při návratu vezme jen to, co opravdu potřebuje.
        [GC]::Collect()
        if ($native) { $null = $native::EmptyWorkingSet([Diagnostics.Process]::GetCurrentProcess().Handle) }
        return
    }

    $problem = if ($exited) { "$($app.Name) skončil hned po spuštění." }
        elseif ([DateTime]::UtcNow -gt $launch.GiveUp) { "$($app.Name) se zatím neukázal. Jestli se neotevře, zkus to znovu." }
    if (-not $problem) { return }
    $state.Launch = $null
    if ($app.Id -eq $gateway.Id) {
        # Soubory už jsou nové, jen se brána sama znovu neotevřela.
        $state.Gateway.Phase = 'Done'
        Update-Footer
        return
    }
    $entry = $state.Apps[$app.Id]
    $entry.Phase = 'Idle'
    $entry.Error = $problem
    Update-App $app
    # Zálohu spotřeboval nepovedený pokus; další má být zase rychlý.
    Start-Standby
}

# ---- Návrat z aplikace ----
# Aplikace, která to umí, bránu neotevírá znovu: nastaví událost Branocesta.<PID> a schovaná brána se
# ukáže. Nic se nestartuje, takže je to hned. Když aplikace skončí a bránu nezavolá, skončí brána taky.

# Vytáhne okno navrch, aniž by tam zůstalo natrvalo. Windows oknu, které se ukáže samo od sebe, popředí
# nedají: zůstalo by schované za tím, co bylo aktivní předtím.
function Show-OnTop {
    $window.Topmost = $true
    $window.Topmost = $false
    $null = $window.Activate()
}

# Volá se z časovače, dokud je brána schovaná za aplikací.
function Complete-Away {
    $away = $state.Away
    if (-not $away) { return }
    $called = $back.WaitOne(0)
    if (-not $called -and -not $away.Process.HasExited) { return }
    $state.Away = $null
    if (-not $called) {
        $window.Close()
        return
    }

    # Mezitím mohla jiná brána něco nainstalovat nebo odebrat a hlášky z doby před odchodem už neplatí.
    foreach ($app in $apps) {
        $entry = $state.Apps[$app.Id]
        $entry.Installed = Get-Installed $context $app
        $entry.Error = $null
        $entry.Fresh = $null
    }
    Update-Footer
    $window.Show()
    Show-OnTop
    Start-Refresh
    Start-Standby
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

    $names = @('FolderButton', 'RefreshButton', 'FooterText', 'GatewayUpdate', 'VersionText')
    foreach ($app in $apps) {
        foreach ($part in 'Icon', 'Version', 'Status', 'Busy', 'Launch', 'Install', 'Update', 'Remove') { $names += "$($app.Id)$part" }
    }
    $ui = @{}
    foreach ($name in $names) { $ui[$name] = $window.FindName($name) }
    $missing = @(foreach ($name in $names) { if ($null -eq $ui[$name]) { $name } })
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

    $window.Add_ContentRendered({
        # Když bránu otevře aplikace, která se hned nato zavře, Windows mezitím aktivují jiné okno.
        Show-OnTop
        # Okno je vidět; teď teprve to, co k jeho vykreslení nebylo potřeba.
        Add-Type -AssemblyName Microsoft.VisualBasic   # AppActivate pošle dopředu okno jiného procesu (viz Complete-Launch)
        Start-Refresh
        Start-Standby
        $state.Started = $true
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
        # Výslovně Průzkumník: Start-Process by si cestu ...\Branocesta\apps vyložil jako skript Apps.ps1,
        # který leží hned vedle, a otevřel by ten.
        Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList "`"$AppsPath`""
    })
    $ui.RefreshButton.Add_Click({ Start-Refresh -Force })
    $ui.GatewayUpdate.Add_Click({ Start-GatewayUpdate })
    $window.Add_KeyDown({
        param($source, $e)
        if ($e.Key -ne 'F5') { return }
        Start-Refresh -Force
        $e.Handled = $true
    })

    $timer = [Windows.Threading.DispatcherTimer]::new()
    # Po tomhle intervalu si brána všimne okna spuštěné aplikace i toho, že ji aplikace volá zpátky.
    # Kratší by návrat zrychlil jen o desítky milisekund a schovaná brána by zbytečně budila procesor.
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)
    $timer.Add_Tick({
        # Schovaná brána jen čeká na aplikaci; na okně se nic nemění a úlohy na pozadí počkají na návrat.
        if ($state.Away) {
            Complete-Away
            return
        }
        Complete-Work
        Complete-Launch
        $ui.RefreshButton.IsEnabled = -not ($jobs.Count -or $state.Launch)
        $ui.GatewayUpdate.IsEnabled = $ui.RefreshButton.IsEnabled -and $state.Gateway.Phase -eq 'Idle'

        if ($Screenshot -and $state.Started -and -not $jobs.Count) {
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
    # Karty hned ukážou, co brána o vydáních ví z minula; na GitHub se ptá až po vykreslení okna, a jen když
    # je to potřeba (viz Start-Refresh).
    foreach ($app in $apps) {
        $known = $state.Known[$app.Id]
        $state.Apps[$app.Id] = @{
            Installed = Get-Installed $context $app; Latest = $(if ($known) { $known.Release })
            Phase = 'Idle'; Error = $null; Fresh = $null
        }
    }
    $known = $state.Known[$gateway.Id]
    if ($selfUpdates -and $known -and (Test-Newer $known.Release.Tag $version)) { $state.Gateway.Latest = $known.Release }
    Update-Footer

    # Okno není dialog (ShowDialog): to by se schovat nedalo, schování dialog ukončí. Smyčka zpráv běží,
    # dokud se okno nezavře, i když zrovna není vidět.
    $frame = [Windows.Threading.DispatcherFrame]::new()
    $window.Add_Closed({ $frame.Continue = $false })
    $timer.Start()
    $window.Show()
    [Windows.Threading.Dispatcher]::PushFrame($frame)
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
finally {
    Stop-Standby
    $back.Dispose()
}
