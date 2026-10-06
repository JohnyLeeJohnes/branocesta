# Apps.ps1: které aplikace Bránocesta zná, jak zjistí jejich nejnovější vydání na GitHubu, jak ho nainstaluje
# a jak aplikaci zase odebere.
# Žádné okno: funkce běží na pozadí (Branocesta.ps1) i v testech (tests/test.ps1).
# Úlohy na pozadí si tenhle soubor nenačítají z disku, ale z textu, který si okno přečetlo při startu,
# takže se tu nedá spoléhat na $PSScriptRoot.
#
# $context = @{ Source = $null; Root = '...' }
# Root je jedna společná složka, do které se aplikace instalují (každá do <Root>\<Id>). Se Source = cesta ke složce se místo GitHubu čtou soubory
# <repozitář>.json a <repozitář>.zip (viz Read-Source).

Add-Type -AssemblyName System.Net.Http, System.IO.Compression, System.IO.Compression.FileSystem

# Aplikace v pořadí, v jakém jsou v okně. Id je jméno složky po instalaci a předpona prvků v Branocesta.xaml,
# Script soubor, kterým se aplikace spouští. Repozitáře jsou veřejné, takže se GitHubu není třeba prokazovat.
$apps = @(
    @{ Id = 'Spac'; Name = 'Spáč'; Repository = 'JohnyLeeJohnes/spac'; Script = 'Spac.ps1' }
    @{ Id = 'Sluzbak'; Name = 'Službák'; Repository = 'JohnyLeeJohnes/sluzbak'; Script = 'Sluzbak.ps1' }
    @{ Id = 'Mesec'; Name = 'Měšec'; Repository = 'JohnyLeeJohnes/mesec'; Script = 'Mesec.ps1' }
)

# Brána sama. Vydání má na GitHubu stejně jako aplikace, jen se instaluje jinak (viz Update-Gateway).
$gateway = @{ Id = 'Branocesta'; Name = 'Bránocesta'; Repository = 'JohnyLeeJohnes/branocesta'; Script = 'Branocesta.ps1' }

# Soubor ve složce aplikace s tagem vydání, ze kterého je nainstalovaná.
$releaseFile = '.release'

# ---- Chyby ----
# Chyba nese druh (NotFound, RateLimited, Network, Busy, Unexpected) a českou hlášku pro uživatele.

function New-AppError([string]$kind, [string]$message) {
    $exception = [Exception]::new($message)
    $exception.Data['Kind'] = $kind
    $exception
}

# Běžící aplikace má svou složku otevřenou a Windows ji nedovolí přejmenovat ani smazat.
function New-BusyError($app) { New-AppError 'Busy' "$($app.Name) právě běží. Zavři ho a zkus to znovu." }

function ConvertTo-AppError([int]$status) {
    switch ($status) {
        404 { New-AppError 'NotFound' 'Vydání jsem na GitHubu nenašel.' }
        # Bez přihlášení dovolí GitHub 60 dotazů za hodinu z jedné adresy.
        { $_ -in 403, 429 } { New-AppError 'RateLimited' 'GitHub teď další dotazy nepustí, zkus to za chvíli.' }
        default { New-AppError 'Unexpected' "GitHub vrátil chybu $status." }
    }
}

# ---- HTTP ----

# Klient žije v globální proměnné, aby ho úlohy na pozadí sdílely a spojení se neotvíralo pokaždé znovu.
function Get-HttpClient {
    if (-not $global:BranocestaHttp) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AutomaticDecompression = 'GZip, Deflate'
        $global:BranocestaHttp = New-Object System.Net.Http.HttpClient $handler
        $global:BranocestaHttp.Timeout = [TimeSpan]::FromSeconds(60)
        # GitHub dotazy bez představení odmítá.
        $null = $global:BranocestaHttp.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', 'Branocesta (+https://github.com/JohnyLeeJohnes/branocesta)')
    }
    $global:BranocestaHttp
}

# Vrátí tělo odpovědi jako bajty. $accept říká GitHubu, jestli chceme popis vydání, nebo samotný soubor.
function Invoke-Http([string]$uri, [string]$accept) {
    $request = New-Object System.Net.Http.HttpRequestMessage ([Net.Http.HttpMethod]::Get), $uri
    $null = $request.Headers.TryAddWithoutValidation('Accept', $accept)
    try {
        $response = (Get-HttpClient).SendAsync($request).GetAwaiter().GetResult()
        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    } catch {
        if ($_.Exception.GetBaseException() -is [OperationCanceledException]) {
            throw (New-AppError 'Network' 'GitHub neodpověděl včas. Zkus to za chvíli.')
        }
        throw (New-AppError 'Network' 'Nepodařilo se spojit s GitHubem. Zkontroluj připojení k internetu.')
    }
    if (-not $response.IsSuccessStatusCode) { throw (ConvertTo-AppError ([int]$response.StatusCode)) }
    , $bytes
}

