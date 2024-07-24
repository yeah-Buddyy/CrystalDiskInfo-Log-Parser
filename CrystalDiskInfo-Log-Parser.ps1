# Run as Admin
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell.exe -Verb RunAs "-NoProfile -NoLogo -ExecutionPolicy Bypass -Command `"cd '$pwd'; & '$PSCommandPath';`"";
    exit;
}

$MaxReadErrorRate = 100
$MaxWriteErrorRate = 100
$MaxReallocatedSectorsCount = 1
$MaxCurrentPendingSectorCount = 1
$MaxUncorrectableSectorCount = 1

# Define the file path
$filePathDiskInfoIni = "$PSScriptRoot\CrystalDiskInfo\DiskInfo.ini"

# Define the file path
$filePathDiskInfoTxt = "$PSScriptRoot\CrystalDiskInfo\DiskInfo.txt"

# Define the file path
$filePathDiskInfoExe = "$PSScriptRoot\CrystalDiskInfo\DiskInfo64.exe"

$DownloadURL = "https://sourceforge.net/projects/crystaldiskinfo/files/9.3.2/CrystalDiskInfo9_3_2.zip/download"
$DownloadLocation = Join-Path -Path $PSScriptRoot -ChildPath "CrystalDiskInfo"
$ZipFilePath = Join-Path -Path $DownloadLocation -ChildPath "CrystalDiskInfo.zip"

# Download CrystalDiskInfo
if (-not (Test-Path -Path $filePathDiskInfoExe -PathType Leaf)) {
    # Check if the download location directory exists
    if (-not (Test-Path -Path $DownloadLocation)) {
        # Create the directory
        New-Item -Path $DownloadLocation -ItemType Directory -Force | Out-Null
    }

    # Download the zip file
    Invoke-WebRequest -UserAgent "Wget" -Uri $DownloadURL -OutFile $ZipFilePath

    # Check if the zip file was downloaded successfully
    if (Test-Path -Path $ZipFilePath) {
        # Extract the zip file
        Expand-Archive -Path $ZipFilePath -DestinationPath $DownloadLocation -Force

        # Remove the zip file after extraction
        Remove-Item -Path $ZipFilePath -Force
    } else {
        Write-Error "Failed to download the file from $DownloadURL"
    }
} else {
    Write-Host "CrystalDiskInfo already downloaded" -ForegroundColor Cyan
}

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
Write-Host "DiskInfo.ini has been created/overwritten with the specified content." -ForegroundColor Cyan

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

# Function to get the latest and second latest registry entry
function Get-LatestAndSecondLatestRegistryValues {
    param (
        [parameter(Mandatory = $true)][string]$RegistryPath
    )
    
    # Check if registry path exists
    if (-not (Test-Path -Path $RegistryPath)) {
        Write-Host "Registry path does not exist: $RegistryPath" -ForegroundColor Cyan
        return $null
    }
    
    # Get all property names (dates) in the registry path
    $propertyNames = Get-ItemProperty -Path $RegistryPath | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
    
    # Filter dates and convert to datetime objects
    $dates = @()
    foreach ($prop in $propertyNames) {
        if ($prop -match "^\d{4}-\d{2}-\d{2}$") { # Check if property name is a date in 'yyyy-MM-dd' format
            $propDate = [datetime]::ParseExact($prop, 'yyyy-MM-dd', $null)
            $dates += $propDate
        }
    }
    
    # Get the latest and second latest dates from the filtered dates
    if ($dates.Count -gt 1) {
        $sortedDates = $dates | Sort-Object -Descending
        $latestDate = $sortedDates[0]
        $secondLatestDate = $sortedDates[1]
        
        $latestDateString = $latestDate.ToString('yyyy-MM-dd')
        $secondLatestDateString = $secondLatestDate.ToString('yyyy-MM-dd')
        
        # Get the registry values for the latest and second latest dates
        $latestValue = (Get-ItemProperty -Path $RegistryPath -Name $latestDateString).$latestDateString
        $secondLatestValue = (Get-ItemProperty -Path $RegistryPath -Name $secondLatestDateString).$secondLatestDateString
        
        return @{
            LatestDate = $latestDateString
            LatestValue = $latestValue
            SecondLatestDate = $secondLatestDateString
            SecondLatestValue = $secondLatestValue
        }
    } elseif ($dates.Count -eq 1) {
        $latestDate = $dates[0]
        $latestDateString = $latestDate.ToString('yyyy-MM-dd')
        
        # Get the registry value for the latest date
        $latestValue = (Get-ItemProperty -Path $RegistryPath -Name $latestDateString).$latestDateString
        
        return @{
            LatestDate = $latestDateString
            LatestValue = $latestValue
            SecondLatestDate = $null
            SecondLatestValue = $null
        }
    } else {
        Write-Host "No valid dates found in the registry path $RegistryPath." -ForegroundColor Cyan
        return $null
    }
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
        Write-Host "FOUND HDD OR SSD LOG" -ForegroundColor Cyan
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
        Write-Host "Model: $($modelObject.Model)"
        Write-Host "Firmware: $($modelObject.Firmware)"
        Write-Host "Serial Number: $($modelObject.SerialNumber)"
        Write-Host "Disk Size: $($modelObject.DiskSize)"
        Write-Host "Buffer Size: $($modelObject.BufferSize)"
        Write-Host "Queue Depth: $($modelObject.QueueDepth)"
        Write-Host "# of Sectors: $($modelObject.'#ofSectors')"
        Write-Host "Rotation Rate: $($modelObject.RotationRate)"
        Write-Host "Interface: $($modelObject.Interface)"
        Write-Host "Major Version: $($modelObject.MajorVersion)"
        Write-Host "Minor Version: $($modelObject.MinorVersion)"
        Write-Host "Transfer Mode: $($modelObject.TransferMode)"
        Write-Host "PowerOnHours: $($modelObject.PowerOnHours)"
        Write-Host "PowerOnCount: $($modelObject.PowerOnCount)"
        Write-Host "Temperature: $($modelObject.Temperature)"
        if ($modelObject.HealthStatus -match "Good") {
            Write-Host "Health Status: $($modelObject.HealthStatus)" -ForegroundColor Green
        } else {
            Write-Host "Health Status: $($modelObject.HealthStatus)" -BackgroundColor Red
        }
        Write-Host "Features: $($modelObject.Features)"
        Write-Host "APM Level: $($modelObject.APMLevel)"
        Write-Host "AAM Level: $($modelObject.AAMLevel)"
        Write-Host "Drive Letter: $($modelObject.DriveLetter)"

        Write-Host

        Write-Host "Disk Values" -BackgroundColor Magenta
        if ($null -ne $ReadErrorRate -and $ReadErrorRate -match '^\d+$' -and $ReadErrorRate -ge $MaxReadErrorRate) {
            Write-Host "Read Error Rate: $ReadErrorRate" -BackgroundColor Red
        } else {
            Write-Host "Read Error Rate: $ReadErrorRate" -ForegroundColor Green
        }
        Write-Host "Spin Up Time: $SpinUpTime"
        Write-Host "Start Stop Count: $StartStopCount"
        if ($null -ne $ReallocatedSectorsCount -and $ReallocatedSectorsCount -match '^\d+$' -and $ReallocatedSectorsCount -ge $MaxReallocatedSectorsCount) {
            Write-Host "Reallocated Sectors Count: $ReallocatedSectorsCount" -BackgroundColor Red
        } else {
            Write-Host "Reallocated Sectors Count: $ReallocatedSectorsCount" -ForegroundColor Green
        }
        Write-Host "Seek Error Rate: $SeekErrorRate"
        Write-Host "Power On Hours: $PowerOnHoursValue"
        Write-Host "Spin Retry Count: $SpinRetryCount"
        Write-Host "Recalibration Retries: $RecalibrationRetries"
        Write-Host "Power Cycle Count: $PowerCycleCount"
        Write-Host "Power Off Retract Count: $PowerOffRetractCount"
        Write-Host "Load Unload Cycle Count: $LoadUnloadCycleCount"
        Write-Host "Temperature: $Temperature"
        Write-Host "Reallocation Event Count: $ReallocationEventCount"
        if ($null -ne $CurrentPendingSectorCount -and $CurrentPendingSectorCount -match '^\d+$' -and $CurrentPendingSectorCount -ge $MaxCurrentPendingSectorCount) {
            Write-Host "Current Pending Sector Count: $CurrentPendingSectorCount" -BackgroundColor Red
        } else {
            Write-Host "Current Pending Sector Count: $CurrentPendingSectorCount" -ForegroundColor Green
        }
        if ($null -ne $UncorrectableSectorCount -and $UncorrectableSectorCount -match '^\d+$' -and $UncorrectableSectorCount -ge $MaxUncorrectableSectorCount) {
            Write-Host "Uncorrectable Sector Count: $UncorrectableSectorCount" -BackgroundColor Red
        } else {
            Write-Host "Uncorrectable Sector Count: $UncorrectableSectorCount" -ForegroundColor Green
        }
        Write-Host "UltraDMACRC Error Count: $UltraDMACRCErrorCount"
        if ($null -ne $WriteErrorRate -and $WriteErrorRate -match '^\d+$' -and $WriteErrorRate -ge $MaxWriteErrorRate) {
            Write-Host "Write Error Rate: $WriteErrorRate" -BackgroundColor Red
        } else {
            Write-Host "Write Error Rate: $WriteErrorRate" -ForegroundColor Green
        }
        Write-Host "-------------------------------"
        Write-Host

        # Parse Max Min and Current Temp
        $hexString = ($diskinfo | Where-Object { $_.ID -eq "C2"}).RawValue

        # Split the string into three parts
        $maxTemp = "0x" + $hexString.Substring(0, 4)
        $minTemp = "0x" + $hexString.Substring(4, 4)
        $currentTemp = "0x" + $hexString.Substring(8, 4)

        if ($null -ne [uint32]$Temperature -and [uint32]$Temperature -match '^\d+$') {
            if ($null -ne [uint32]$maxTemp -and [uint32]$maxTemp -match '^\d+$') {
                if (-not([uint32]$maxTemp -eq 0)) {
                    if ([uint32]$Temperature -gt [uint32]$maxTemp) {
                        Write-Host "$($modelObject.Model) is currently running above the maximum temperature rating. Max Temperature: $([uint32]$maxTemp) | Current Temperature: $([uint32]$Temperature)" -BackgroundColor Red
                        Write-Host
                    }
                }
            }
        }

        # Output the parts
        #Write-Host "Maximum Temp: $maxTemp "
        #Write-Host "Minimum Temp: $minTemp"
        #Write-Host "Current Temp: $currentTemp"

        # $null -ne ensures that var is not empty.
        # -match '^\d+$' uses a regular expression to verify that var contains only digits, making it a valid integer.
        # Reallocated sectors are a warning sign that your disk may be dying if the number is very high or if it increases rapidly. 
        # If you have 1, 2 or even 20 reallocated sectors on your drive it may not be a cause for panic, as many hard drives can last for years with only a few bad sectors being reallocated. 
        # But you have to watch this number very closely, because if it increases over time it’s likely that the disk is dying
        if ($null -ne $ReallocatedSectorsCount -and $ReallocatedSectorsCount -match '^\d+$' -and $ReallocatedSectorsCount -ge $MaxReallocatedSectorsCount) {
            $RegistryBase = "HKLM:\SOFTWARE\SMARTCheck\Monitoring\ReallocatedSectorsCount"

            # Set disk registry path
            $RegistryPath = Join-Path -Path $RegistryBase -ChildPath "$($modelObject.Model)"
                
            # Create disk registry key if not present
            if (-not (Test-Path -Path $RegistryPath)) {
                New-Item -Path $RegistryPath -Force | Out-Null
            }
                
            # Set registry values and warning message
            New-ItemProperty -Path $RegistryPath -Name $((Get-Date).ToString('yyyy-MM-dd')) -Value $ReallocatedSectorsCount -PropertyType "String" -Force | Out-Null

            $latestEntries = Get-LatestAndSecondLatestRegistryValues -RegistryPath $RegistryPath

            if ($latestEntries) {
                Write-Host "Latest Reallocated Sectors Count registry entry for disk $($modelObject.Model)" -ForegroundColor Cyan
                Write-Host "Date: $($latestEntries.LatestDate)" -ForegroundColor Cyan
                Write-Host "Value: $($latestEntries.LatestValue)" -ForegroundColor Cyan
                
                if ($latestEntries.SecondLatestDate) {
                    Write-Host "Second latest Reallocated Sectors Count registry entry for disk $($modelObject.Model)" -ForegroundColor Cyan
                    Write-Host "Date: $($latestEntries.SecondLatestDate)" -ForegroundColor Cyan
                    Write-Host "Value: $($latestEntries.SecondLatestValue)" -ForegroundColor Cyan
                    if ($latestEntries.LatestValue -gt $latestEntries.SecondLatestValue) {
                        $FinalReallocatedSectorsCount = [int]$latestEntries.LatestValue - [int]$latestEntries.SecondLatestValue
                        $OutputMsg = "Disk $($modelObject.Model) - The number of reallocated sectors has increased by a factor of $FinalReallocatedSectorsCount since the last check. This is generally a bad sign and you should replace your drive immediately."
                        Write-Host $OutputMsg -BackgroundColor Red
                    }
                } else {
                    Write-Host "No second latest entry found for disk $($modelObject.Model)" -ForegroundColor Cyan
                }
            } else {
                Write-Host "No entries found for disk $($modelObject.Model)" -ForegroundColor Cyan
            }
        }

        # Pending sectors are a warning sign that your drive may experience some problems or failure. The main way to determine whether or not your drive is likely to fail is how quickly this count increases. 
        # If your count is fairly low (say <20) and after continuing to use the drive, rebooting the system, etc the count stays the exact same, your drive may be okay. However, 
        # if your pending sector count increases you should immediately replace the drive to prevent data loss.
        if ($null -ne $CurrentPendingSectorCount -and $CurrentPendingSectorCount -match '^\d+$' -and $CurrentPendingSectorCount -ge $MaxCurrentPendingSectorCount) {
            $RegistryBase = "HKLM:\SOFTWARE\SMARTCheck\Monitoring\CurrentPendingSectorCount"

            # Set disk registry path
            $RegistryPath = Join-Path -Path $RegistryBase -ChildPath "$($modelObject.Model)"
                
            # Create disk registry key if not present
            if (-not (Test-Path -Path $RegistryPath)) {
                New-Item -Path $RegistryPath -Force | Out-Null
            }
                
            # Set registry values and warning message
            New-ItemProperty -Path $RegistryPath -Name $((Get-Date).ToString('yyyy-MM-dd')) -Value $CurrentPendingSectorCount -PropertyType "String" -Force | Out-Null

            $latestEntries = Get-LatestAndSecondLatestRegistryValues -RegistryPath $RegistryPath

            if ($latestEntries) {
                Write-Host "Latest Current Pending Sector Count registry entry for disk $($modelObject.Model)" -ForegroundColor Cyan
                Write-Host "Date: $($latestEntries.LatestDate)" -ForegroundColor Cyan
                Write-Host "Value: $($latestEntries.LatestValue)" -ForegroundColor Cyan
                
                if ($latestEntries.SecondLatestDate) {
                    Write-Host "Second latest Current Pending Sector Count registry entry for disk $($modelObject.Model)" -ForegroundColor Cyan
                    Write-Host "Date: $($latestEntries.SecondLatestDate)" -ForegroundColor Cyan
                    Write-Host "Value: $($latestEntries.SecondLatestValue)" -ForegroundColor Cyan
                    if ($latestEntries.LatestValue -gt $latestEntries.SecondLatestValue) {
                        $FinalCurrentPendingSectorCount = [int]$latestEntries.LatestValue - [int]$latestEntries.SecondLatestValue
                        $OutputMsg = "Disk $($modelObject.Model) - The number of current pending sectors has increased by a factor of $FinalCurrentPendingSectorCount since the last check. This is generally a bad sign and you should replace your drive immediately."
                        Write-Host $OutputMsg -BackgroundColor Red
                    }
                } else {
                    Write-Host "No second latest entry found for disk $($modelObject.Model)" -ForegroundColor Cyan
                }
            } else {
                Write-Host "No entries found for disk $($modelObject.Model)" -ForegroundColor Cyan
            }
        }

        # Like Reallocated and Pending sectors, if this count does not drastically increase over time it may be okay to keep using the drive. 
        # However, it is advisable to replace the hard drive if your data is important to you and to only continue using the drive for non-critical data storage. 
        # You should backup any data on the drive immediately if you do not already have a recent backup.
        if ($null -ne $UncorrectableSectorCount -and $UncorrectableSectorCount -match '^\d+$' -and $UncorrectableSectorCount -ge $MaxUncorrectableSectorCount) {
            $RegistryBase = "HKLM:\SOFTWARE\SMARTCheck\Monitoring\UncorrectableSectorCount"

            # Set disk registry path
            $RegistryPath = Join-Path -Path $RegistryBase -ChildPath "$($modelObject.Model)"
                
            # Create disk registry key if not present
            if (-not (Test-Path -Path $RegistryPath)) {
                New-Item -Path $RegistryPath -Force | Out-Null
            }
                
            # Set registry values and warning message
            New-ItemProperty -Path $RegistryPath -Name $((Get-Date).ToString('yyyy-MM-dd')) -Value $UncorrectableSectorCount -PropertyType "String" -Force | Out-Null

            $latestEntries = Get-LatestAndSecondLatestRegistryValues -RegistryPath $RegistryPath

            if ($latestEntries) {
                Write-Host "Latest Uncorrectable Sector Count registry entry for disk $($modelObject.Model)" -ForegroundColor Cyan
                Write-Host "Date: $($latestEntries.LatestDate)" -ForegroundColor Cyan
                Write-Host "Value: $($latestEntries.LatestValue)" -ForegroundColor Cyan
                
                if ($latestEntries.SecondLatestDate) {
                    Write-Host "Second latest Uncorrectable Sector Count registry entry for disk $($modelObject.Model)" -ForegroundColor Cyan
                    Write-Host "Date: $($latestEntries.SecondLatestDate)" -ForegroundColor Cyan
                    Write-Host "Value: $($latestEntries.SecondLatestValue)" -ForegroundColor Cyan
                    if ($latestEntries.LatestValue -gt $latestEntries.SecondLatestValue) {
                        $FinalUncorrectableSectorCount = [int]$latestEntries.LatestValue - [int]$latestEntries.SecondLatestValue
                        $OutputMsg = "Disk $($modelObject.Model) - The number of uncorrectable sector count has increased by a factor of $FinalUncorrectableSectorCount since the last check. This is generally a bad sign and you should replace your drive immediately."
                        Write-Host $OutputMsg -BackgroundColor Red
                    }
                } else {
                    Write-Host "No second latest entry found for disk $($modelObject.Model)" -ForegroundColor Cyan
                }
            } else {
                Write-Host "No entries found for disk $($modelObject.Model)" -ForegroundColor Cyan
            }
        }
    } else {
        Write-Host "FOUND NVME LOG" -ForegroundColor Cyan
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
        Write-Host "Model: $($modelObject.Model)"
        Write-Host "Firmware: $($modelObject.Firmware)"
        Write-Host "Serial Number: $($modelObject.SerialNumber)"
        Write-Host "Disk Size: $($modelObject.DiskSize)"
        Write-Host "Interface: $($modelObject.Interface)"
        Write-Host "Standard: $($modelObject.Standard)"
        Write-Host "Transfer Mode: $($modelObject.TransferMode)"
        Write-Host "PowerOnHours: $($modelObject.PowerOnHours)"
        Write-Host "PowerOnCount: $($modelObject.PowerOnCount)"
        Write-Host "Host Reads: $($modelObject.HostReads)"
        Write-Host "Host Writes: $($modelObject.HostWrites)"
        Write-Host "Temperature: $($modelObject.Temperature)"
        if ($modelObject.HealthStatus -match "Good") {
            Write-Host "Health Status: $($modelObject.HealthStatus)" -ForegroundColor Green
        } else {
            Write-Host "Health Status: $($modelObject.HealthStatus)" -BackgroundColor Red
        }
        Write-Host "Features: $($modelObject.Features)"
        Write-Host "Drive Letter: $($modelObject.DriveLetter)"

        Write-Host

        Write-Host "Disk Values" -BackgroundColor Magenta
        if ($null -ne $CriticalWarnings -and $CriticalWarnings -match '^\d+$' -and $CriticalWarnings -eq 0) {
            Write-Host "Critical Warnings: $CriticalWarnings" -ForegroundColor Green
        } else {
            Write-Host "Critical Warnings: $CriticalWarnings" -BackgroundColor Red
        }
        Write-Host "Composite Temp: $CompositeTemp"
        Write-Host "Available Spare: $AvailableSpare"
        Write-Host "Available Spare Threshold: $AvailableSpareThreshold"
        Write-Host "Percentage Used: $PercentageUsed"
        Write-Host "DataUnits Read: $DataUnitsRead"
        Write-Host "DataUnits Written: $DataUnitsWritten"
        Write-Host "Host Read Commands: $HostReadCommands"
        Write-Host "Host Write Commands: $HostWriteCommands"
        Write-Host "ControllerBusyTime: $ControllerBusyTime"
        Write-Host "PowerCycles: $PowerCycles"
        Write-Host "PowerOnHours: $PowerOnHours"
        if ($null -ne $UnsafeShutdowns -and $UnsafeShutdowns -match '^\d+$' -and $UnsafeShutdowns -eq 0) {
            Write-Host "UnsafeShutdowns: $UnsafeShutdowns" -ForegroundColor Green
        } else {
            Write-Host "UnsafeShutdowns: $UnsafeShutdowns" -ForegroundColor Yellow
        }
        Write-Host "IntegrityErrors: $IntegrityErrors"
        Write-Host "InformationLogEntries: $InformationLogEntries"
        Write-Host "-------------------------------"
        Write-Host
    }
}

pause
exit
