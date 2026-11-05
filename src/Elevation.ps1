# Elevation.ps1 - talks to the session-scoped administrator helper.
#
# One UAC approval per app session. After the helper is up, every machine-wide
# tweak and admin command is sent over a private named pipe instead of asking the
# user to restart PowerKit, so the window keeps its state and scroll position.

$script:Elevation = @{
    Started   = $false
    Ready     = $false
    PipeName  = ''
    Token     = ''
    Process   = $null
    LastError = ''
    Frame     = $null
}

$script:ElevationProbeOk = $false
$script:ElevationDeadline = $null

function Start-ElevatedHelper {
    if ($script:Elevation.Ready) { return $true }
    if ($script:IsAdmin) { return $true }

    $helperPath = Join-Path $script:AppRoot 'src\ElevatedHelper.ps1'
    if (-not (Test-Path -LiteralPath $helperPath)) {
        $script:Elevation.LastError = 'The elevated helper script is missing.'
        return $false
    }

    $pipeName = 'PowerKit-' + [guid]::NewGuid().ToString('N')
    $token = [guid]::NewGuid().ToString('N')
    $clientSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $exe = (Get-Process -Id $PID).Path

    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', "`"$helperPath`"",
        '-PipeName', $pipeName,
        '-Token', $token,
        '-ParentPid', [string]$PID,
        '-AppRoot', "`"$script:AppRoot`"",
        '-ClientSid', $clientSid
    )

    try {
        $process = Start-Process -FilePath $exe -Verb RunAs -ArgumentList $arguments -PassThru -WindowStyle Hidden
        $script:Elevation.Started = $true
        $script:Elevation.Ready = $false
        $script:Elevation.Process = $process
        $script:Elevation.PipeName = $pipeName
        $script:Elevation.Token = $token
        $script:Elevation.LastError = ''
        Write-AppLog 'Requested administrator approval for the elevated helper'
        return $true
    } catch {
        $script:Elevation.Started = $false
        $script:Elevation.Ready = $false
        $script:Elevation.LastError = $_.Exception.Message
        Write-AppLog "Elevation request failed: $($_.Exception.Message)"
        return $false
    }
}

function Set-ElevationStatus {
    param([bool]$Ready, [switch]$Lost)

    $label = $script:AdminStatusText
    if ($null -eq $label -or $null -eq $script:Window -or $script:IsAdmin) { return }

    if ($Ready) {
        $label.Text = 'Administrator helper connected'
        $label.Foreground = Get-Resource 'SuccessText'
    } elseif ($Lost) {
        $label.Text = 'Administrator helper closed - the next admin change asks again'
        $label.Foreground = Get-Resource 'WarnGlyph'
    } else {
        $label.Text = 'Standard user - admin tweaks ask for approval'
        $label.Foreground = Get-Resource 'TextTertiary'
    }
}

function Test-ElevatedProcessExited {
    $process = $script:Elevation.Process
    if ($null -eq $process) { return $false }
    try { return [bool]$process.HasExited } catch { return $false }
}

function Invoke-ElevatedRequest {
    param([hashtable]$Payload, [int]$ConnectTimeoutMs = 3000)

    if (-not $script:Elevation.Started) {
        return @{ ok = $false; error = 'The elevated helper is not running.' }
    }

    $client = $null
    try {
        $client = New-Object System.IO.Pipes.NamedPipeClientStream(
            '.', $script:Elevation.PipeName, [System.IO.Pipes.PipeDirection]::InOut)
        $client.Connect($ConnectTimeoutMs)

        $Payload['token'] = $script:Elevation.Token
        $writer = New-Object System.IO.StreamWriter($client, [System.Text.Encoding]::UTF8)
        $writer.AutoFlush = $true
        $writer.WriteLine(($Payload | ConvertTo-Json -Compress))

        $reader = New-Object System.IO.StreamReader($client, [System.Text.Encoding]::UTF8)
        $line = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) {
            return @{ ok = $false; error = 'The elevated helper closed the connection without answering.' }
        }

        $result = $line | ConvertFrom-Json
        return @{ ok = [bool]$result.ok; error = [string]$result.error; message = [string]$result.message }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    } finally {
        if ($null -ne $client) { $client.Dispose() }
    }
}

# Pumps the WPF dispatcher while waiting for the user to approve UAC, so the window
# stays painted instead of appearing frozen.
function Wait-ForElevation {
    param([int]$TimeoutMs = 30000)

    if (-not $script:Elevation.Started) { return $false }

    $script:ElevationProbeOk = $false
    $script:ElevationDeadline = (Get-Date).AddMilliseconds($TimeoutMs)

    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $script:Elevation.Frame = $frame

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $timer.Add_Tick({
        param($sender, $eventArgs)

        if (Test-ElevatedProcessExited) {
            $script:Elevation.LastError = 'The elevated helper stopped before it could connect.'
            $script:ElevationProbeOk = $false
            $script:Elevation.Frame.Continue = $false
            $sender.Stop()
            return
        }

        if ((Get-Date) -gt $script:ElevationDeadline) {
            $script:Elevation.LastError = 'Timed out waiting for administrator approval.'
            $script:ElevationProbeOk = $false
            $script:Elevation.Frame.Continue = $false
            $sender.Stop()
            return
        }

        $probe = Invoke-ElevatedRequest -Payload @{ action = 'ping' } -ConnectTimeoutMs 400
        if ($probe.ok) {
            $script:ElevationProbeOk = $true
            $script:Elevation.Frame.Continue = $false
            $sender.Stop()
        }
    })

    # Dim the content while waiting so a second click cannot start another wait.
    $content = $null
    try { if ($null -ne $script:Window) { $content = $script:Window.Content } } catch { }
    if ($null -ne $content) { $content.IsEnabled = $false }

    $timer.Start()
    try {
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    } finally {
        $timer.Stop()
        if ($null -ne $content) { try { $content.IsEnabled = $true } catch { } }
        $script:Elevation.Frame = $null
    }

    return [bool]$script:ElevationProbeOk
}

function Ensure-ElevatedHelper {
    if ($script:IsAdmin) { return $true }
    if ($script:Elevation.Ready) { return $true }

    if (-not $script:Elevation.Started) {
        if (-not (Start-ElevatedHelper)) { return $false }
    }

    Show-Toast -Message 'Approve the administrator prompt to apply this change.' -Kind 'info'
    $ready = Wait-ForElevation -TimeoutMs 30000
    $script:Elevation.Ready = $ready
    if (-not $ready) {
        # A dead or timed-out helper must be restarted from scratch next time.
        Clear-ElevationSession -Lost
    } else {
        Set-ElevationStatus -Ready $true
    }
    return $ready
}

function Clear-ElevationSession {
    param([switch]$Lost)

    $script:Elevation.Started = $false
    $script:Elevation.Ready = $false
    $script:Elevation.Process = $null
    $script:Elevation.PipeName = ''
    $script:Elevation.Token = ''
    Set-ElevationStatus -Ready $false -Lost:$Lost
}

function Close-ElevatedHelper {
    if ($script:Elevation.Frame) { $script:Elevation.Frame.Continue = $false }
    if ($script:Elevation.Started) {
        try { $null = Invoke-ElevatedRequest -Payload @{ action = 'shutdown' } -ConnectTimeoutMs 800 } catch { }
    }
    Clear-ElevationSession
}

# A helper that has exited or lost its pipe needs a fresh approval, not a retry.
function Test-ElevationFailure {
    param($Response)

    if ($Response.needsApproval) { return $false }
    if (Test-ElevatedProcessExited) { return $true }

    $errorText = [string]$Response.error
    if ($errorText -match 'pipe|connect|not running|closed the connection|broken|not exist') { return $true }
    return $false
}

# Sends a request to the helper, restarting the session once if the helper died.
function Invoke-ElevatedAction {
    param([hashtable]$Payload)

    if (-not (Ensure-ElevatedHelper)) {
        return @{ ok = $false; error = 'Administrator approval was not granted.'; needsApproval = $true }
    }

    $response = Invoke-ElevatedRequest -Payload $Payload -ConnectTimeoutMs 5000
    if ($response.ok) { return $response }

    if (-not (Test-ElevationFailure -Response $response)) {
        $response['needsApproval'] = $false
        return $response
    }

    Write-AppLog 'Elevated helper connection failed; requesting approval again'
    Clear-ElevationSession -Lost
    if (-not (Ensure-ElevatedHelper)) {
        return @{ ok = $false; error = 'Administrator approval was not granted.'; needsApproval = $true }
    }

    $retry = Invoke-ElevatedRequest -Payload $Payload -ConnectTimeoutMs 5000
    if (-not $retry.ok) { $retry['needsApproval'] = $false }
    return $retry
}

# Runs an admin tweak change through the helper when the app is not elevated.
function Invoke-ElevatedTweakAction {
    param($Tweak, [string]$Action, [bool]$TurnOn = $false)

    $payload = @{ action = $Action; id = $Tweak.Id }
    if ($Action -eq 'apply') { $payload['on'] = $TurnOn }
    return Invoke-ElevatedAction -Payload $payload
}
