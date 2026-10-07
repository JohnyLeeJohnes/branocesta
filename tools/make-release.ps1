# Sestaví ZIP pro GitHub Release do složky dist/:
#   powershell -ExecutionPolicy Bypass -File tools/make-release.ps1
# V ZIPu je složka Branocesta jen s tím, co brána potřebuje k běhu. Jméno ZIPu je schválně bez čísla verze,
# aby odkaz releases/latest/download/Branocesta.zip platil i pro každé další vydání.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$root = Split-Path $PSScriptRoot
# Testy, nástroje a obrázky do README zůstávají jen v repozitáři.
$items = 'Branocesta.ps1', 'Branocesta.xaml', 'Apps.ps1', 'Standby.ps1', 'Branocesta.cmd', 'install.cmd', 'README.md', 'CHANGELOG.md', 'assets\branocesta.ico'

$dist = Join-Path $root 'dist'
$null = New-Item -ItemType Directory -Force $dist
$zipPath = Join-Path $dist 'Branocesta.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath }

$zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    foreach ($item in $items) {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $root $item))
        # cmd.exe čte spolehlivě jen konce řádků CRLF a v pracovní kopii mohou být LF.
        if ($item -like '*.cmd') {
            $bytes = [Text.Encoding]::ASCII.GetBytes(([Text.Encoding]::ASCII.GetString($bytes) -replace "`r?`n", "`r`n"))
        }
        # V ZIPu patří do cest lomítka dopředu; se zpětnými si neporadí každý rozbalovací program.
        $stream = $zip.CreateEntry('Branocesta/' + $item.Replace('\', '/'), 'Optimal').Open()
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    }
} finally { $zip.Dispose() }

"OK: dist/Branocesta.zip ($([Math]::Round((Get-Item $zipPath).Length / 1KB)) kB)"
