# UTF-8-stöd för att svenska tecken ska visas korrekt i terminal och loggar
$OutputEncoding = [System.Text.Encoding]::UTF8

# Sätter även konsolens encoding till UTF-8 om scriptet körs i vanlig PowerShell-konsol
# Detta fungerar inte alltid i PowerShell ISE, därför kontrolleras ConsoleHost först
if ($Host.Name -eq "ConsoleHost") {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

# Importerar Green IT Scanner-modulen med alla funktioner
Import-Module "$PSScriptRoot\src\GreenITScanner.psm1" -Force

# Ange subnet som ska skannas
$Subnet = "192.168.200"

# Skapar en lista med IP-adresser från 192.168.200.1 till 192.168.200.23
$targets = 1..23 | ForEach-Object {
    "$Subnet.$_"
}

# Sökväg till .env-filen där credentials och webhook lagras
$EnvPath = Join-Path $PSScriptRoot ".env"

# Läser in variabler från .env-filen om den finns, och sätter dem som processmiljövariabler
if (Test-Path $EnvPath) {
    Get-Content $EnvPath | ForEach-Object {
        if ($_ -match "^\s*#" -or $_ -match "^\s*$") {
            return
        }

        $name, $value = $_ -split "=", 2
        [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), "Process")
    }
}
else {
    Write-Warning ".env saknas. CIM-inventering med credentials kan misslyckas."
}

# Hämtar användarnamn och lösenord från miljövariablerna
# Dessa används av Get-GreenITMachineInfo för att hämta mer information via CIM/WMI
$GreenITUser = $env:GREENIT_USER
$GreenITPassword = $env:GREENIT_PASSWORD

if ([string]::IsNullOrWhiteSpace($GreenITUser) -or [string]::IsNullOrWhiteSpace($GreenITPassword)) {
    Write-Warning "GREENIT_USER eller GREENIT_PASSWORD saknas i .env."
}

# Enkel nätverksskanning med progressbar
# Start-GreenITScan kontrollerar om maskinen är online och försöker hämta hostname
$scanResults = @()
$total = $targets.Count
$current = 0

foreach ($target in $targets) {
    $current++

    Write-Progress -Activity "Skannar nätverk..." `
                   -Status "Testar $target ($current av $total)" `
                   -PercentComplete (($current / $total) * 100)

    $scanResults += Start-GreenITScan -ComputerName $target
}

Write-Progress -Activity "Skannar nätverk..." -Completed

# Välj ut de maskiner som svarade på ping
$onlineTargets = $scanResults |
    Where-Object { $_.Online -eq $true }

# Hämta mer detaljerad inventarieinformation + portskanning för online-maskiner
$inventoryResults = foreach ($target in $onlineTargets) {
    $machineInfo = Get-GreenITMachineInfo `
        -ComputerName $target.ComputerName `
        -HostName $target.HostName `
        -GreenITUser $GreenITUser `
        -GreenITPassword $GreenITPassword

    # Hämta öppna portar
    $openPorts = Get-OpenPorts -ComputerName $target.ComputerName

    # Lägg till OpenPorts i objektet
    $machineInfo | Add-Member -MemberType NoteProperty -Name "OpenPorts" -Value $openPorts -Force

    $machineInfo
}

# Lägg till offline-maskiner så de också syns i CSV-filen
$offlineResults = $scanResults |
    Where-Object { $_.Online -eq $false } |
    ForEach-Object {
        [PSCustomObject]@{
            ComputerName   = $_.ComputerName
            HostName       = $_.HostName
            Online         = $false
            LastBootUpTime = $null
            UptimeHours    = $null
            Status         = "Offline"
            OpenPorts      = ""
        }
    }

# Slår ihop online-inventering och offline-resultat
$results = @($inventoryResults) + @($offlineResults)

# Skapar logs-mapp om den saknas
$LogDirectory = Join-Path $PSScriptRoot "logs"

