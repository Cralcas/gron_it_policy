# UTF-8-stöd för att svenska tecken ska visas korrekt i terminal och loggar
$OutputEncoding = [System.Text.Encoding]::UTF8

# Sätter även konsolens encoding till UTF-8 om scriptet körs i vanlig PowerShell-konsol
# Detta fungerar inte alltid i PowerShell ISE, därför kontrolleras ConsoleHost först
if ($Host.Name -eq "ConsoleHost") {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

# Importerar Green IT-modulerna för inventering, Discord-notiser och shutdown-kontroll
Import-Module "$PSScriptRoot\src\GreenITScanner.psm1" -Force
Import-Module "$PSScriptRoot\src\GreenITDiscord.psm1" -Force
Import-Module "$PSScriptRoot\src\GreenITShutdown.psm1" -Force

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

# Enkel nätverksinventering med progressbar
# Get-GreenITMachineInfo kontrollerar om maskinen är online,
# försöker hämta hostname och hämtar CIM/WMI-information om det går.
# För maskiner som är online kontrolleras även vanliga öppna portar.
$total = $targets.Count
$current = 0

$results = foreach ($target in $targets) {
    $current++

    Write-Progress -Activity "Skannar nätverk..." `
                   -Status "Testar $target ($current av $total)" `
                   -PercentComplete (($current / $total) * 100)

    $machineInfo = Get-GreenITMachineInfo `
        -ComputerName $target `
        -GreenITUser $GreenITUser `
        -GreenITPassword $GreenITPassword

    if ($machineInfo.Online -eq $true) {
        # Hämta öppna portar endast för maskiner som är online
        $openPorts = Get-OpenPorts -ComputerName $machineInfo.ComputerName
    }
    else {
        $openPorts = ""
    }

    # Lägg till OpenPorts i objektet
    $machineInfo | Add-Member -MemberType NoteProperty -Name "OpenPorts" -Value $openPorts -Force

    $machineInfo
}

Write-Progress -Activity "Skannar nätverk..." -Completed

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

# Kör shutdown-kontroll i demo-läge
# Funktionen avgör själv om maskinen är Inaktiv eller ska hoppas över
# Utan -RealShutdown stängs inget av, det loggas bara vad som skulle ha hänt
$ShutdownLogFile = Join-Path $LogDirectory "greenit-shutdown.log"

$results |
    New-GreenITShutdownSchedule -DelayMinutes 30 -LogPath $ShutdownLogFile

# Räknar antal online, inaktiva och offline maskiner för terminalsammanfattningen
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