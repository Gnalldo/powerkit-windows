# Commands.ps1 - real Windows actions behind the one-click command cards.

$script:PlanBalanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
$script:PlanHigh = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$script:PlanUltimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'

function Get-CommandById {
    param([string]$Id)
    foreach ($command in $script:CommandDefs) { if ($command.Id -eq $Id) { return $command } }
    return $null
}

function Write-RunLog {
    param([string]$FilePath, [string[]]$ArgumentList)

    # RUN lines start with the catalog id of the command that launched them, the same
    # way SET lines start with a tweak id, so the activity log can link back to a card.
    $prefix = if ($script:LogCommandId) { $script:LogCommandId + ' ' } else { '' }
    Write-AppLog ("RUN {0}{1} {2}" -f $prefix, $FilePath, ($ArgumentList -join ' '))
}

function Invoke-StartProcess {
    param([string]$FilePath, [string[]]$ArgumentList)

    Write-RunLog -FilePath $FilePath -ArgumentList $ArgumentList
    $args = @{ FilePath = $FilePath }
    if ($ArgumentList) { $args['ArgumentList'] = $ArgumentList }
    Start-Process @args | Out-Null
}

function Invoke-CmdHidden {
    param([string]$FilePath, [string[]]$ArgumentList)

    Write-RunLog -FilePath $FilePath -ArgumentList $ArgumentList

    # Native tools write progress and errors to stderr; with ErrorActionPreference
    # set to Stop that would become a terminating error, so relax it just here.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = & $FilePath @ArgumentList 2>&1 | ForEach-Object { [string]$_ }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    return @{ ExitCode = $code; Output = (($lines -join "`n").Trim()) }
}