# Vydání ze složky místo z GitHubu: JohnyLeeJohnes/spac -> spac.json (popis vydání) a spac.zip (soubory).
function Read-Source($context, $app, [string]$extension) {
    $file = Join-Path $context.Source ((Split-Path $app.Repository -Leaf) + $extension)
    if (-not (Test-Path -LiteralPath $file)) { throw (New-AppError 'NotFound' "Ve složce s vydáními chybí $(Split-Path $file -Leaf).") }
    , [IO.File]::ReadAllBytes($file)
}

# ---- Vydání ----

# Nejnovější vydání aplikace: @{ Tag; Url; Accept }. Url je ZIP přiložený k vydání; když u vydání žádný není,
# archiv zdrojáků, který GitHub dělá ke každému tagu.
function Get-LatestRelease($context, $app) {
    $bytes = if ($context.Source) { Read-Source $context $app '.json' }
        else { Invoke-Http "https://api.github.com/repos/$($app.Repository)/releases/latest" 'application/vnd.github+json' }
    # Dekódujeme sami, ať název vydání s háčky nezávisí na tom, co server napíše do hlavičky.
    try { $release = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json }
    catch { throw (New-AppError 'Unexpected' 'GitHub poslal odpověď, které nerozumím.') }
    if (-not $release.tag_name) { throw (New-AppError 'Unexpected' 'GitHub poslal vydání bez čísla verze.') }

    $asset = @($release.assets | Where-Object { $_.name -like '*.zip' })[0]
    if ($asset) { @{ Tag = [string]$release.tag_name; Url = [string]$asset.url; Accept = 'application/octet-stream' } }
    else { @{ Tag = [string]$release.tag_name; Url = [string]$release.zipball_url; Accept = 'application/vnd.github+json' } }
}

function Get-AppDirectory($context, $app) { Join-Path $context.Root $app.Id }

# Tag vydání, ze kterého je aplikace nainstalovaná; '' když nainstalovaná není.
function Get-Installed($context, $app) {
    $directory = Get-AppDirectory $context $app
    if (-not (Test-Path -LiteralPath (Join-Path $directory $app.Script))) { return '' }
    try { [IO.File]::ReadAllText((Join-Path $directory $releaseFile)).Trim() }
    catch { '' }   # Bez záznamu o vydání se nainstaluje znovu.
}

# Rozbalí ZIP z paměti do složky. Vydání mají všechno v jedné složce (Sluzbak/, u archivu zdrojáků
# JohnyLeeJohnes-spac-<commit>/); ta se vynechá, aby soubory aplikace ležely přímo v cíli.
function Expand-Release([byte[]]$bytes, [string]$target) {
    $stream = New-Object System.IO.MemoryStream (, $bytes)
    try { $zip = New-Object System.IO.Compression.ZipArchive $stream }
    catch { throw (New-AppError 'Unexpected' 'Stažené vydání není ZIP.') }
    try {
        $files = @($zip.Entries | Where-Object { $_.Name })   # složky mají jméno prázdné
        $folders = @($files | ForEach-Object { ($_.FullName -split '[\\/]')[0] } | Select-Object -Unique)
        $loose = @($files | Where-Object { $_.FullName -notmatch '[\\/]' })
        $skip = if ($folders.Count -eq 1 -and -not $loose) { $folders[0].Length + 1 } else { 0 }

        $base = [IO.Path]::GetFullPath($target).TrimEnd('\') + '\'
        foreach ($entry in $files) {
            $path = [IO.Path]::GetFullPath((Join-Path $base $entry.FullName.Substring($skip)))
            # Cesta s ".." by soubor položila mimo složku aplikace.
            if (-not $path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
                throw (New-AppError 'Unexpected' 'Vydání obsahuje soubor, který míří mimo složku aplikace.')
            }
            $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $path, $true)
        }
    } finally {
        $zip.Dispose()
        $stream.Dispose()
    }
}

