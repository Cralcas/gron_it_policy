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