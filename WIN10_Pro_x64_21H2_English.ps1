<# PRE EXECUTION SETUP #>
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.String]$repo = "pbatard/Fido"
[System.String]$releases = "https://api.github.com/repos/${repo}/releases"
Write-Output "Determining latest release"
[System.String]$tag = (Invoke-WebRequest $releases | ConvertFrom-Json)[0].tag_name
[System.String]$download = "https://github.com/${repo}/archive/refs/tags/${tag}.zip"
[System.String]$zipfile = Split-Path -Path $download -Leaf
[System.String]$dirname = $zipfile -replace '.*\.zip$',''
Write-Output "Downloading latest release"
Invoke-WebRequest -UseBasicParsing -Uri $download -OutFile $zipfile
Write-Output "Extracting release files"
Expand-Archive $zipfile -Force
Remove-Item -Path $zipfile -Recurse -Force -ErrorAction SilentlyContinue 
[System.String]$FidoFile = Get-ChildItem -Path ".\${dirname}" -Recurse -Filter "Fido.ps1" | Select-Object -ExpandProperty FullName
$CHeaders = @{accept = 'application/json'}

<# CONFIG #>
[System.String]$WinRelease = "10"
[System.String]$WinEdition = "Pro"
[System.String]$WinArch = "x64"
[System.String]$FidoRelease = "21H2"
[System.String]$WinLcid = "English"
[System.String]$SupportedWinRelease = "Windows_10"

<# SETUP #>
[System.String]$DownloadLink = & $FidoFile -Win $WinRelease -Rel $FidoRelease -Ed $WinEdition -Lang $WinLcid -Arch $WinArch -GetUrl
Invoke-WebRequest -UseBasicParsing -Uri $DownloadLink -OutFile "Win${WinRelease}_${FidoRelease}_${WinLcid}_${WinArch}.iso" -ContentType "application/octet-stream"
[System.String]$IsoFile = Get-ChildItem -Path . -Recurse -Filter "*.iso" | Select-Object -ExpandProperty FullName

<# MOUNT #>
$iso = Mount-DiskImage -ImagePath $IsoFile -Access ReadOnly -StorageType ISO
[System.String]$DriveLetter = $($iso | Get-Volume | Select-Object -ExpandProperty DriveLetter) + ":"
[System.String]$InstallWIM = Get-ChildItem -Path "${DriveLetter}\" -Recurse -Filter "install.wim" | Select-Object -ExpandProperty FullName
New-Item -Path $env:TMP -ItemType Directory -Name "Win${WinRelease}_${FidoRelease}_${WinLcid}_${WinArch}_MOUNT" -Force -Confirm:$false
[System.String]$ImageIndex = Get-WindowsImage -ImagePath $InstallWIM | Where-Object -FilterScript {$_.ImageName -match '^Windows 10 Pro$'} | Select-Object -ExpandProperty ImageIndex
Mount-WindowsImage -ImagePath $InstallWIM -Index $ImageIndex -Path "${env:TMP}\Win${WinRelease}_${FidoRelease}_${WinLcid}_${WinArch}_MOUNT" -ReadOnly

<# MAIN API EXEC #>
Get-WindowsOptionalFeature -Path "${env:TMP}\Win${WinRelease}_${FidoRelease}_${WinLcid}_${WinArch}_MOUNT"