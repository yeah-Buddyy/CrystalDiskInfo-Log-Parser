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

$hideSerialNumber = $true

# Define the file path
$filePathDiskInfoIni = "$PSScriptRoot\CrystalDiskInfo\DiskInfo.ini"

# Define the file path
$filePathDiskInfoTxt = "$PSScriptRoot\CrystalDiskInfo\DiskInfo.txt"

# Define the file path
$filePathDiskInfoExe = "$PSScriptRoot\CrystalDiskInfo\DiskInfo64.exe"

# Define the output file path
$outputFile = "$PSScriptRoot\DiskInfoOutput.txt"

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

# Open the output file for writing
Start-Transcript -Path $outputFile

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

    # Print properties and values with conditional formatting
    Write-Host "Disk Information" -BackgroundColor Magenta
    foreach ($property in $modelObject.PSObject.Properties) {
        $propertyName = $property.Name
        $propertyValue = $property.Value

        if ($null -ne $propertyName -and $null -ne $propertyValue) {
            if ($propertyName -eq "HealthStatus") {
                if ($propertyValue -match "Good") {
                    Write-Host "$propertyName`: $propertyValue" -ForegroundColor Green
                } else {
                    Write-Host "$propertyName`: $propertyValue" -ForegroundColor Red
                }
            } else {
                if ($hideSerialNumber) {
                    if ($propertyName -eq "SerialNumber") {
                        $propertyValue = "XXXXXXXXXX"
                    }
                }
                Write-Host "$propertyName`: $propertyValue"
            }
        }
    }
    Write-Host

    # Output the PSCustomObject
    # $modelObject | Format-List

    # Get the first line
    $firstLine = ($DiskInfoRaw | Select-Object -First 1)

    # Check if the first line contains "Cur", "Wor", and "Thr"
    if ($firstLine -match "Cur" -and $firstLine -match "Wor" -and $firstLine -match "Thr") {
        # Write-Host "FOUND HDD OR SSD LOG" -ForegroundColor Cyan

        # Parse the raw data into an array of custom objects
        $diskinfo = $DiskInfoRaw -split "`n" | Select-Object -Skip 1 | ForEach-Object {
            $columns = $_ -split "\s+"
            [PSCustomObject]@{
                ID            = $columns[0]
                Cur           = $columns[1]
                Wor           = $columns[2]
                Thr           = $columns[3]
                RawValue      = $columns[4]
                AttributeName = $columns[5..($columns.Length - 1)] -join " "
            }
        }

        # Print the ID and RawValue for each entry
        Write-Host "Disk Values" -BackgroundColor Magenta
        foreach ($entry in $diskinfo) {
            if ($null -ne $entry.ID -and $null -ne $entry.AttributeName -and $null -ne $entry.RawValue) {
                $id = $entry.ID
                $attributeName = $entry.AttributeName
                $rawValue = [System.Convert]::ToInt64($entry.RawValue ,16)

                if ($id -eq "C2") {
                    if ($rawValue -match '^\d+$') {
                        $maxTemp = $entry.RawValue.Substring(0, 4)
                        $minTemp = $entry.RawValue.Substring(4, 4)
                        $currentTemp = $entry.RawValue.Substring(8, 4)

                        $maxTempRaw = [System.Convert]::ToInt64($maxTemp ,16)
                        $currentTempRaw = [System.Convert]::ToInt64($currentTemp ,16)

                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $currentTempRaw"

                        if ($null -ne $maxTempRaw -and $maxTempRaw -match '^\d+$') {
                            if ($null -ne $currentTempRaw -and $currentTempRaw -match '^\d+$') {
                                if (-not($maxTempRaw -eq 0)) {
                                    if ($currentTempRaw  -gt $maxTempRaw) {
                                        Write-Host "$($modelObject.Model) is currently running above the maximum temperature rating. Max Temperature: $maxTempRaw | Current Temperature: $currentTempRaw" -BackgroundColor Red
                                        Write-Host
                                        $maxTempRaw = ""
                                        $currentTempRaw = ""
                                    }
                                }
                            }
                        }
                        continue
                    }
                }
                if ($id -eq "01") {
                    if ($rawValue -match '^\d+$' -and $rawValue -ge $MaxReadErrorRate) {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue" -BackgroundColor Red
                        continue
                    } else {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue"
                        continue
                    }
                } 
                if ($id -eq "05") {
                    if ($rawValue -match '^\d+$' -and $rawValue -ge $MaxReallocatedSectorsCount) {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue" -BackgroundColor Red

                        # $null -ne ensures that var is not empty.
                        # -match '^\d+$' uses a regular expression to verify that var contains only digits, making it a valid integer.
                        # Reallocated sectors are a warning sign that your disk may be dying if the number is very high or if it increases rapidly. 
                        # If you have 1, 2 or even 20 reallocated sectors on your drive it may not be a cause for panic, as many hard drives can last for years with only a few bad sectors being reallocated. 
                        # But you have to watch this number very closely, because if it increases over time it’s likely that the disk is dying
                        $RegistryBase = "HKLM:\SOFTWARE\SMARTCheck\Monitoring\ReallocatedSectorsCount"

                        # Set disk registry path
                        $RegistryPath = Join-Path -Path $RegistryBase -ChildPath "$($modelObject.Model)"
                            
                        # Create disk registry key if not present
                        if (-not (Test-Path -Path $RegistryPath)) {
                            New-Item -Path $RegistryPath -Force | Out-Null
                        }
                            
                        # Set registry values and warning message
                        New-ItemProperty -Path $RegistryPath -Name $((Get-Date).ToString('yyyy-MM-dd')) -Value $rawValue -PropertyType "String" -Force | Out-Null

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
                        continue
                    } else {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue"
                        continue
                    }
                } 
                if ($id -eq "C5") {
                    if ($rawValue -match '^\d+$' -and $rawValue -ge $MaxCurrentPendingSectorCount) {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue" -BackgroundColor Red

                        # Pending sectors are a warning sign that your drive may experience some problems or failure. The main way to determine whether or not your drive is likely to fail is how quickly this count increases. 
                        # If your count is fairly low (say <20) and after continuing to use the drive, rebooting the system, etc the count stays the exact same, your drive may be okay. However, 
                        # if your pending sector count increases you should immediately replace the drive to prevent data loss.
                        $RegistryBase = "HKLM:\SOFTWARE\SMARTCheck\Monitoring\CurrentPendingSectorCount"

                        # Set disk registry path
                        $RegistryPath = Join-Path -Path $RegistryBase -ChildPath "$($modelObject.Model)"
                            
                        # Create disk registry key if not present
                        if (-not (Test-Path -Path $RegistryPath)) {
                            New-Item -Path $RegistryPath -Force | Out-Null
                        }
                            
                        # Set registry values and warning message
                        New-ItemProperty -Path $RegistryPath -Name $((Get-Date).ToString('yyyy-MM-dd')) -Value $rawValue -PropertyType "String" -Force | Out-Null

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
                        continue
                    } else {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue"
                        continue
                    }
                }
                if ($id -eq "C6") {
                    if ($rawValue -match '^\d+$' -and $rawValue -ge $MaxUncorrectableSectorCount) {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue" -BackgroundColor Red

                        # Like Reallocated and Pending sectors, if this count does not drastically increase over time it may be okay to keep using the drive. 
                        # However, it is advisable to replace the hard drive if your data is important to you and to only continue using the drive for non-critical data storage. 
                        # You should backup any data on the drive immediately if you do not already have a recent backup.
                        $RegistryBase = "HKLM:\SOFTWARE\SMARTCheck\Monitoring\UncorrectableSectorCount"

                        # Set disk registry path
                        $RegistryPath = Join-Path -Path $RegistryBase -ChildPath "$($modelObject.Model)"
                            
                        # Create disk registry key if not present
                        if (-not (Test-Path -Path $RegistryPath)) {
                            New-Item -Path $RegistryPath -Force | Out-Null
                        }
                            
                        # Set registry values and warning message
                        New-ItemProperty -Path $RegistryPath -Name $((Get-Date).ToString('yyyy-MM-dd')) -Value $rawValue -PropertyType "String" -Force | Out-Null

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
                        continue
                    } else {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue"
                        continue
                    }
                }
                if ($id -eq "C8") {
                    if ($rawValue -match '^\d+$' -and $rawValue -ge $MaxWriteErrorRate) {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue" -BackgroundColor Red
                        continue
                    } else {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue"
                        continue
                    }
                }
                Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue"
            }
        }
        Write-Host "-------------------------------"
        Write-Host
    } else {
        # Write-Host "FOUND NVME LOG" -ForegroundColor Cyan

        # Parse the raw data into an array of custom objects
        $diskinfo = $DiskInfoRaw -split "`n" | Select-Object -Skip 1 | ForEach-Object {
            $columns = $_ -split "\s+"
            [PSCustomObject]@{
                ID            = $columns[0]
                RawValue      = $columns[1]
                AttributeName = $columns[2..($columns.Length - 1)] -join " "
            }
        }

        # Print the ID and RawValue for each entry
        Write-Host "Disk Values" -BackgroundColor Magenta
        foreach ($entry in $diskinfo) {
            if ($null -ne $entry.ID -and $null -ne $entry.AttributeName -and $null -ne $entry.RawValue) {
                $id = $entry.ID
                $attributeName = $entry.AttributeName
                $rawValue = [System.Convert]::ToInt64($entry.RawValue ,16)

               if ($id -eq "02") {
                    if ($rawValue -match '^\d+$') {
                        $maxTemp = $entry.RawValue.Substring(0, 4)
                        $minTemp = $entry.RawValue.Substring(4, 4)
                        $currentTemp = $entry.RawValue.Substring(8, 4)

                        $maxTempRaw = [System.Convert]::ToInt64($maxTemp ,16)
                        $currentTempRaw = [System.Convert]::ToInt64($currentTemp ,16) - 273.15

                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $currentTempRaw"

                        if ($null -ne $maxTempRaw -and $maxTempRaw -match '^\d+$') {
                            if ($null -ne $currentTempRaw -and $currentTempRaw -match '^\d+$') {
                                if (-not($maxTempRaw -eq 0)) {
                                    if ($currentTempRaw  -gt $maxTempRaw) {
                                        Write-Host "$($modelObject.Model) is currently running above the maximum temperature rating. Max Temperature: $maxTempRaw | Current Temperature: $currentTempRaw" -BackgroundColor Red
                                        Write-Host
                                        $maxTempRaw = ""
                                        $currentTempRaw = ""
                                    }
                                }
                            }
                        }
                        continue
                    }
                }
                if ($id -eq "01") {
                    if ($rawValue -match '^\d+$' -and $rawValue -eq 0) {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue"
                        continue
                    } else {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue" -BackgroundColor Red
                        continue
                    }
                }
                if ($id -eq "0D") {
                    if ($rawValue -match '^\d+$' -and $rawValue -eq 0 ) {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue"
                        continue
                    } else {
                        Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue" -ForegroundColor Yellow
                        continue
                    }
                }
                Write-Host "ID: $id, AttributeName: $attributeName, RawValue: $rawValue"
            }
        }
        Write-Host "-------------------------------"
        Write-Host
    }
}

# Close the transcript
Stop-Transcript

pause
exit
