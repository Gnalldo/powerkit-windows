# ElevatedHelper.ps1 - session-scoped administrator helper for PowerKit.
#
# Started by the PowerKit window through a UAC consent prompt. It listens on a
# random named pipe and only accepts requests that carry the session token and
# originate from the PowerKit process that launched it. Only catalog tweaks that
# write machine-wide keys, and catalog commands marked Admin, can be requested -
# there is no way to ask it to run arbitrary commands or write arbitrary keys.

param(
    [Parameter(Mandatory = $true)][string]$PipeName,
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $true)][int]$ParentPid,
    [string]$AppRoot = '',
    [string]$ClientSid = '',
    [int]$IdleSeconds = 900
)

$ErrorActionPreference = 'Stop'

function Write-HelperLog {
    param([string]$Message)
    try {
        $dir = Join-Path $env:LOCALAPPDATA 'PowerKit'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $line = ('{0}  [helper {1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID, $Message)
        [System.IO.File]::AppendAllText((Join-Path $dir 'app.log'), $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch { }
}

try {
    if (-not $AppRoot) { $AppRoot = Split-Path -Parent $PSScriptRoot }
    $script:AppRoot = $AppRoot

    . (Join-Path $AppRoot 'src\RegistryTools.ps1')
    . (Join-Path $AppRoot 'src\Catalog.ps1')
    . (Join-Path $AppRoot 'src\Commands.ps1')
} catch {
    Write-HelperLog "Could not load modules: $($_.Exception.Message)"
    exit 1
}

$script:IsAdmin = Test-IsAdmin
$script:ClientSid = $ClientSid
$script:StopRequested = $false
$script:LogTag = '[helper ' + $PID + ']'
Load-Defaults

function New-ElevatedPipe {
    param([string]$Name)

    $direction = [System.IO.Pipes.PipeDirection]::InOut
    $mode = [System.IO.Pipes.PipeTransmissionMode]::Byte
    $options = [System.IO.Pipes.PipeOptions]::Asynchronous

    if ($script:ClientSid) {
        try {
            $security = New-Object System.IO.Pipes.PipeSecurity
            $sid = New-Object System.Security.Principal.SecurityIdentifier($script:ClientSid)
            $rule = New-Object System.IO.Pipes.PipeAccessRule(
                $sid,
                [System.IO.Pipes.PipeAccessRights]::FullControl,
                [System.Security.AccessControl.AccessControlType]::Allow)
            $security.AddAccessRule($rule)
            return New-Object System.IO.Pipes.NamedPipeServerStream($Name, $direction, 1, $mode, $options, 65536, 65536, $security)
        } catch {
            Write-AppLog "Pipe security setup failed, using the default pipe ACL: $($_.Exception.Message)"
        }
    }

    return New-Object System.IO.Pipes.NamedPipeServerStream($Name, $direction, 1, $mode, $options)
}

function Get-PipeClientProcessId {
    param($Pipe)

    if (-not ('PowerKitPipe.Native' -as [type])) {
        try {
            Add-Type -Namespace PowerKitPipe -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetNamedPipeClientProcessId(IntPtr Pipe, out uint ClientProcessId);
'@ -ErrorAction Stop
        } catch {
            return 0
        }
    }

    $clientId = [uint32]0
    try {
        $handle = $Pipe.SafePipeHandle.DangerousGetHandle()
        if ([PowerKitPipe.Native]::GetNamedPipeClientProcessId($handle, [ref]$clientId)) {
            return [int]$clientId
        }
    } catch { }
    return 0
}

function Invoke-HelperRequest {
    param($Request)

    $action = [string]$Request.action
    switch ($action) {
        'ping' {
            return @{ ok = $true; message = 'ready'; elevated = $script:IsAdmin }
        }
        'apply' {
            $tweak = Get-TweakById -Id ([string]$Request.id)
            if ($null -eq $tweak) { throw 'Unknown tweak.' }
            if (-not (Test-TweakAdmin -Tweak $tweak)) { throw 'That tweak does not need administrator rights.' }
            Apply-Tweak -Tweak $tweak -TurnOn ([bool]$Request.on)
            return @{ ok = $true; message = 'applied' }
        }
        'reset' {
            $tweak = Get-TweakById -Id ([string]$Request.id)
            if ($null -eq $tweak) { throw 'Unknown tweak.' }
            if (-not (Test-TweakAdmin -Tweak $tweak)) { throw 'That tweak does not need administrator rights.' }
            Reset-Tweak -Tweak $tweak
            return @{ ok = $true; message = 'reset' }
        }
        'command' {
            $command = $null
            foreach ($entry in $script:CommandDefs) { if ($entry.Id -eq [string]$Request.id) { $command = $entry } }
            if ($null -eq $command) { throw 'Unknown command.' }
            if (-not ($command.ContainsKey('Admin') -and $command.Admin)) { throw 'That command does not need administrator rights.' }
            # Tag this command's RUN lines so the log row can point back at its card.
            $script:LogCommandId = $command.Id
            try {
                $message = Get-HandlerAction -Handler $command.Handler
            } finally {
                $script:LogCommandId = ''
            }
            return @{ ok = $true; message = $message }
        }
        'shutdown' {
            $script:StopRequested = $true
            return @{ ok = $true; message = 'bye' }
        }
        default {
            throw "Unknown action '$action'."
        }
    }
}

Write-AppLog ("Elevated helper ready (pid {0}, parent {1}, administrator {2})" -f $PID, $ParentPid, $script:IsAdmin)
if (-not $script:IsAdmin) { Write-AppLog 'Elevated helper was started WITHOUT administrator rights; machine-wide writes will fail.' }

function Test-HelperSessionAlive {
    if (-not (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)) {
        Write-AppLog 'PowerKit window closed; elevated helper shutting down'
        return $false
    }
    if (((Get-Date) - $lastActivity).TotalSeconds -gt $IdleSeconds) {
        Write-AppLog 'Elevated helper idle timeout'
        return $false
    }
    return $true
}

$lastActivity = Get-Date
$server = $null

while (-not $script:StopRequested) {
    if (-not (Test-HelperSessionAlive)) { break }

    if ($null -eq $server) {
        try {
            $server = New-ElevatedPipe -Name $PipeName
        } catch {
            Write-AppLog "Could not create the helper pipe: $($_.Exception.Message)"
            Start-Sleep -Milliseconds 500
            continue
        }
    }

    try {
        # One persistent pipe instance, so a client connecting exactly when a poll
        # tick elapses is never dropped. We only disconnect after a full reply.
        $connectTask = $server.WaitForConnectionAsync()
        while (-not $connectTask.Wait(500)) {
            if (-not (Test-HelperSessionAlive)) { break }
        }
        if (-not $connectTask.IsCompleted -or -not $server.IsConnected) { break }

        $lastActivity = Get-Date
        $clientPid = Get-PipeClientProcessId -Pipe $server

        $writer = New-Object System.IO.StreamWriter($server, [System.Text.Encoding]::UTF8)
        $writer.AutoFlush = $true
        $reader = New-Object System.IO.StreamReader($server, [System.Text.Encoding]::UTF8)

        if ($clientPid -gt 0 -and $clientPid -ne $ParentPid) {
            Write-AppLog ("Rejected a request from process {0} (expected {1})" -f $clientPid, $ParentPid)
            $writer.WriteLine((@{ ok = $false; error = 'Rejected: the request did not come from the PowerKit window.' } | ConvertTo-Json -Compress))
        } else {
            $readTask = $reader.ReadLineAsync()
            if (-not $readTask.Wait(5000)) {
                throw 'Timed out waiting for the request.'
            }
            $line = $readTask.Result
            if ([string]::IsNullOrWhiteSpace($line)) {
                $response = @{ ok = $false; error = 'Empty request.' }
            } else {
                try {
                    $request = $line | ConvertFrom-Json
                    if (-not $request.token -or [string]$request.token -ne $Token) { throw 'Authorisation failed.' }
                    $response = Invoke-HelperRequest -Request $request
                } catch {
                    $response = @{ ok = $false; error = $_.Exception.Message }
                    Write-AppLog ("Request failed: {0}" -f $_.Exception.Message)
                }
            }
            $writer.WriteLine(($response | ConvertTo-Json -Compress))
            $writer.Flush()
        }

        try { $server.WaitForPipeDrain() } catch { }
        $server.Disconnect()
    } catch {
        Write-AppLog "Helper connection error: $($_.Exception.Message)"
        if ($null -ne $server) { try { $server.Dispose() } catch { } }
        $server = $null
    }
}

if ($null -ne $server) { try { $server.Dispose() } catch { } }
Write-AppLog 'Elevated helper exiting'
exit 0