# Stáhne vydání a nainstaluje ho do <Root>\<Id>. Vrací nainstalovaný tag.
# Nové soubory se chystají vedle a složky se vymění až nakonec, takže nepovedená instalace starou verzi nerozbije.
function Install-Release($context, $app, $release) {
    $bytes = if ($context.Source) { Read-Source $context $app '.zip' } else { Invoke-Http $release.Url $release.Accept }

    $directory = Get-AppDirectory $context $app
    $staging = "$directory.new"
    $former = "$directory.old"
    try {
        foreach ($leftover in $staging, $former) {
            if (Test-Path -LiteralPath $leftover) { Remove-Item -LiteralPath $leftover -Recurse -Force }
        }
        Expand-Release $bytes $staging
        if (-not (Test-Path -LiteralPath (Join-Path $staging $app.Script))) {
            throw (New-AppError 'Unexpected' "Ve vydání $($release.Tag) chybí $($app.Script).")
        }
        [IO.File]::WriteAllText((Join-Path $staging $releaseFile), $release.Tag)

        $replaces = Test-Path -LiteralPath $directory
        if ($replaces) {
            try { [IO.Directory]::Move($directory, $former) }
            catch { throw (New-BusyError $app) }
        }
        try { [IO.Directory]::Move($staging, $directory) }
        catch {
            if ($replaces) { [IO.Directory]::Move($former, $directory) }
            throw
        }
    } finally {
        foreach ($leftover in $staging, $former) {
            try { if (Test-Path -LiteralPath $leftover) { Remove-Item -LiteralPath $leftover -Recurse -Force } } catch { }
        }
    }
    $release.Tag
}

# Odebere aplikaci ze složky <Root>\<Id>. Složka se nejdřív přejmenuje a teprve pak maže: přejmenování se
# povede buď celé, nebo vůbec, takže běžící aplikace nezůstane napůl smazaná. Data si aplikace drží jinde.
function Uninstall-App($context, $app) {
    $directory = Get-AppDirectory $context $app
    $former = "$directory.old"
    if (Test-Path -LiteralPath $former) { Remove-Item -LiteralPath $former -Recurse -Force }
    if (-not (Test-Path -LiteralPath $directory)) { return }
    try { [IO.Directory]::Move($directory, $former) }
    catch { throw (New-BusyError $app) }
    # Co nejde smazat hned, uklidí příští instalace.
    try { Remove-Item -LiteralPath $former -Recurse -Force } catch { }
}

# ---- Brána sama ----

# Je vydání novější než verze, která právě běží? Tag, který není číslo verze, se za novější nepovažuje.
function Test-Newer([string]$tag, [string]$version) {
    $latest = $null
    $current = $null
    [version]::TryParse(($tag -replace '^v'), [ref]$latest) -and [version]::TryParse($version, [ref]$current) -and $latest -gt $current
}

# Přepíše soubory brány ve složce $directory novým vydáním. Vrací nainstalovaný tag.
# Brána ze své složky běží, takže ji nejde vyměnit celou jako u aplikací. Vydání se proto nejdřív rozbalí
# stranou a zkontroluje, pak se nové soubory položí vedle starých a teprve nakonec je nahradí.
function Update-Gateway($context, $release, [string]$directory) {
    $bytes = if ($context.Source) { Read-Source $context $gateway '.zip' } else { Invoke-Http $release.Url $release.Accept }

    $staging = Join-Path ([IO.Path]::GetTempPath()) "Branocesta-$([Guid]::NewGuid().ToString('N'))"
    $targets = New-Object System.Collections.ArrayList
    try {
        Expand-Release $bytes $staging
        foreach ($required in $gateway.Script, 'Apps.ps1', 'Branocesta.xaml') {
            if (-not (Test-Path -LiteralPath (Join-Path $staging $required))) {
                throw (New-AppError 'Unexpected' "Ve vydání $($release.Tag) chybí $required.")
            }
        }

        $base = $staging.TrimEnd('\') + '\'
        foreach ($file in Get-ChildItem -LiteralPath $staging -Recurse -File) {
            $target = Join-Path $directory $file.FullName.Substring($base.Length)
            $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            $null = $targets.Add($target)
            [IO.File]::Copy($file.FullName, "$target.new", $true)
        }
        # Sem se dojde, jen když se do složky dá zapisovat a nové soubory jsou celé; výměna už je jen přejmenování.
        foreach ($target in $targets) {
            if ([IO.File]::Exists($target)) { [IO.File]::Delete($target) }
            [IO.File]::Move("$target.new", $target)
        }
    } finally {
        foreach ($target in $targets) { try { [IO.File]::Delete("$target.new") } catch { } }
        try { if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force } } catch { }
    }
    $release.Tag
}
