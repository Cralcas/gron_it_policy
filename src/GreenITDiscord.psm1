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