function Get-HandlerAction {
    param([string]$Handler)

    switch ($Handler) {
        'Restart'        { Invoke-StartProcess -FilePath 'shutdown.exe' -ArgumentList '/r', '/t', '0'; return 'Restarting the PC' }
        'Shutdown'       { Invoke-StartProcess -FilePath 'shutdown.exe' -ArgumentList '/s', '/t', '0'; return 'Shutting down' }
        'SignOut'        { Invoke-StartProcess -FilePath 'shutdown.exe' -ArgumentList '/l'; return 'Signing out' }
        'Sleep'          { Invoke-StartProcess -FilePath 'rundll32.exe' -ArgumentList 'powrprof.dll,SetSuspendState', '0,1,0'; return 'Going to sleep' }
        'Lock'           { Invoke-StartProcess -FilePath 'rundll32.exe' -ArgumentList 'user32.dll,LockWorkStation'; return 'PC locked' }
        'CancelShutdown' {
            $result = Invoke-CmdHidden -FilePath 'shutdown.exe' -ArgumentList '/a'
            if ($result.ExitCode -ne 0) { throw 'There is no shutdown or restart in progress.' }
            return 'Pending shutdown cancelled'
        }
        'Hibernate' {
            $availability = (Invoke-CmdHidden -FilePath 'powercfg.exe' -ArgumentList '/a').Output
            if ($availability -notmatch 'Hibernate') {
                throw 'Hibernation is currently disabled. Use "Enable hibernation" in Power and Session first.'
            }
            Invoke-StartProcess -FilePath 'shutdown.exe' -ArgumentList '/h'
            return 'Hibernating'
        }
        'Firmware'  { Invoke-StartProcess -FilePath 'shutdown.exe' -ArgumentList '/r', '/fw', '/t', '0'; return 'Restarting into firmware settings' }
        'RestartExplorer' {
            Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 400
            Start-Process explorer.exe
            Write-AppLog 'Explorer restarted'
            return 'Explorer restarted'
        }
        'PlanHigh' {
            $result = Invoke-CmdHidden -FilePath 'powercfg.exe' -ArgumentList '/setactive', $script:PlanHigh
            if ($result.ExitCode -ne 0) { throw 'Windows would not switch to the High performance plan.' }
            return 'High performance plan active'
        }
        'PlanBalanced' {
            $result = Invoke-CmdHidden -FilePath 'powercfg.exe' -ArgumentList '/setactive', $script:PlanBalanced
            if ($result.ExitCode -ne 0) { throw 'Windows would not switch to the Balanced plan.' }
            return 'Balanced plan active'
        }
        'PlanUltimate' {
            $list = (Invoke-CmdHidden -FilePath 'powercfg.exe' -ArgumentList '/list').Output
            if ($list -notmatch [regex]::Escape($script:PlanUltimate)) {
                $create = Invoke-CmdHidden -FilePath 'powercfg.exe' -ArgumentList '-duplicatescheme', $script:PlanUltimate
                if ($create.ExitCode -ne 0) {
                    throw 'Windows refused to create the Ultimate Performance plan. Administrator rights are required.'
                }
                # Only report success if the plan really showed up.
                $list = (Invoke-CmdHidden -FilePath 'powercfg.exe' -ArgumentList '/list').Output
                if ($list -notmatch [regex]::Escape($script:PlanUltimate)) {
                    throw 'This Windows build does not offer the Ultimate Performance plan. High performance is the closest built-in option.'
                }
            }
            $set = Invoke-CmdHidden -FilePath 'powercfg.exe' -ArgumentList '/setactive', $script:PlanUltimate
            if ($set.ExitCode -ne 0) { throw 'Windows would not switch to the Ultimate Performance plan.' }
            return 'Ultimate Performance plan active'
        }
        'HibernateOff' {
            $result = Invoke-CmdHidden -FilePath 'powercfg.exe' -ArgumentList '/hibernate', 'off'
            if ($result.ExitCode -ne 0) { throw 'powercfg could not disable hibernation. Administrator rights are required.' }
            return 'Hibernation and Fast Startup disabled'
        }
        'HibernateOn' {
            $result = Invoke-CmdHidden -FilePath 'powercfg.exe' -ArgumentList '/hibernate', 'on'
            if ($result.ExitCode -ne 0) { throw 'powercfg could not enable hibernation. Administrator rights are required.' }
            return 'Hibernation enabled'
        }
        'OpenCmd'            { Invoke-StartProcess -FilePath 'cmd.exe'; return 'Command Prompt opened' }
        'OpenPwsh'           { Invoke-StartProcess -FilePath 'powershell.exe'; return 'PowerShell opened' }
        'OpenWindowsTerminal' {
            $terminal = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
            if (Test-Path -LiteralPath $terminal) {
                Invoke-StartProcess -FilePath $terminal
                return 'Windows Terminal opened'
            }
            Invoke-StartProcess -FilePath 'cmd.exe'
            return 'Windows Terminal is not installed - opened Command Prompt instead'
        }
        'OpenTaskmgr'       { Invoke-StartProcess -FilePath 'taskmgr.exe'; return 'Task Manager opened' }
        'OpenSettings'      { Invoke-StartProcess -FilePath 'ms-settings:'; return 'Settings opened' }
        'OpenServices'      { Invoke-StartProcess -FilePath 'services.msc'; return 'Services opened' }
        'OpenDevMgmt'       { Invoke-StartProcess -FilePath 'devmgmt.msc'; return 'Device Manager opened' }
        'OpenCleanmgr'      { Invoke-StartProcess -FilePath 'cleanmgr.exe'; return 'Disk Cleanup opened' }
        'OpenSysdm'         { Invoke-StartProcess -FilePath 'SystemPropertiesAdvanced.exe'; return 'System Properties opened' }
        'OpenPowerOptions'  { Invoke-StartProcess -FilePath 'powercfg.cpl'; return 'Power Options opened' }
        'OpenRegedit'       { Invoke-StartProcess -FilePath 'regedit.exe'; return 'Registry Editor opened' }
        'OpenControl'       { Invoke-StartProcess -FilePath 'control.exe'; return 'Control Panel opened' }
        'OpenNetwork'       { Invoke-StartProcess -FilePath 'ncpa.cpl'; return 'Network connections opened' }
        'OpenWindowsUpdate' { Invoke-StartProcess -FilePath 'ms-settings:windowsupdate'; return 'Windows Update opened' }
        'OpenStartupApps'   { Invoke-StartProcess -FilePath 'ms-settings:startupapps'; return 'Startup apps opened' }
        'OpenMsinfo'        { Invoke-StartProcess -FilePath 'msinfo32.exe'; return 'System Information opened' }
        'CreateGodMode' {
            $desktop = [Environment]::GetFolderPath('Desktop')
            if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
            $folder = Join-Path $desktop 'PowerKit God Mode.{ED7BA470-8E54-465E-825C-99712043E01C}'
            if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
            return 'God Mode folder created on the desktop'
        }
        'FlushDns' {
            $result = Invoke-CmdHidden -FilePath 'ipconfig.exe' -ArgumentList '/flushdns'
            if ($result.ExitCode -ne 0) {
                throw 'Windows refused to flush the DNS cache. This action needs administrator rights.'
            }
            return 'DNS cache flushed'
        }
        'ClearTemp' {
            $temp = [System.IO.Path]::GetTempPath()
            $freed = 0
            $failed = 0
            Get-ChildItem -LiteralPath $temp -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $size = 0
                    if ($_.PSIsContainer) {
                        $size = (Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    } else {
                        $size = $_.Length
                    }
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                    if ($size) { $freed += $size }
                } catch {
                    $failed++
                }
            }
            $mb = [Math]::Round($freed / 1MB, 1)
            return ("Temporary files cleared - {0} MB freed{1}" -f $mb, $(if ($failed -gt 0) { ", $failed item(s) in use" } else { '' }))
        }
        default { throw "Unknown command handler: $Handler" }
    }
}
