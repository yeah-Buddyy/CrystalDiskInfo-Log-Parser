# Run as Admin
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell.exe -Verb RunAs "-NoProfile -NoLogo -ExecutionPolicy Bypass -Command `"cd '$pwd'; & '$PSCommandPath';`"";
    exit;
}

# Define the file path
$filePathDiskInfoIni = "$PSScriptRoot\CrystalDiskInfo9_3_2\DiskInfo.ini"

# Define the file path
$filePathDiskInfoTxt = "$PSScriptRoot\CrystalDiskInfo9_3_2\DiskInfo.txt"

# Define the file path
$filePathDiskInfoExe = "$PSScriptRoot\CrystalDiskInfo9_3_2\DiskInfo64.exe"

# Define the content to be written to the file
$DiskInfoIniContent = @"
[Setting]
DebugMode="0"
AutoRefresh="10"
StartupWaitTime="30"
Temperature="0"
ResidentMinimize="0"
SortDriveLetter="1"
DriveMenu="8"
AMD_RC2="1"
MegaRAID="1"
IntelVROC="1"
JMS56X="0"
JMB39X="0"
JMS586="0"
StartupFixed="1"
Language="English"
[Workaround]
ExecFailed="0"
[USB]
SAT="1"
IODATA="1"
Sunplus="1"
Logitec="1"
Prolific="1"
JMicron="1"
Cypress="1"
ASM1352R="1"
UsbMemory="0"
NVMeJMicron3="0"
NVMeJMicron="1"
NVMeASMedia="1"
NVMeRealtek="1"
"@

# Write the content to the file, overwriting if it exists
Set-Content -Path $filePathDiskInfoIni -Value $DiskInfoIniContent

# Output a message indicating the operation is complete
Write-Host "DiskInfo.ini has been created/overwritten with the specified content." -ForegroundColor Yellow

# We start CrystalDiskInfo with the COPYEXIT parameter. This just collects the SMART information in DiskInfo.txt
Start-Process "$filePathDiskInfoExe" -ArgumentList "/CopyExit" -Wait -WindowStyle Hidden

# Read the content of the file
$content = Get-Content -Path $filePathDiskInfoTxt

# Flags to indicate if we are capturing lines
$captureRawValues = $false
$captureModel = $false

# Lists to store multiple captures
$allRawValuesCapturedLines = @()
$currentRawValuesCapture = @()

$allModelCapturedLines = @()
$currentModelCapture = @()

foreach ($line in $content) {
    # If we find "RawValues(", set the capture flag for RawValues
    if ($line -match "RawValues\(") {
        if ($captureRawValues -eq $true -and $currentRawValuesCapture.Count -gt 0) {
            $allRawValuesCapturedLines += ,@($currentRawValuesCapture)
            $currentRawValuesCapture = @()
        }
        $captureRawValues = $true
    }

    # If capturing RawValues, add the line to the currentRawValuesCapture array
    if ($captureRawValues) {
        $currentRawValuesCapture += $line
        
        # If the line is empty, stop capturing and store the captured lines
        if ($line -eq "") {
            $captureRawValues = $false
            if ($currentRawValuesCapture.Count -gt 0) {
                $allRawValuesCapturedLines += ,@($currentRawValuesCapture)
            }
            $currentRawValuesCapture = @()
        }
    }

    # If we find "Model :", set the capture flag for Model
    if ($line -match "Model :") {
        if ($captureModel -eq $true -and $currentModelCapture.Count -gt 0) {
            $allModelCapturedLines += ,@($currentModelCapture)
            $currentModelCapture = @()
        }
        $captureModel = $true
    }

    # If capturing Model, add the line to the currentModelCapture array
    if ($captureModel) {
        $currentModelCapture += $line

        # If the line is empty, stop capturing and store the captured lines
        if ($line -eq "") {
            $captureModel = $false
            if ($currentModelCapture.Count -gt 0) {
                $allModelCapturedLines += ,@($currentModelCapture)
            }
            $currentModelCapture = @()
        }
    }
}

# Handle the last captures if the file does not end with a blank line
if ($currentRawValuesCapture.Count -gt 0) {
    $allRawValuesCapturedLines += ,@($currentRawValuesCapture)
}

if ($currentModelCapture.Count -gt 0) {
    $allModelCapturedLines += ,@($currentModelCapture)
}

for ($i = 0; $i -lt $allRawValuesCapturedLines.Count; $i++) {
    # Process RawValues
    $DiskInfoRaw = $allRawValuesCapturedLines[$i]

    # Process Model
    $ModelLines = $allModelCapturedLines[$i]
    # $ModelLines | ForEach-Object { Write-Host $_ }

    # Parse Model section into a PSCustomObject
    $modelObject = [PSCustomObject]@{}
    foreach ($line in $ModelLines) {
        if ($line -match " : ") {
            $parts = $line -split " : "
            if ($parts.Count -eq 2) {
                $propertyName = $parts[0] -replace (' ')
                $propertyValue = $parts[1].Trim()
                $modelObject | Add-Member -MemberType NoteProperty -Name $propertyName -Value $propertyValue
            }
        }
    }

    # Output the PSCustomObject
    # $modelObject | Format-List

    # Get the first line
    $firstLine = ($DiskInfoRaw | Select-Object -First 1)

    # Check if the first line contains "Cur", "Wor", and "Thr"
    if ($firstLine -match "Cur" -and $firstLine -match "Wor" -and $firstLine -match "Thr") {
        Write-Host "FOUND HDD OR SSD LOG" -ForegroundColor Yellow
        $diskinfo = $DiskInfoRaw -split "`n" | select -skip 1 | Out-String | ConvertFrom-Csv -Delimiter " " -Header "ID","Cur","Wor","Thr","RawValue","Attribute","Name"

        [int64]$ReadErrorRate = "0x" + ($diskinfo | Where-Object { $_.ID -eq "01"}).RawValue
        [int64]$SpinUpTime = "0x" + ($diskinfo | Where-Object { $_.ID -eq "03"}).RawValue
        [int64]$StartStopCount = "0x" + ($diskinfo | Where-Object { $_.ID -eq "04"}).RawValue
        [int64]$ReallocatedSectorsCount = "0x" + ($diskinfo | Where-Object { $_.ID -eq "05"}).RawValue
        [int64]$SeekErrorRate = "0x" + ($diskinfo | Where-Object { $_.ID -eq "07"}).RawValue
        [int64]$PowerOnHoursValue = "0x" + ($diskinfo | Where-Object { $_.ID -eq "09"}).RawValue
        [int64]$SpinRetryCount = "0x" + ($diskinfo | Where-Object { $_.ID -eq "0A"}).RawValue
        [int64]$RecalibrationRetries = "0x" + ($diskinfo | Where-Object { $_.ID -eq "0B"}).RawValue
        [int64]$PowerCycleCount = "0x" + ($diskinfo | Where-Object { $_.ID -eq "0C"}).RawValue
        [int64]$PowerOffRetractCount = "0x" + ($diskinfo | Where-Object { $_.ID -eq "C0"}).RawValue
        [int64]$LoadUnloadCycleCount = "0x" + ($diskinfo | Where-Object { $_.ID -eq "C1"}).RawValue
        [int64]$Temperature = "0x" + ($diskinfo | Where-Object { $_.ID -eq "C2"}).RawValue
        [int64]$ReallocationEventCount = "0x" + ($diskinfo | Where-Object { $_.ID -eq "C4"}).RawValue
        [int64]$CurrentPendingSectorCount = "0x" + ($diskinfo | Where-Object { $_.ID -eq "C5"}).RawValue
        [int64]$UncorrectableSectorCount = "0x" + ($diskinfo | Where-Object { $_.ID -eq "C6"}).RawValue
        [int64]$UltraDMACRCErrorCount = "0x" + ($diskinfo | Where-Object { $_.ID -eq "C7"}).RawValue
        [int64]$WriteErrorRate = "0x" + ($diskinfo | Where-Object { $_.ID -eq "C8"}).RawValue

        Write-Host "Disk Information" -BackgroundColor Magenta
        Write-Host "Model: $($modelObject.Model)" -BackgroundColor Green
        Write-Host "Firmware: $($modelObject.Firmware)" -BackgroundColor Green
        Write-Host "Serial Number: $($modelObject.SerialNumber)" -BackgroundColor Green
        Write-Host "Disk Size: $($modelObject.DiskSize)" -BackgroundColor Green
        Write-Host "Buffer Size: $($modelObject.BufferSize)" -BackgroundColor Green
        Write-Host "Queue Depth: $($modelObject.QueueDepth)" -BackgroundColor Green
        Write-Host "# of Sectors: $($modelObject.'#ofSectors')" -BackgroundColor Green
        Write-Host "Rotation Rate: $($modelObject.RotationRate)" -BackgroundColor Green
        Write-Host "Interface: $($modelObject.Interface)" -BackgroundColor Green
        Write-Host "Major Version: $($modelObject.MajorVersion)" -BackgroundColor Green
        Write-Host "Minor Version: $($modelObject.MinorVersion)" -BackgroundColor Green
        Write-Host "Transfer Mode: $($modelObject.TransferMode)" -BackgroundColor Green
        Write-Host "PowerOnHours: $($modelObject.PowerOnHours)" -BackgroundColor Green
        Write-Host "PowerOnCount: $($modelObject.PowerOnCount)" -BackgroundColor Green
        Write-Host "Temperature: $($modelObject.Temperature)" -BackgroundColor Green
        if ($modelObject.HealthStatus -match "Good") {
            Write-Host "Health Status: $($modelObject.HealthStatus)" -BackgroundColor Green
        } else {
            Write-Host "Health Status: $($modelObject.HealthStatus)" -BackgroundColor Red
        }
        Write-Host "Features: $($modelObject.Features)" -BackgroundColor Green
        Write-Host "APM Level: $($modelObject.APMLevel)" -BackgroundColor Green
        Write-Host "AAM Level: $($modelObject.AAMLevel)" -BackgroundColor Green
        Write-Host "Drive Letter: $($modelObject.DriveLetter)" -BackgroundColor Green
        Write-Host
        Write-Host "Disk Values" -BackgroundColor Magenta
        if ($null -ne $ReadErrorRate -and $ReadErrorRate -match '^\d+$' -and $ReadErrorRate -eq 0) {
            Write-Host "Read Error Rate: $ReadErrorRate" -BackgroundColor Green
        } else {
            Write-Host "Read Error Rate: $ReadErrorRate" -BackgroundColor Cyan
        }
        Write-Host "Spin Up Time: $SpinUpTime" -BackgroundColor Green
        Write-Host "Start Stop Count: $StartStopCount" -BackgroundColor Green
        if ($null -ne $ReallocatedSectorsCount -and $ReallocatedSectorsCount -match '^\d+$' -and $ReallocatedSectorsCount -eq 0) {
            Write-Host "Reallocated Sectors Count: $ReallocatedSectorsCount" -BackgroundColor Green
        } else {
            Write-Host "Reallocated Sectors Count: $ReallocatedSectorsCount" -BackgroundColor Red
        }
        if ($null -ne $SeekErrorRate -and $SeekErrorRate -match '^\d+$' -and $SeekErrorRate -eq 0) {
            Write-Host "Seek Error Rate: $SeekErrorRate" -BackgroundColor Green
        } else {
            Write-Host "Seek Error Rate: $SeekErrorRate" -BackgroundColor Cyan
        }
        Write-Host "Power On Hours: $PowerOnHoursValue" -BackgroundColor Green
        Write-Host "Spin Retry Count: $SpinRetryCount" -BackgroundColor Green
        Write-Host "Recalibration Retries: $RecalibrationRetries" -BackgroundColor Green
        Write-Host "Power Cycle Count: $PowerCycleCount" -BackgroundColor Green
        Write-Host "Power Off Retract Count: $PowerOffRetractCount" -BackgroundColor Green
        Write-Host "Load Unload Cycle Count: $LoadUnloadCycleCount" -BackgroundColor Green
        Write-Host "Temperature: $Temperature" -BackgroundColor Green
        Write-Host "Reallocation Event Count: $ReallocationEventCount" -BackgroundColor Green
        if ($null -ne $CurrentPendingSectorCount -and $CurrentPendingSectorCount -match '^\d+$' -and $CurrentPendingSectorCount -eq 0) {
            Write-Host "Current Pending Sector Count: $CurrentPendingSectorCount" -BackgroundColor Green
        } else {
            Write-Host "Current Pending Sector Count: $CurrentPendingSectorCount" -BackgroundColor Red
        }
        if ($null -ne $UncorrectableSectorCount -and $UncorrectableSectorCount -match '^\d+$' -and $UncorrectableSectorCount -eq 0) {
            Write-Host "Uncorrectable Sector Count: $UncorrectableSectorCount" -BackgroundColor Green
        } else {
            Write-Host "Uncorrectable Sector Count: $UncorrectableSectorCount" -BackgroundColor Red
        }
        Write-Host "UltraDMACRC Error Count: $UltraDMACRCErrorCount" -BackgroundColor Green
        if ($null -ne $WriteErrorRate -and $WriteErrorRate -match '^\d+$' -and $WriteErrorRate -eq 0) {
            Write-Host "Write Error Rate: $WriteErrorRate" -BackgroundColor Green
        } else {
            Write-Host "Write Error Rate: $WriteErrorRate" -BackgroundColor Cyan
        }
        Write-Host "-------------------------------"
        Write-Host

        # Parse Max Min and Current Temp
        #$hexString = ($diskinfo | Where-Object { $_.ID -eq "C2"}).RawValue

        # Split the string into three parts
        #$part1 = "0x" + $hexString.Substring(0, 4)
        #$part2 = "0x" + $hexString.Substring(4, 4)
        #$part3 = "0x" + $hexString.Substring(8, 4)

        # Output the parts
        #Write-Host "Maximum Temp: $part1"
        #Write-Host "Minimum Temp: $part2"
        #Write-Host "Current Temp: $part3"
    } else {
        Write-Host "FOUND NVME LOG" -ForegroundColor Yellow
        $diskinfo = $DiskInfoRaw -split "`n" | select -skip 1 | Out-String | ConvertFrom-Csv -Delimiter " " -Header "ID","RawValue","Attribute","Name"

        [int64]$CriticalWarnings = "0x" + ($diskinfo | Where-Object { $_.ID -eq "01"}).RawValue
        [int64]$CompositeTemp = "0x" + ($diskinfo | Where-Object { $_.ID -eq "02"}).RawValue - 273.15
        [int64]$AvailableSpare = "0x" + ($diskinfo | Where-Object { $_.ID -eq "03"}).RawValue
        [int64]$AvailableSpareThreshold = "0x" + ($diskinfo | Where-Object { $_.ID -eq "04"}).RawValue
        [int64]$PercentageUsed = "0x" + ($diskinfo | Where-Object { $_.ID -eq "05"}).RawValue
        [int64]$DataUnitsRead = "0x" + ($diskinfo | Where-Object { $_.ID -eq "06"}).RawValue
        [int64]$DataUnitsWritten = "0x" + ($diskinfo | Where-Object { $_.ID -eq "07"}).RawValue
        [int64]$HostReadCommands = "0x" + ($diskinfo | Where-Object { $_.ID -eq "08"}).RawValue
        [int64]$HostWriteCommands = "0x" + ($diskinfo | Where-Object { $_.ID -eq "09"}).RawValue
        [int64]$ControllerBusyTime = "0x" + ($diskinfo | Where-Object { $_.ID -eq "0A"}).RawValue
        [int64]$PowerCycles = "0x" + ($diskinfo | Where-Object { $_.ID -eq "0B"}).RawValue
        [int64]$PowerOnHours = "0x" + ($diskinfo | Where-Object { $_.ID -eq "0C"}).RawValue
        [int64]$UnsafeShutdowns = "0x" + ($diskinfo | Where-Object { $_.ID -eq "0D"}).RawValue
        [int64]$IntegrityErrors = "0x" + ($diskinfo | Where-Object { $_.ID -eq "0E"}).RawValue
        [int64]$InformationLogEntries = "0x" + ($diskinfo | Where-Object { $_.ID -eq "0F"}).RawValue

        Write-Host "Disk Information" -BackgroundColor Magenta
        Write-Host "Model: $($modelObject.Model)" -BackgroundColor Green
        Write-Host "Firmware: $($modelObject.Firmware)" -BackgroundColor Green
        Write-Host "Serial Number: $($modelObject.SerialNumber)" -BackgroundColor Green
        Write-Host "Disk Size: $($modelObject.DiskSize)" -BackgroundColor Green
        Write-Host "Interface: $($modelObject.Interface)" -BackgroundColor Green
        Write-Host "Standard: $($modelObject.Standard)" -BackgroundColor Green
        Write-Host "Transfer Mode: $($modelObject.TransferMode)" -BackgroundColor Green
        Write-Host "PowerOnHours: $($modelObject.PowerOnHours)" -BackgroundColor Green
        Write-Host "PowerOnCount: $($modelObject.PowerOnCount)" -BackgroundColor Green
        Write-Host "Host Reads: $($modelObject.HostReads)" -BackgroundColor Green
        Write-Host "Host Writes: $($modelObject.HostWrites)" -BackgroundColor Green
        Write-Host "Temperature: $($modelObject.Temperature)" -BackgroundColor Green
        if ($modelObject.HealthStatus -match "Good") {
            Write-Host "Health Status: $($modelObject.HealthStatus)" -BackgroundColor Green
        } else {
            Write-Host "Health Status: $($modelObject.HealthStatus)" -BackgroundColor Red
        }
        Write-Host "Features: $($modelObject.Features)" -BackgroundColor Green
        Write-Host "Drive Letter: $($modelObject.DriveLetter)" -BackgroundColor Green
        Write-Host
        Write-Host "Disk Values" -BackgroundColor Magenta
        if ($null -ne $CriticalWarnings -and $CriticalWarnings -match '^\d+$' -and $CriticalWarnings -eq 0) {
            Write-Host "Critical Warnings: $CriticalWarnings" -BackgroundColor Green
        } else {
            Write-Host "Critical Warnings: $CriticalWarnings" -BackgroundColor Red
        }
        Write-Host "Composite Temp: $CompositeTemp" -BackgroundColor Green
        Write-Host "Available Spare: $AvailableSpare" -BackgroundColor Green
        Write-Host "Available Spare Threshold: $AvailableSpareThreshold" -BackgroundColor Green
        Write-Host "Percentage Used: $PercentageUsed" -BackgroundColor Green
        Write-Host "DataUnits Read: $DataUnitsRead" -BackgroundColor Green
        Write-Host "DataUnits Written: $DataUnitsWritten" -BackgroundColor Green
        Write-Host "Host Read Commands: $HostReadCommands" -BackgroundColor Green
        Write-Host "Host Write Commands: $HostWriteCommands" -BackgroundColor Green
        Write-Host "ControllerBusyTime: $ControllerBusyTime" -BackgroundColor Green
        Write-Host "PowerCycles: $PowerCycles" -BackgroundColor Green
        Write-Host "PowerOnHours: $PowerOnHours" -BackgroundColor Green
        if ($null -ne $UnsafeShutdowns -and $UnsafeShutdowns -match '^\d+$' -and $UnsafeShutdowns -eq 0) {
            Write-Host "UnsafeShutdowns: $UnsafeShutdowns" -BackgroundColor Green
        } else {
            Write-Host "UnsafeShutdowns: $UnsafeShutdowns" -BackgroundColor Cyan
        }
        if ($null -ne $IntegrityErrors -and $IntegrityErrors -match '^\d+$' -and $IntegrityErrors -eq 0) {
            Write-Host "IntegrityErrors: $IntegrityErrors" -BackgroundColor Green
        } else {
            Write-Host "IntegrityErrors: $IntegrityErrors" -BackgroundColor Red
        }
        if ($null -ne $InformationLogEntries -and $InformationLogEntries -match '^\d+$' -and $InformationLogEntries -eq 0) {
            Write-Host "InformationLogEntries: $InformationLogEntries" -BackgroundColor Green
        } else {
            Write-Host "InformationLogEntries: $InformationLogEntries" -BackgroundColor Cyan
        }
        Write-Host "-------------------------------"
        Write-Host
    }
}

pause
exit
