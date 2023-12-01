param (
    [string[]]$requiresSystem,
    [string[]]$requiresDisplay,
    [int]$pollingRate = 120,
    [bool]$focusOnly = $true,
    [bool]$oneTime = $false
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
        Write-Host "Error: Unable to set execution state." -ForegroundColor Red
    }

    Get-StateNames -Value ([NativeMethods]::SetThreadExecutionState(0))  # Get the current state
}

function Get-StateNames {
    param (
        [uint32]$Value
    )

    if ($Value -band [PowerState]::ES_SYSTEM_REQUIRED -and $Value -band [PowerState]::ES_DISPLAY_REQUIRED) {
        Write-Host "Fully awake" -ForegroundColor DarkGreen
    }
    elseif ($Value -band [PowerState]::ES_SYSTEM_REQUIRED) {
	Write-Host "System is awake" -ForegroundColor DarkYellow
    }
    elseif ($Value -band [PowerState]::ES_DISPLAY_REQUIRED) {
	Write-Host "Display is awake" -ForegroundColor DarkBlue
    }
    else {
        Write-Host "Feeling sleepy" -ForegroundColor Gray
    }
}

function IsProcessRunning {
    param (
        [string[]]$processName
    )

    foreach ($name in $processName) {
        Write-Host "Searching for ""$name""..." -ForegroundColor Gray
        $process = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($process) {
            Write-Host "Process ""$name"" found" -ForegroundColor Gray
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

while (($requiresSystem -ne $null -and $requiresSystem.Length -gt 0) -or ($requiresDisplay -ne $null -and $requiresDisplay.Length -gt 0)) {
    if (IsProcessRunning $requiresDisplay) {
        $executionState = [PowerState]::ES_SYSTEM_REQUIRED

        foreach ($name in $requiresDisplay) {
            if (($focusOnly -and (IsProcessFocused $name)) -or (-not $focusOnly -and ((IsProcessFocused $name) -or (IsProcessVisible $name)))) {

                Write-Host "Process ""$name"" wants display" -ForegroundColor Gray
                $executionState = $executionState -bor [PowerState]::ES_DISPLAY_REQUIRED
                break  # Exit the loop once one focused process is found
            }
        }

        SetExecutionState -esFlags $executionState
    } elseif (IsProcessRunning $requiresSystem) {
        SetExecutionState -esFlags ES_SYSTEM_REQUIRED
    } else {
        Write-Host "No processes found" -ForegroundColor Gray
    }

    if ($oneTime) {
        break
    } else {
        Start-Sleep -Seconds $pollingRate
    }
}

# Release the execution state when the process is not running
SetExecutionState -esFlags ES_CONTINUOUS | Out-Null
