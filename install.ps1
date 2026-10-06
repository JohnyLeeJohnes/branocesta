# Web installer for Branocesta. Run it with:
#   powershell -c "irm https://raw.githubusercontent.com/JohnyLeeJohnes/branocesta/master/install.ps1 | iex"
# It downloads the latest release into %LOCALAPPDATA%\Branocesta, creates the shortcuts and opens the gateway.
# Running it again updates the gateway; the apps it has installed (the apps folder next to it) stay.
#
# Keep this file plain ASCII without a BOM: irm leaves a BOM in the text and iex fails on it,
# and without a BOM Windows PowerShell misreads non-ASCII characters when the file is run from disk.

# The script block keeps the variables out of the session of whoever pasted the command.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $target = Join-Path $env:LOCALAPPDATA 'Branocesta'
    $download = Join-Path ([IO.Path]::GetTempPath()) "Branocesta-$PID.zip"
    Invoke-WebRequest 'https://github.com/JohnyLeeJohnes/branocesta/releases/latest/download/Branocesta.zip' -OutFile $download -UseBasicParsing
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($download)
        try {
            foreach ($entry in $zip.Entries) {
                if (-not $entry.Name) { continue }   # a folder
                # Everything in the ZIP sits in one folder, Branocesta; its content goes straight into the target.
                $path = Join-Path $target ($entry.FullName -replace '^[^/]+/')
                $null = New-Item -ItemType Directory -Force (Split-Path $path)
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $path, $true)
            }
        } finally { $zip.Dispose() }
    } finally { Remove-Item $download }

    # A separate process, because the execution policy of this session may not allow script files.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $target 'Branocesta.ps1') -Install
    if ($LASTEXITCODE) { throw 'Creating the shortcuts failed.' }

    # Started from Win+R this window closes right away, so opening the gateway is how you see it worked.
    Invoke-Item (Join-Path $target '*.lnk')
}
