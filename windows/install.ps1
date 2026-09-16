$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# PowerShell 5 默认进度条会把 GitHub 下载拖得极慢，看起来像卡死。
$ProgressPreference = 'SilentlyContinue'

$Base = 'https://github.com/yejiasong1-ferrari/lecture-copilot/releases/latest/download'
$Name = 'Lecture-Copilot-Windows-x64-Setup.exe'
$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ("lecture-copilot-" + [Guid]::NewGuid().ToString('N'))
$Setup = Join-Path $Temp $Name
$Checksum = "$Setup.sha256"
$BrowserUrl = "$Base/$Name"

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Lecture Copilot 需要 64 位 Windows 10 或 Windows 11。'
}

New-Item -ItemType Directory -Path $Temp | Out-Null
try {
    Write-Host ''
    Write-Host 'Lecture Copilot for Windows'
    Write-Host '安装包大约 70 MB。国内访问 GitHub 往往要几分钟，进度条不动也请不要关窗口。'
    Write-Host '等太久的话，用浏览器打开下面的链接，下载后双击即可：'
    Write-Host "  $BrowserUrl"
    Write-Host ''
    Write-Host "正在下载 $Name ..."

    $headers = @{ 'User-Agent' = 'LectureCopilot-Installer' }
    try {
        Invoke-WebRequest -Uri $BrowserUrl -OutFile $Setup -UseBasicParsing -Headers $headers
        Invoke-WebRequest -Uri "$BrowserUrl.sha256" -OutFile $Checksum -UseBasicParsing -Headers $headers
    } catch {
        throw @"
下载失败：$($_.Exception.Message)

请改用浏览器下载后双击安装：
$BrowserUrl

注意：PowerShell 里必须整行粘贴，末尾要有  | iex
"@
    }

    $Bytes = (Get-Item $Setup).Length
    if ($Bytes -lt 1MB) {
        throw @"
下载到的不是安装包（只有 $Bytes 字节），多半是 GitHub 被拦截或返回了网页。
请用浏览器打开：
$BrowserUrl
"@
    }

    Write-Host ("下载完成（{0:N1} MB），正在校验..." -f ($Bytes / 1MB))
    $Expected = (Get-Content $Checksum -Raw).Trim().Split(' ')[0].ToLowerInvariant()
    $Actual = (Get-FileHash $Setup -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not $Expected -or $Expected -ne $Actual) {
        throw 'SHA-256 校验失败，安装已停止。请改用浏览器重新下载。'
    }

    Write-Host '校验通过，正在打开安装向导...'
    Start-Process -FilePath $Setup -ArgumentList '/CURRENTUSER' -Wait
}
finally {
    Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
