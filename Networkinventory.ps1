# Importerar Green IT Scanner-modulen med alla funktioner
Import-Module "$PSScriptRoot\src\GreenITScanner.psm1" -Force

# Ange subnet som ska skannas
$Subnet = "192.168.x"

# Skapar en lista med IP-adresser från 192.168.0.1 till 192.168.0.254
$targets = 1..254 | ForEach-Object {
    "$Subnet.$_"
}

# Enkel nätverksskanning
# Start-GreenITScan kontrollerar om maskinen är online och försöker hämta hostname
$scanResults = Start-GreenITScan -ComputerName $targets

# Välj ut de maskiner som svarade på ping
$onlineTargets = $scanResults |
    Where-Object { $_.Online -eq $true } |
    Select-Object -ExpandProperty ComputerName

# Hämta mer detaljerad inventarieinformation för online-maskiner
# Get-GreenITMachineInfo hämtar till exempel senaste uppstartstid, uptime och status
$inventoryResults = foreach ($target in $onlineTargets) {
    Get-GreenITMachineInfo -ComputerName $target
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
        }
    }

# Slår ihop online-inventering och offline-resultat
$results = $inventoryResults + $offlineResults

# Skapar filnamn för CSV-export
$filename = "Inventory_$(Get-Date -Format 'yyyy-MM-dd_HH-mm').csv"

# Sparar resultatet till CSV
$results | Export-Csv -Path $filename -NoTypeInformation -Encoding UTF8

# Kör shutdown-funktionen i demo-läge för inaktiva maskiner
# Utan -RealShutdown stängs inget av, det loggas bara vad som skulle ha hänt
$results |
    Where-Object { $_.Status -eq "Inaktiv" } |
    New-GreenITShutdownSchedule -DelayMinutes 30

# Räknar antal online, inaktiva och offline maskiner
$onlineCount = ($results | Where-Object { $_.Online -eq $true }).Count
$inactiveCount = ($results | Where-Object { $_.Status -eq "Inaktiv" }).Count
$offlineCount = ($results | Where-Object { $_.Status -eq "Offline" }).Count

# Skriver ut en kort sammanfattning till användaren
Write-Host "`nInventering klar!" -ForegroundColor Green
Write-Host "Skannade $($results.Count) enheter" -ForegroundColor Green
Write-Host "Hittade $onlineCount online enheter" -ForegroundColor Green
Write-Host "Hittade $inactiveCount inaktiva enheter" -ForegroundColor Yellow
Write-Host "Hittade $offlineCount offline enheter" -ForegroundColor DarkGray
Write-Host "Resultaten sparades som: $filename" -ForegroundColor Green
Write-Host "Shutdown-kontroll kördes i demo-läge." -ForegroundColor Cyan