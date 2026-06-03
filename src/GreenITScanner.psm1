# User story #16
# Testar om en angiven maskin eller IP-adress �r online via ping.
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
# F�rs�ker h�mta hostname f�r en angiven maskin eller IP-adress.
# Returnerar hostname om det g�r, annars null.
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
# Startar en n�tverksskanning f�r en eller flera maskiner/IP-adresser.
# Anv�nder funktionerna f�r ping och hostname s� att koden blir mer strukturerad och modul�r.
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
# H�mtar grundl�ggande information om en maskin.
# Anv�nder ping, hostname och CIM f�r att bed�ma om maskinen �r aktiv eller inaktiv.
# Om maskinen har varit ig�ng mer �n angivet antal timmar f�r den status Inaktiv.
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

                # Tar bort .local eller dom�ndel, t.ex. GronIT-PC1.local -> GronIT-PC1
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
        Write-Warning "Kunde inte h�mta CIM fr�n $ComputerName. Fel: $($_.Exception.Message)"

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
# Schemal�gger avst�ngning f�r en maskin endast om den �r markerad som Inaktiv.
# Som standard k�rs funktionen i demo-l�ge och loggar bara vad som skulle ha h�nt.
# F�r att aktivera riktig shutdown anv�nds parametern -RealShutdown.
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
# Funktionen l�ser CSV-loggen som skapats efter skanningen.
# Online-enheter visas med information, medan offline-enheter bara r�knas.
function Send-GreenITDiscordNotification {
    param(
        [string]$Title = "Green IT-skanning klar",
        [string]$Message = "",
        [string]$LogPath,
        [int]$MaxOnlineDevices = 10,
        [string]$WebhookUrl = $env:DISCORD_WEBHOOK_URL
    )
    # Om webhook saknas ska scriptet inte krascha.
    # Det ska bara hoppa �ver Discord-notisen och skriva en varning.
    if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
        Write-Warning "DISCORD_WEBHOOK_URL saknas. Skickar ingen Discord-notis."
        return
    }
    # Kontrollerar att CSV-loggen faktiskt finns innan funktionen f�rs�ker l�sa den
    if (-not $LogPath -or -not (Test-Path -LiteralPath $LogPath)) {
        Write-Warning "Loggfil saknas. Skickar ingen Discord-notis."
        return
    }
    # L�ser in CSV-filen med inventeringsresultatet
    try {
        $rows = @(Import-Csv -LiteralPath $LogPath)
    }
    catch {
        Write-Warning ("Kunde inte l�sa CSV-loggen: {0}" -f $_.Exception.Message)
        return
    }
    # Delar upp resultatet efter status s� att online-enheter kan listas medan offline-enheter bara r�knas
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

    # Visar bara detaljer f�r online-enheter
    $content += "**Online:**$nl"

    if ($onlineDevices.Count -eq 0) {
        $content += "Inga online-enheter hittades.$nl"
    }
    else {
        foreach ($device in ($onlineDevices | Select-Object -First $MaxOnlineDevices)) {
            $ip = $device.ComputerName

            # Om hostname saknas visas ett tydligt standardv�rde ist�llet f�r att l�mna det tomt
            if ([string]::IsNullOrWhiteSpace($device.HostName)) {
                $hostName = "Ok�nt hostnamn"
            }
            else {
                $hostName = $device.HostName
            }
            # Om status saknas r�knas maskinen �nd� som online
            if ([string]::IsNullOrWhiteSpace($device.Status)) {
                $status = "Online"
            }
            else {
                $status = $device.Status
            }
            # Uptime kan saknas om CIM/WMI inte gick att l�sa
            if ([string]::IsNullOrWhiteSpace($device.UptimeHours)) {
                $uptime = "Ok�nd uptime"
            }
            else {
                $uptime = "$($device.UptimeHours)h"
            }
            # Senaste uppstartstid kan ocks� saknas vid Online-NoCIM
            if ([string]::IsNullOrWhiteSpace($device.LastBootUpTime)) {
                $lastBoot = "Ok�nd starttid"
            }
            else {
                $lastBoot = $device.LastBootUpTime
            }
            # En rad per online-enhet med IP, hostname, status, uptime och senaste uppstartstid
            $content += "$ip - $hostName - $status - Uptime: $uptime - Startad: $lastBoot$nl"
        }
        # Om m�nga enheter �r online visas bara ett begr�nsat antal
        if ($onlineDevices.Count -gt $MaxOnlineDevices) {
            $remaining = $onlineDevices.Count - $MaxOnlineDevices
            $content += "...och $remaining fler online-enheter.$nl"
        }
    }
    # Discord har gr�ns p� meddelandel�ngd.
    # Kortar d�rf�r ner texten innan den skickas.
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