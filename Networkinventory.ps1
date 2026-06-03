# UTF-8-st�d f�r att svenska tecken ska visas korrekt i terminal och loggar
$OutputEncoding = [System.Text.Encoding]::UTF8

# S�tter �ven konsolens encoding till UTF-8 om scriptet k�rs i vanlig PowerShell-konsol
# Detta fungerar inte alltid i PowerShell ISE, d�rf�r kontrolleras ConsoleHost f�rst
if ($Host.Name -eq "ConsoleHost") {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

# Importerar Green IT Scanner-modulen med alla funktioner
Import-Module "$PSScriptRoot\src\GreenITScanner.psm1" -Force

# Ange subnet som ska skannas
$Subnet = "192.168.200"

# Skapar en lista med IP-adresser fr�n 192.168.200.1 till 192.168.200.23
$targets = 1..23 | ForEach-Object {
    "$Subnet.$_"
}

# S�kv�g till .env-filen d�r credentials och webhook lagras
$EnvPath = Join-Path $PSScriptRoot ".env"

# L�ser in variabler fr�n .env-filen om den finns, och s�tter dem som processmilj�variabler
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

# H�mtar anv�ndarnamn och l�senord fr�n milj�variablerna
# Dessa anv�nds av Get-GreenITMachineInfo f�r att h�mta mer information via CIM/WMI
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

# V�lj ut de maskiner som svarade p� ping
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

# L�gg till offline-maskiner s� de ocks� syns i CSV-filen
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

# Sl�r ihop online-inventering och offline-resultat
$results = @($inventoryResults) + @($offlineResults)

# Skapar logs-mapp om den saknas
$LogDirectory = Join-Path $PSScriptRoot "logs"

if (-not (Test-Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory | Out-Null
}

# Skapar filnamn f�r CSV-export
$filename = "Inventory_$(Get-Date -Format 'yyyy-MM-dd_HH-mm').csv"

# Skapar full s�kv�g till CSV-filen i logs-mappen
$LogFile = Join-Path $LogDirectory $filename

# Sparar resultatet till CSV
$results | Export-Csv -Path $LogFile -NoTypeInformation -Encoding UTF8

# Skickar resultatet till Discord
Send-GreenITDiscordNotification `
    -Title "Green IT-skanning klar" `
    -LogPath $LogFile

# K�r shutdown-funktionen i demo-l�ge f�r inaktiva maskiner
# Utan -RealShutdown st�ngs inget av, det loggas bara vad som skulle ha h�nt
$results |
    Where-Object { $_.Status -eq "Inaktiv" } |
    New-GreenITShutdownSchedule -DelayMinutes 30

# R�knar antal online, inaktiva och offline maskiner
$onlineCount = @($results | Where-Object { $_.Online -eq $true }).Count
$inactiveCount = @($results | Where-Object { $_.Status -eq "Inaktiv" }).Count
$offlineCount = @($results | Where-Object { $_.Status -eq "Offline" }).Count

# Skriver ut en kort sammanfattning till anv�ndaren
Write-Host "`nInventering klar!" -ForegroundColor Green
Write-Host "Skannade $($results.Count) enheter" -ForegroundColor Green
Write-Host "Hittade $onlineCount online enheter" -ForegroundColor Green
Write-Host "Hittade $inactiveCount inaktiva enheter" -ForegroundColor Yellow
Write-Host "Hittade $offlineCount offline enheter" -ForegroundColor DarkGray
Write-Host "Resultaten sparades som: $LogFile" -ForegroundColor Green
Write-Host "Shutdown-kontroll k�rdes i demo-l�ge." -ForegroundColor Cyan