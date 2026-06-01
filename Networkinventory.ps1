# Skanna alla ip-adresser
1..254 | ForEach-Object {

    $ip = "$Subnet.$_"

    if (Test-Connection -ComputerName $ip -Count 1 -Quiet) {

        # Försöker hämta hostname med felhantering
        $hostname = try {
            (Resolve-DnsName -Name $ip -ErrorAction Stop).NameHost
        }
        catch {
            "N/A"
        }

        $result = [PSCustomObject]@{
            IP       = $ip
            Hostname = $hostname
            Status   = "Online"
            ScanTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

        $results += $result
    }
}

# Spara till CSV
$filename = "Inventory_$(Get-Date -Format 'yyyy-MM-dd_HH-mm').csv"
$results | Export-Csv -Path $filename -NoTypeInformation -Encoding UTF8

# Feedback till användaren
Write-Host "`nInventering Klar!" -ForegroundColor Green
Write-Host "Hittade $($results.Count) online enheter" -ForegroundColor Green
Write-Host "Resultaten sparades som: $filename" -ForegroundColor Green