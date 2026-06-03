# User story #16
# Testar om en angiven maskin eller IP-adress är online via en ping.
# Returnerar True om maskinen svarar inom timeout, annars False.
function Test-GreenITConnection {
  param(
    [Parameter(Mandatory)]
    [string]$ComputerName,

    [int]$TimeoutMilliseconds = 1000
  )

  $ping = $null

  try {
    $ping = New-Object System.Net.NetworkInformation.Ping
    $reply = $ping.Send($ComputerName, $TimeoutMilliseconds)

    return $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success
  }
  catch {
    return $false
  }
  finally {
    if ($null -ne $ping) {
      $ping.Dispose()
    }
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

  if ([string]::IsNullOrWhiteSpace($HostName)) {
    $HostName = Resolve-GreenITHostName -ComputerName $ComputerName
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