if (-not (Test-Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory | Out-Null
}

# Skapar filnamn för CSV-export
$filename = "Inventory_$(Get-Date -Format 'yyyy-MM-dd_HH-mm').csv"

# Skapar full sökväg till CSV-filen i logs-mappen
$LogFile = Join-Path $LogDirectory $filename

# Sparar resultatet till CSV
$results | Export-Csv -Path $LogFile -NoTypeInformation -Encoding UTF8

# Skickar resultatet till Discord
Send-GreenITDiscordNotification `
    -Title "Green IT-skanning klar" `
    -LogPath $LogFile

# Kör shutdown-funktionen i demo-läge för inaktiva maskiner
# Utan -RealShutdown stängs inget av, det loggas bara vad som skulle ha hänt
$results |
    Where-Object { $_.Status -eq "Inaktiv" } |
    New-GreenITShutdownSchedule -DelayMinutes 30

# Räknar antal online, inaktiva och offline maskiner
$onlineCount = @($results | Where-Object { $_.Online -eq $true }).Count
$inactiveCount = @($results | Where-Object { $_.Status -eq "Inaktiv" }).Count
$offlineCount = @($results | Where-Object { $_.Status -eq "Offline" }).Count

# Skriver ut en kort sammanfattning till användaren
Write-Host "`nInventering klar!" -ForegroundColor Green
Write-Host "Skannade $($results.Count) enheter" -ForegroundColor Green
Write-Host "Hittade $onlineCount online enheter" -ForegroundColor Green
Write-Host "Hittade $inactiveCount inaktiva enheter" -ForegroundColor Yellow
Write-Host "Hittade $offlineCount offline enheter" -ForegroundColor DarkGray
Write-Host "Resultaten sparades som: $LogFile" -ForegroundColor Green
Write-Host "Shutdown-kontroll kördes i demo-läge." -ForegroundColor Cyan

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

# User story #24
# Skickar en kort sammanfattning av inventeringsresultatet till Discord via webhook.
# Funktionen läser CSV-loggen som skapats efter skanningen.
# Online-enheter visas med information, medan offline-enheter bara räknas.
function Send-GreenITDiscordNotification {
    param(
        [string]$Title = "Green IT-skanning klar",
        [string]$Message = "",
        [string]$LogPath,
        [int]$MaxOnlineDevices = 10,
        [string]$WebhookUrl = $env:DISCORD_WEBHOOK_URL
    )
    # Om webhook saknas ska scriptet inte krascha.
    # Det ska bara hoppa över Discord-notisen och skriva en varning.
    if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
        Write-Warning "DISCORD_WEBHOOK_URL saknas. Skickar ingen Discord-notis."
        return
    }
    # Kontrollerar att CSV-loggen faktiskt finns innan funktionen försöker läsa den
    if (-not $LogPath -or -not (Test-Path -LiteralPath $LogPath)) {
        Write-Warning "Loggfil saknas. Skickar ingen Discord-notis."
        return
    }
    # Läser in CSV-filen med inventeringsresultatet
    try {
        $rows = @(Import-Csv -LiteralPath $LogPath)
    }
    catch {
        Write-Warning ("Kunde inte läsa CSV-loggen: {0}" -f $_.Exception.Message)
        return
    }
    # Delar upp resultatet efter status så att online-enheter kan listas medan offline-enheter bara räknas
    $onlineDevices = @(
        $rows | Where-Object {
            $_.Online -eq $true -or $_.Online -eq "True"
        }
    )

    $offlineDevices = @(
        $rows | Where-Object {
            $_.Online -eq $false -or $_.Online -eq "False" -or $_.Status -eq "Offline"
        }
    )

    $inactiveDevices = @(
        $rows | Where-Object {
            $_.Status -eq "Inaktiv"
        }
    )

    $nl = [Environment]::NewLine

    # Bygger Discord-meddelandet
    $content = "**$Title**$nl"

    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $content += "$Message$nl"
    }

    # Kort driftlik sammanfattning av resultatet, t.ex. "Skannade 50 enheter. 30 svarade, 15 var offline, 5 markerades som inaktiva."
    $content += "Skannade $($rows.Count) enheter. "
    $content += "$($onlineDevices.Count) svarade, "
    $content += "$($offlineDevices.Count) var offline. "
    $content += "$($inactiveDevices.Count) markerades som inaktiva.$nl$nl"

    # Visar bara detaljer för online-enheter
    $content += "**Online:**$nl"

    if ($onlineDevices.Count -eq 0) {
        $content += "Inga online-enheter hittades.$nl"
    }
    else {
        foreach ($device in ($onlineDevices | Select-Object -First $MaxOnlineDevices)) {
            $ip = $device.ComputerName

            # Om hostname saknas visas ett tydligt standardvärde istället för att lämna det tomt
            if ([string]::IsNullOrWhiteSpace($device.HostName)) {
                $hostName = "Okänt hostnamn"
            }
            else {
                $hostName = $device.HostName
            }
            # Om status saknas räknas maskinen ändå som online
            if ([string]::IsNullOrWhiteSpace($device.Status)) {
                $status = "Online"
            }
            else {
                $status = $device.Status
            }
            # Uptime kan saknas om CIM/WMI inte gick att läsa
            if ([string]::IsNullOrWhiteSpace($device.UptimeHours)) {
                $uptime = "Okänd uptime"
            }
            else {
                $uptime = "$($device.UptimeHours)h"
            }
            # Senaste uppstartstid kan också saknas vid Online-NoCIM
            if ([string]::IsNullOrWhiteSpace($device.LastBootUpTime)) {
                $lastBoot = "Okänd starttid"
            }
            else {
                $lastBoot = $device.LastBootUpTime
            }
            # En rad per online-enhet med IP, hostname, status, uptime och senaste uppstartstid
            $content += "$ip - $hostName - $status - Uptime: $uptime - Startad: $lastBoot$nl"
        }
        # Om många enheter är online visas bara ett begränsat antal
        if ($onlineDevices.Count -gt $MaxOnlineDevices) {
            $remaining = $onlineDevices.Count - $MaxOnlineDevices
            $content += "...och $remaining fler online-enheter.$nl"
        }
    }
    # Discord har gräns på meddelandelängd.
    # Kortar därför ner texten innan den skickas.
    if ($content.Length -gt 1900) {
        $content = $content.Substring(0, 1900) + "$nl...kortad output"
    }

    # Skapar JSON-payload till Discord
    $payload = @{
        username = "Logg-Lasse"
        content  = $content
    } | ConvertTo-Json -Depth 5
    # Skickar meddelandet till Discord via webhook
    try {
        Invoke-RestMethod `
            -Uri $WebhookUrl `
            -Method Post `
            -ContentType "application/json; charset=utf-8" `
            -Body $payload | Out-Null

        Write-Host "Discord-notis skickad." -ForegroundColor Green
    }
    catch {
        Write-Warning ("Kunde inte skicka Discord-notis: {0}" -f $_.Exception.Message)
    }
}

# User story: Portskanning
# Testar vanliga portar på en online-enhet och returnerar en kommaseparerad
# lista med öppna portar (t.ex. "80, 443, 3389").
# Används för att ge mer detaljerad information i CSV-exporten.
function Get-OpenPorts {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    # Vanliga portar att kontrollera
    $portsToCheck = @(22, 80, 443, 3389, 445, 5985, 5986)
    $openPorts = @()

    foreach ($port in $portsToCheck) {
        try {
            $result = Test-NetConnection -ComputerName $ComputerName -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
            if ($result) {
                $openPorts += $port
            }
        }
        catch {
            # Ignorera fel på enskilda portar
        }
    }

    if ($openPorts.Count -gt 0) {
        return ($openPorts -join ", ")
    }
    else {
        return ""
    }
}