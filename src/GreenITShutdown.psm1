# User story #9
# Schemalägger avstängning för en maskin endast om den är markerad som Inaktiv.
# Som standard körs funktionen i demo-läge och loggar bara vad som skulle ha hänt.
# För att aktivera riktig shutdown används parametern -RealShutdown.
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