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
[System.String]$WinEdition = "Home"
[System.String]$WinArch = "x64"
[System.String]$FidoRelease = "21H1"
[System.String]$WinLcid = "English"
[System.String]$SupportedWinRelease = "Windows ${WinRelease}"  # WindowsRelease (Windows_7, Windows_8, Windows_8_1, Windows_10, Windows_11) <~ see repasscloud/WindowsCapability/issues/2

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
Get-WindowsOptionalFeature -Path "${env:TMP}\Win${WinRelease}_${FidoRelease}_${WinLcid}_${WinArch}_MOUNT" | ForEach-Object {

    $obj = $_

    [System.String]$FeatureName = $obj.'FeatureName'
    [System.String]$State = $obj.'State'
    switch ($State)
    {
        'Enabled' {
            $Enabled = $true
        }
        'Disabled' {
            $Enabled = $false
        }
        'DisabledWithPayloadRemoved' {
            $Enabled = $false
        }
        Default {
            $Enabled = $false
        }
    }

    Write-Output "Verifying WindowsOptionalFeature: ${FeatureName}"

    try
    {
        Invoke-RestMethod -Uri "${env:API_URI}/v1/windowsoptionalfeature/name/${FeatureName}" -Method Get -Headers $CHeaders -ErrorAction Stop | Out-Null
        
        $RecordFound = Invoke-RestMethod -Uri "${env:API_URI}/v1/windowsoptionalfeature/name/${FeatureName}" -Method Get -Headers $CHeaders
        [System.Int64]$Id = $RecordFound.id

        <# SUPPORTEDWINDOWSVERSIONS #>
        if (@($RecordFound.supportedWindowsVersions) -notcontains $FidoRelease)
        {
            $newArray = @($RecordFound.supportedWindowsVersions) + $FidoRelease
            $Body = @{
                id = $Id
                uuid = $RecordFound.uuid
                featureName = $RecordFound.featurename
                enabled = [System.Boolean]$RecordFound.enabled
                supportedWindowsVersions = $newArray
                supportedWindowsEditions = @($RecordFound.supportedWindowsEditions)
                supportedWindowsReleases = @($RecordFound.supportedWindowsReleases)
            } | ConvertTo-Json
            Write-Output "<| Test SupportedWindowsVersions"
            Invoke-RestMethod -Uri "${env:API_URI}/v1/windowsoptionalfeature/${Id}" -Method Put -UseBasicParsing -Body $Body -ContentType 'application/json' -ErrorAction Stop
        }
        else
        {
            Write-Output "  => SupportedWindowsVersions OK"
        }

        <# SUPPORTEDWINDOWSEDITIONS #>
        if (@($RecordFound.supportedWindowsEditions) -notcontains $WinEdition)
        {
            $newArray = @($RecordFound.supportedWindowsEditions) + $WinEdition
            $Body = @{
                id = $Id
                uuid = $RecordFound.uuid
                featureName = $RecordFound.featurename
                enabled = [System.Boolean]$RecordFound.enabled
                supportedWindowsVersions = @($RecordFound.supportedWindowsVersions)
                supportedWindowsEditions = $newArray
                supportedWindowsReleases = @($RecordFound.supportedWindowsReleases)
            } | ConvertTo-Json
            Write-Output "<| Test SupportedWindowsEditions"
            Invoke-RestMethod -Uri "${env:API_URI}/v1/windowsoptionalfeature/${Id}" -Method Put -UseBasicParsing -Body $Body -ContentType 'application/json' -ErrorAction Stop
        }
        else
        {
            Write-Output "  => SupportedWindowsEditions OK"
        }

        <# SUPPORTEDWINDOWSRELEASES #>
        if (@($RecordFound.supportedWindowsReleases) -notcontains $SupportedWinRelease)
        {
            $newArray = @($RecordFound.supportedWindowsReleases) + $SupportedWinRelease
            $Body = @{
                id = $Id
                uuid = $RecordFound.uuid
                featureName = $RecordFound.featurename
                enabled = [System.Boolean]$RecordFound.enabled
                supportedWindowsVersions = @($RecordFound.supportedWindowsVersions)
                supportedWindowsEditions = @($RecordFound.supportedWindowsEditions)
                supportedWindowsReleases = $newArray
            } | ConvertTo-Json
            Write-output "<| Test SupportedWindowsReleases"
            Invoke-RestMethod -Uri "${env:API_URI}/v1/windowsoptionalfeature/${Id}" -Method Put -UseBasicParsing -Body $Body -ContentType 'application/json' -ErrorAction Stop
        }
        else
        {
            Write-Output "  => SupportedWindowsReleases OK"
        }
    }
    catch
    {
        $SupportedWindowsRelease = $FidoRelease
        $Body = @{
            id = 0
            uuid = [System.Guid]::NewGuid().Guid.ToString()
            featureName = $FeatureName
            enabled = [System.Boolean]$Enabled
            supportedWindowsVersions = @($SupportedWindowsRelease)
            supportedWindowsEditions = @($WinEdition)
            supportedWindowsReleases = @($SupportedWinRelease)
        } | ConvertTo-Json
        try
        {
            Invoke-RestMethod -Uri "${env:API_URI}/v1/windowsoptionalfeature/${Id}" -Method Post -UseBasicParsing -Body $Body -ContentType 'application/json' -ErrorAction Stop
        }
        catch
        {
            Write-Warning "Error: $($_.Exception)"
        }
    }
}

<# CLEAN UP #>
Dismount-WindowsImage -Path "${env:TMP}\Win${WinRelease}_${FidoRelease}_${WinLcid}_${WinArch}_MOUNT" -Discard
Remove-Item -Path "${env:TMP}\Win${WinRelease}_${FidoRelease}_${WinLcid}_${WinArch}_MOUNT" -Recurse -Force -Confirm:$false
Dismount-DiskImage -ImagePath $IsoFile -Confirm:$false
Remove-Item -Path $IsoFile -Confirm:$false -Force