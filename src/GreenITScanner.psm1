# User story #16
# Testar om en angiven maskin eller IP-adress är online via ping.
# Returnerar True om maskinen svarar, annars False.
function Test-GreenITConnection {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    try {
        return Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction Stop
    }
    catch {
        return $false
    }
}

# User story #16
# Försöker hämta hostname för en angiven maskin eller IP-adress.
# Returnerar hostname om det går, annars null.
function Resolve-GreenITHostName {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    try {
        return ([System.Net.Dns]::GetHostEntry($ComputerName)).HostName
    }
    catch {
        return $null
    }
}

# User story #20
# Startar en nätverksskanning för en eller flera maskiner/IP-adresser.
# Använder funktionerna för ping och hostname så att koden blir mer strukturerad och modulär.
function Start-GreenITScan {
    param(
        [Parameter(Mandatory)]
        [string[]]$ComputerName
    )

    foreach ($computer in $ComputerName) {
        $online = Test-GreenITConnection -ComputerName $computer
        $hostName = $null

        if ($online) {
            $hostName = Resolve-GreenITHostName -ComputerName $computer
        }

        [pscustomobject]@{
            ComputerName = $computer
            HostName     = $hostName
            Online       = $online
        }
    }
}

# User story #8
# Hämtar grundläggande information om en maskin.
# Använder ping, hostname och CIM för att bedöma om maskinen är aktiv eller inaktiv.
# Om maskinen har varit igång mer än angivet antal timmar får den status Inaktiv.
function Get-GreenITMachineInfo {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [string]$HostName,

        [string]$GreenITUser,

        [string]$GreenITPassword,

        [int]$InactiveAfterHours = 4
    )

    $online = Test-GreenITConnection -ComputerName $ComputerName

    if ([string]::IsNullOrWhiteSpace($HostName)) {
        $HostName = Resolve-GreenITHostName -ComputerName $ComputerName
    }

    if (-not $online) {
        return [pscustomobject]@{
            ComputerName   = $ComputerName
            HostName       = $HostName
            Online         = $false
            LastBootUpTime = $null
            UptimeHours    = $null
            Status         = "Offline"
        }
    }

    $cimSession = $null

    try {
        $isLocalMachine = (
            $ComputerName -eq "localhost" -or
            $ComputerName -eq "127.0.0.1" -or
            $ComputerName -eq $env:COMPUTERNAME -or
            $HostName -like "$env:COMPUTERNAME*"
        )

        if ($isLocalMachine) {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        }
        else {
            $credential = $null

            if (-not [string]::IsNullOrWhiteSpace($GreenITUser) -and -not [string]::IsNullOrWhiteSpace($GreenITPassword)) {
                $securePassword = ConvertTo-SecureString $GreenITPassword -AsPlainText -Force

                $credentialHost = $HostName

                if ([string]::IsNullOrWhiteSpace($credentialHost)) {
                    $credentialHost = $ComputerName
                }

                # Tar bort .local eller domändel, t.ex. GronIT-PC1.local -> GronIT-PC1
                $credentialHost = ($credentialHost -split "\.")[0]

                $credentialName = "$credentialHost\$GreenITUser"

                $credential = New-Object System.Management.Automation.PSCredential ($credentialName, $securePassword)

                $cimSession = New-CimSession -ComputerName $ComputerName -Credential $credential -ErrorAction Stop
            }
            else {
                $cimSession = New-CimSession -ComputerName $ComputerName -ErrorAction Stop
            }

            $os = Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $cimSession -ErrorAction Stop
        }

        $lastBoot = $os.LastBootUpTime
        $uptimeHours = [math]::Round(((Get-Date) - $lastBoot).TotalHours, 1)

        if ($uptimeHours -ge $InactiveAfterHours) {
            $status = "Inaktiv"
        }
        else {
            $status = "Aktiv"
        }

        return [pscustomobject]@{
            ComputerName   = $ComputerName
            HostName       = $HostName
            Online         = $true
            LastBootUpTime = $lastBoot
            UptimeHours    = $uptimeHours
            Status         = $status
        }
    }
    catch {
        Write-Warning "Kunde inte hämta CIM från $ComputerName. Fel: $($_.Exception.Message)"

        return [pscustomobject]@{
            ComputerName   = $ComputerName
            HostName       = $HostName
            Online         = $true
            LastBootUpTime = $null
            UptimeHours    = $null
            Status         = "Online-NoCIM"
        }
    }
    finally {
        if ($null -ne $cimSession) {
            Remove-CimSession -CimSession $cimSession
        }
    }
}

# User story #9
# Schemalägger avstängning för en maskin endast om den är markerad som Inaktiv.
# Som standard körs funktionen i demo-läge och loggar bara vad som skulle ha hänt.
# För att aktivera riktig shutdown används parametern -RealShutdown.
function New-GreenITShutdownSchedule {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$MachineInfo,

        [int]$DelayMinutes = 1,

        [string]$LogPath = ".\logs\greenit-shutdown.log",

        [switch]$RealShutdown
    )

    process {
        $logDirectory = Split-Path -Path $LogPath -Parent

        if (-not [string]::IsNullOrWhiteSpace($logDirectory) -and -not (Test-Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory | Out-Null
        }

        if ($MachineInfo.Status -ne "Inaktiv") {
            $message = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Shutdown skipped for $($MachineInfo.ComputerName). Status: $($MachineInfo.Status)"
            Add-Content -Path $LogPath -Value $message -Encoding UTF8

            Write-Host "Shutdown skipped for $($MachineInfo.ComputerName). Status: $($MachineInfo.Status)"
            return
        }

        if ($RealShutdown) {
            $message = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - REAL: Shutdown scheduled for $($MachineInfo.ComputerName) in $DelayMinutes minutes."
            Add-Content -Path $LogPath -Value $message -Encoding UTF8

            $seconds = $DelayMinutes * 60
            $target = "\\$($MachineInfo.ComputerName)"

            shutdown.exe /m $target /s /t $seconds /c "Green IT scheduled shutdown"

            if ($LASTEXITCODE -eq 0) {
                $message = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - SUCCESS: Shutdown command accepted for $($MachineInfo.ComputerName)."
                Add-Content -Path $LogPath -Value $message -Encoding UTF8
                Write-Host "Shutdown scheduled for $($MachineInfo.ComputerName) in $DelayMinutes minutes."
            }
            else {
                $message = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - FAILED: Shutdown failed for $($MachineInfo.ComputerName). Exit code: $LASTEXITCODE"
                Add-Content -Path $LogPath -Value $message -Encoding UTF8
                Write-Warning "Shutdown failed for $($MachineInfo.ComputerName). Exit code: $LASTEXITCODE"
            }
        }
        else {
            $message = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - DEMO: Shutdown would have been scheduled for $($MachineInfo.ComputerName) in $DelayMinutes minutes."
            Add-Content -Path $LogPath -Value $message -Encoding UTF8

            Write-Host "DEMO: Shutdown would have been scheduled for $($MachineInfo.ComputerName) in $DelayMinutes minutes."
        }
    }
}