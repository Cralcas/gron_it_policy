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
# Använder ping och hostname som grund för att senare bedöma om maskinen är aktiv eller inaktiv.
# Om maskinen har varit igång mer än 8 timmar så får den status inaktiv eller får den aktiv
function Get-GreenITMachineInfo {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [int]$InactiveAfterHours = 8
    )

    $online = Test-GreenITConnection -ComputerName $ComputerName
    $hostName = Resolve-GreenITHostName -ComputerName $ComputerName

    if (-not $online) {
        return [pscustomobject]@{
            ComputerName   = $ComputerName
            HostName       = $hostName
            Online         = $false
            LastBootUpTime = $null
            UptimeHours    = $null
            Status         = "Offline"
        }
    }

    try {
        if (
            $ComputerName -eq "localhost" -or
            $ComputerName -eq "127.0.0.1" -or
            $ComputerName -eq $env:COMPUTERNAME -or
            $hostName -like "$env:COMPUTERNAME*"
        ) {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        }
        else {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $ComputerName -ErrorAction Stop
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
            HostName       = $hostName
            Online         = $true
            LastBootUpTime = $lastBoot
            UptimeHours    = $uptimeHours
            Status         = $status
        }
    }
    catch {
    Write-Warning "Kunde inte h�mta CIM fr�n $ComputerName. Fel: $($_.Exception.Message)"

    return [pscustomobject]@{
        ComputerName   = $ComputerName
        HostName       = $hostName
        Online         = $true
        LastBootUpTime = $null
        UptimeHours    = $null
        Status         = "Unknown"
        }
    }
}

# User story #9
# Schemalägger avstängning för en maskin endast om den är markerad som Inaktiv.
# Som standard körs funktionen i demo-läge och loggar bara vad som skulle ha hänt.
# För att aktivera den riktiga så sätter man "$RealShutdown" till = $true
function New-GreenITShutdownSchedule {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$MachineInfo,

        [int]$DelayMinutes = 30,

        [string]$LogPath = ".\greenit-shutdown.log",

        [switch]$RealShutdown #= $true
    )

    process {
        if ($MachineInfo.Status -ne "Inaktiv") {
            $message = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Shutdown skipped for $($MachineInfo.ComputerName). Status: $($MachineInfo.Status)"
            Add-Content -Path $LogPath -Value $message

            Write-Host "Shutdown skipped. The machine is not inactive."
            return
        }

        $message = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Shutdown scheduled for $($MachineInfo.ComputerName) in $DelayMinutes minutes."
        Add-Content -Path $LogPath -Value $message

        if ($RealShutdown) {
            $seconds = $DelayMinutes * 60
            shutdown.exe /s /t $seconds
            Write-Host "Shutdown scheduled in $DelayMinutes minutes."
        }
        else {
            Write-Host "DEMO: Shutdown would have been scheduled for $($MachineInfo.ComputerName) in $DelayMinutes minutes."
        }
    }
}