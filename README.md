# SnoozeGuard
This script allows you to prevent system/display sleep if a process (or more) is running on a Windows system. "Prevent" means reset of respective timers with use of Windows' native `SetThreadExecutionState` function.

## Parameters
`-requiresDisplay` - array of strings, list of processes (without `.exe`), that require display to stay active. Will also prevent system sleep, since keeping display up while allowing system to sleep does not make sense.  
`-requiresSystem` - array of strings, list of processes (without `.exe`), that requrie system to stay awake, but do not need a display.  
`-focusOnly` - boolean, if list of processes requiring display is provided will determine if a process needs to be focused or just visible (that is not minimized or hidden). If set to `true` (default) window needs to be active/selected to prevent display sleep. Otherwise only system will be prevented from sleeping.  
`-oneTime` - boolean, if `false` (default) will allow the script to run indefinitely, if at least one of the lists of processes is not empty. If `true` will be run only once regardless of whether there are processes running or not.  
`-pollingRate` - number, determines interval in seconds to repeat the check for processes if `-oneTime` is set to `false`. Default value is `120`, that is 2 minutes, which is just enough to handle display sleeping after 3 minutes (value recommended by Windows' "energy recommendations").  
`-debug` - boolean, enables debug mode, that logs stuff to a log file. Default is `false`.  
`-logFile` - string, path to log file, if `-debug` is set to `true`. If not set or invalid will dump to `logfile.txt` near the script file itself.

## Usage
Below example will search for `mstsc` (RDP client) process and if it's found - prevent system, and if the window is visible - display from sleeping. It will not check for `handbrake` status, if `mstsc` is found (since timers are global). If `mstsc` is missing, it will search for `handbrake` and prevent system sleep, if found. Script will be run indefinitely with checks every 2 minutes, even if processes ar enot running.
```powershell
SnoozeGuard.ps1 -requiresDisplay "mstsc" -requiresSystem "handbrake" -focusOnly 0 -pollingRate 120 -oneTime 0
```
Below example, will do the same, but will search for _either_ `mstsc` _or_ `notepad` processes, both of which would require display to stay awake.
```powershell
SnoozeGuard.ps1 -requiresDisplay "mstsc", "notepad" -requiresSystem "handbrake" -focusOnly 0 -pollingRate 120 -oneTime 0
```

## Scheduling
Due to quirks of Powershell, when scheduling in Task Scheduler or otherwise running the file from CMD (not PowerShell itself), use `-Command` instead of `-File` to avoid `Cannot convert value "System.String" to type "System.Boolean"` error. LIke this:
```
powershell -NoProfile -ExecutionPolicy Bypass -Command "C:\SnoozeGuard.ps1" -requiresDisplay "mstsc" -focusOnly 1 -oneTime 1
```
To prevent the CMD pop-up from the task, you will need to use VBS wrapper like this:
```vbs
Dim Args()
ReDim Args(WScript.Arguments.Count - 1)

For i = 0 To WScript.Arguments.Count - 1
   Args(i) = """" & WScript.Arguments(i) & """"
Next
CreateObject("WScript.Shell").Run Join(Args), 0, False
```
Then you will need to schedule a call of `wscript.exe` with parameters like below (`invisible.vbs` is path to the VBS file):
```
"invisible.vbs" powershell -NoProfile -ExecutionPolicy Bypass -Command "C:\SnoozeGuard.ps1" -requiresDisplay "mstsc" -focusOnly 1 -oneTime 1
```
Unfortunately, I was not able to setup the task to be triggered `On Idle`: it just did not run, even though the scheduler showed, that it did (adjusting conditions did not do anything). But it runs fine if you set it up as `On schedule` and run it every X minutes. Or you can add the script to auto-start and let it run indefinitely, if that's your preference.
