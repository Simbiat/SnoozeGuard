param (
    [string[]]$requiresSystem,
    [string[]]$requiresDisplay,
    [int]$pollingRate = 120,
    [bool]$focusOnly = $true,
    [bool]$oneTime = $false,
    [bool]$debug = $false,
    [string]$logFile
)

# Check if PowerState type is already defined (GPT suggests this, not sure why, since for me it does need to do this: possible for compatibility reasons?)
if (-not ([System.Management.Automation.PSTypeName]'PowerState').Type) {
    # Define the PowerState enumeration
    Add-Type @"
        using System;

        [Flags]
        public enum PowerState : uint
        {
            ES_CONTINUOUS = 0x80000000,
            ES_SYSTEM_REQUIRED = 0x00000001,
            ES_DISPLAY_REQUIRED = 0x00000002
        }
"@
}

# Check if NativeMethods type is already defined
if (-not ([System.Management.Automation.PSTypeName]'NativeMethods').Type) {
    # Define the NativeMethods class
    Add-Type @"
        using System;
        using System.Runtime.InteropServices;

        public class NativeMethods
        {
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern uint SetThreadExecutionState(uint esFlags);

            [DllImport("user32.dll")]
            public static extern IntPtr GetForegroundWindow();

            [DllImport("user32.dll", SetLastError = true)]
            public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
        }
"@
}

if (-not ([System.Management.Automation.PSTypeName]'WindowMethods').Type) {
    # DEfine WindowMethods class
    Add-Type @"
        using System;
        using System.Runtime.InteropServices;
        public class WindowMethods {
            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool IsIconic(IntPtr hWnd);
            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool IsWindowVisible(IntPtr hWnd);
        }
"@
}

function SetExecutionState {
    param (
        [PowerState]$esFlags
    )

    $state = [PowerState]::ES_CONTINUOUS -bor $esFlags
    
    # Suppress the output of SetThreadExecutionState
    $result = [NativeMethods]::SetThreadExecutionState($state)

    if ($result -eq 0) {
        LogToFile -logLine "Error: Unable to set execution state." -color Red
    }

    Get-StateNames -Value ([NativeMethods]::SetThreadExecutionState(0))  # Get the current state
}

function Get-StateNames {
    param (
        [uint32]$Value
    )

    if ($Value -band [PowerState]::ES_SYSTEM_REQUIRED -and $Value -band [PowerState]::ES_DISPLAY_REQUIRED) {
        LogToFile -logLine "Fully awake" -color DarkGreen
    }
    elseif ($Value -band [PowerState]::ES_SYSTEM_REQUIRED) {
	LogToFile -logLine "System is awake" -color DarkYellow
    }
    elseif ($Value -band [PowerState]::ES_DISPLAY_REQUIRED) {
	LogToFile -logLine "Display is awake" -color DarkBlue
    }
    else {
        LogToFile -logLine "Feeling sleepy" -color Gray
    }
}

function IsProcessRunning {
    param (
        [string[]]$processName
    )

    foreach ($name in $processName) {
        LogToFile -logLine "Searching for ""$name""..." -color Gray
        $process = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($process) {
            LogToFile -logLine "Process ""$name"" found" -color Gray
            return $true
        }
    }

    return $false
}

function IsProcessFocused {
    param (
        [string]$name
    )

    $foregroundWindow = [NativeMethods]::GetForegroundWindow()

    if ($foregroundWindow -eq [IntPtr]::Zero) {
        return $false
    }

    $processId = 0
    [NativeMethods]::GetWindowThreadProcessId($foregroundWindow, [ref]$processId) | Out-Null

    $focusedProcess = Get-Process -Id $processId -ErrorAction SilentlyContinue

    if ($focusedProcess -and $focusedProcess.ProcessName -eq $name) {
        return $true
    }

    return $false
}

function IsProcessVisible {
    param (
        [string]$processName
    )

    # Get the process by name
    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue

    # Check if the process is found
    if ($process -ne $null) {
        # Check if the main window is minimized or hidden
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            $mainWindow = $process.MainWindowHandle
            $isMinimized = [WindowMethods]::IsIconic($mainWindow)
            $isVisible = [WindowMethods]::IsWindowVisible($mainWindow)

            if ($isMinimized -or -not $isVisible) {
                return $false
            } else {
               return $true
            }
        }
    }
    return $false
}

function LogToFile {
    param (
        [string]$logLine,
        [ConsoleColor]$color = "Gray"
    )

    if ($debug) {
        if ($logFile -ne $null -and $logFile -ne '' -and (Test-Path $logFile -IsValid -PathType Leaf)) {
            $logFilePath = $logFile
        } else {
            # Get the directory of the script
            $scriptDir = (Get-Item $MyInvocation.PSCommandPath).Directory.FullName

            # Construct the log file path
            $logFilePath = Join-Path $scriptDir "logfile.txt"
        }

        # Get the current timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Your log message
        $logMessage = "[$timestamp] $logLine"

        # Write the log line to the file
        Add-Content -Path $logFilePath -Value $logMessage -ErrorAction SilentlyContinue
    }
    Write-Host $logLine -ForegroundColor $color
}

while (($requiresSystem -ne $null -and $requiresSystem.Length -gt 0) -or ($requiresDisplay -ne $null -and $requiresDisplay.Length -gt 0)) {
    if (IsProcessRunning $requiresDisplay) {
        $executionState = [PowerState]::ES_SYSTEM_REQUIRED

        foreach ($name in $requiresDisplay) {
            if (($focusOnly -and (IsProcessFocused $name)) -or (-not $focusOnly -and ((IsProcessFocused $name) -or (IsProcessVisible $name)))) {

                LogToFile -logLine "Process ""$name"" wants display" -color Gray
                $executionState = $executionState -bor [PowerState]::ES_DISPLAY_REQUIRED
                break  # Exit the loop once one focused process is found
            }
        }

        SetExecutionState -esFlags $executionState
    } elseif (IsProcessRunning $requiresSystem) {
        SetExecutionState -esFlags ES_SYSTEM_REQUIRED
    } else {
        LogToFile -logLine "No processes found" -color Gray
        # Release the execution state when the process is not running
        SetExecutionState -esFlags ES_CONTINUOUS | Out-Null
    }

    if ($oneTime) {
        exit 0
    } else {
        Start-Sleep -Seconds $pollingRate
    }
}
