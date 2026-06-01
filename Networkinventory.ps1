# Skanna alla ip-adresser
1..254 | ForEach-Object {

    $ip = "$Subnet.$_"

    if (Test-Connection -ComputerName $ip -Count 1 -Quiet) {

        $result = [PSCustomObject]@{
            IP       = $ip
            Hostname = "N/A"
            Status   = "Online"
            ScanTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

        $results += $result
    }
}

# Spara till CSV
$filename = "Inventory_$(Get-Date -Format 'yyyy-MM-dd_HH-mm').csv"
$results | Export-Csv -Path $filename -NoTypeInformation -Encoding UTF8