$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $PSScriptRoot 'LectureCopilot.Windows\LectureCopilot.Windows.csproj'
$Publish = Join-Path $PSScriptRoot 'dist\win-x64'

dotnet publish $Project -c Release -r win-x64 --self-contained true -o $Publish
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed' }

$IsccCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
)
$Iscc = $IsccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Iscc) {
    Write-Host 'App published. Install Inno Setup 6 to create the setup executable.'
    exit 0
}

& $Iscc (Join-Path $PSScriptRoot 'installer\LectureCopilot.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }

$Setup = Join-Path $PSScriptRoot 'dist\installer\Lecture-Copilot-Windows-x64-Setup.exe'
$Hash = (Get-FileHash $Setup -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path "$Setup.sha256" -Value "$Hash  Lecture-Copilot-Windows-x64-Setup.exe" -Encoding ascii
Write-Host "Built: $Setup"
