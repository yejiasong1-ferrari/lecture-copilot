$ErrorActionPreference = 'Stop'
$Base = 'https://github.com/yejiasong1-ferrari/lecture-copilot/releases/latest/download'
$Name = 'Lecture-Copilot-Windows-x64-Setup.exe'
$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ("lecture-copilot-" + [Guid]::NewGuid().ToString('N'))
$Setup = Join-Path $Temp $Name
$Checksum = "$Setup.sha256"

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Lecture Copilot requires 64-bit Windows 10 or Windows 11.'
}

New-Item -ItemType Directory -Path $Temp | Out-Null
try {
    Write-Host 'Downloading Lecture Copilot for Windows...'
    Invoke-WebRequest "$Base/$Name" -OutFile $Setup -UseBasicParsing
    Invoke-WebRequest "$Base/$Name.sha256" -OutFile $Checksum -UseBasicParsing
    $Expected = (Get-Content $Checksum -Raw).Trim().Split(' ')[0].ToLowerInvariant()
    $Actual = (Get-FileHash $Setup -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not $Expected -or $Expected -ne $Actual) {
        throw 'The download failed SHA-256 verification. Installation stopped.'
    }
    Start-Process -FilePath $Setup -ArgumentList '/CURRENTUSER' -Wait
}
finally {
    Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
