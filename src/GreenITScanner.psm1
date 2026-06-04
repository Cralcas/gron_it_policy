# User story #16
# Testar om en angiven maskin eller IP-adress är online via en ping.
# Returnerar True om maskinen svarar inom timeout, annars False.
function Test-GreenITConnection {
  param(
    # Datornamn eller IP-adress som ska testas.
    [Parameter(Mandatory)]
    [string]$ComputerName,

    # Max tid att vänta på svar, standard 1 sekund.
    [int]$TimeoutMilliseconds = 1000
  )

  $ping = $null

  try {
    # Skapar ping-objekt och skickar ping.
    $ping = New-Object System.Net.NetworkInformation.Ping
    $reply = $ping.Send($ComputerName, $TimeoutMilliseconds)

    # Returnerar True om ping lyckas.
    return $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success
  }
  catch {
    # Returnerar False vid fel eller uteblivet svar.
    return $false
  }
  finally {
    # Rensar ping-objektet om det skapades.
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
    # Datornamn eller IP-adress som ska slås upp.
    [Parameter(Mandatory)]
    [string]$ComputerName
  )

  try {
    # Försöker hämta DNS-information för angivet namn/IP.
    return ([System.Net.Dns]::GetHostEntry($ComputerName)).HostName
  }
  catch {
    # Returnerar null om hostname inte kan hämtas.
    return $null
  }
}

# User story #20
# Startar en nätverksskanning för en eller flera maskiner/IP-adresser.
# Använder funktionerna för ping och hostname så att koden blir mer strukturerad och modulär.
function Start-GreenITScan {
  param(
    # En eller flera maskiner/IP-adresser som ska skannas.
    [Parameter(Mandatory)]
    [string[]]$ComputerName
  )
  # Går igenom varje angiven maskin/IP-adress.
  foreach ($computer in $ComputerName) {
    # Kontrollerar om maskinen svarar på ping.
    $online = Test-GreenITConnection -ComputerName $computer
    # Hostname sätts till null från början.
    $hostName = $null

     # Hämtar hostname endast om maskinen är online.
    if ($online) {
      $hostName = Resolve-GreenITHostName -ComputerName $computer
    }

    # Returnerar resultatet för aktuell maskin. Om maskinen inte svarar på ping kommer Online att vara False och HostName att vara null.
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
    # Datornamn eller IP-adress som ska kontrolleras.
    [Parameter(Mandatory)]
    [string]$ComputerName,

    # Hostname kan skickas in om det redan är känt.
    [string]$HostName,

    # Användarnamn för fjärranslutning via CIM.
    [string]$GreenITUser,

    # Lösenord för fjärranslutning via CIM.
    [string]$GreenITPassword,

    # Antal timmar innan en maskin räknas som inaktiv.
    [int]$InactiveAfterHours = 10
  )

  # Först testar vi om maskinen är online via ping.
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

  # Om hostname inte skickades in försöker vi lösa det.
  if ([string]::IsNullOrWhiteSpace($HostName)) {
    $HostName = Resolve-GreenITHostName -ComputerName $ComputerName
  }

  # Nu försöker vi hämta CIM-information för att få uptime och senaste uppstartstid.
  # Om det misslyckas (t.ex. på grund av brandvägg eller behörighetsproblem) räknas maskinen ändå som online, men med status "Online-NoCIM".
  $cimSession = $null

  try {
    # Kontrollerar om målet är den lokala datorn.
    $isLocalMachine = (
      $ComputerName -eq "localhost" -or
      $ComputerName -eq "127.0.0.1" -or
      $ComputerName -eq $env:COMPUTERNAME -or
      $HostName -like "$env:COMPUTERNAME*"
    )

    if ($isLocalMachine) {
      # Hämtar OS-information direkt om det är den lokala datorn.
      $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    }
    else {
      # Förbereder credentials om användare och lösenord finns.
      $credential = $null

      if (-not [string]::IsNullOrWhiteSpace($GreenITUser) -and -not [string]::IsNullOrWhiteSpace($GreenITPassword)) {
        # Gör om lösenordet till SecureString.
        $securePassword = ConvertTo-SecureString $GreenITPassword -AsPlainText -Force

        # Använder hostname om det finns, annars IP/datornamn.
        $credentialHost = $HostName

        if ([string]::IsNullOrWhiteSpace($credentialHost)) {
          $credentialHost = $ComputerName
        }

        # Tar bort .local eller domändel, t.ex. GronIT-PC1.local -> GronIT-PC1
        $credentialHost = ($credentialHost -split "\.")[0]

        # Bygger användarnamn i formatet DATOR\användare.
        $credentialName = "$credentialHost\$GreenITUser"

        # Skapar credential-objekt för CIM-anslutningen.
        $credential = New-Object System.Management.Automation.PSCredential ($credentialName, $securePassword)

         # Skapar CIM-session med credentials.
        $cimSession = New-CimSession -ComputerName $ComputerName -Credential $credential -ErrorAction Stop
      }
      else {
         # Skapar CIM-session utan extra credentials.
        $cimSession = New-CimSession -ComputerName $ComputerName -ErrorAction Stop
      }
      # Hämtar OS-information via CIM-sessionen.
      $os = Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $cimSession -ErrorAction Stop
    }
    # Hämtar senaste uppstartstid.
    $lastBoot = $os.LastBootUpTime
    # Räknar ut hur många timmar maskinen varit igång.
    $uptimeHours = [math]::Round(((Get-Date) - $lastBoot).TotalHours, 1)

    # Sätter status beroende på uptime. 10h räknas som inaktiv, men detta kan justeras via parametern $InactiveAfterHours.
    if ($uptimeHours -ge $InactiveAfterHours) {
      $status = "Inaktiv"
    }
    else {
      $status = "Aktiv"
    }
    # Returnerar maskininformation med beräknad status.
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
    # Om ping fungerar men CIM misslyckas markeras maskinen som Online-NoCIM.
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
    # Stänger CIM-sessionen om den skapades.
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