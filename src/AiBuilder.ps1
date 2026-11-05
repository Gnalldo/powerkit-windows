# AiBuilder.ps1 - the "New action" builder: API key storage, AI drafting, validation
# and the custom catalog that user-generated cards live in.

$script:AiDefaultBase = 'https://api.z.ai/api/paas/v4'
# One of Z.ai's genuinely free models ($0 in, $0 out); see README for alternatives.
$script:AiDefaultModel = 'glm-4.7-flash'
$script:AiKeyPath = Join-Path $script:AppDataDir 'ai-key.dat'
$script:CustomCatalogPath = Join-Path $script:AppDataDir 'custom.json'
$script:AiPending = $null
$script:CustomCards = @{}
$script:MaxButton = $null
$script:HeaderSearch = $null
$script:NewActionButton = $null

$script:AiTweakGroups = @('explorer', 'taskbar', 'appearance', 'performance', 'privacy', 'system')
$script:AiCommandGroups = @('power', 'tools')
$script:AiKinds = @('DWord', 'QWord', 'String', 'ExpandString')
$script:AiHives = @('HKCU', 'HKLM')
$script:AiRisks = @('safe', 'caution', 'advanced')
$script:AiRestarts = @('explorer', 'signout', 'reboot')

# Only handlers that already exist in Get-HandlerAction may be used, so a drafted
# command can never introduce new code - it can only press an existing button.
$script:AiAllowedHandlers = @(
    'Restart', 'Shutdown', 'SignOut', 'Sleep', 'Hibernate', 'Lock', 'CancelShutdown', 'Firmware',
    'RestartExplorer', 'PlanHigh', 'PlanBalanced', 'PlanUltimate', 'HibernateOff', 'HibernateOn',
    'OpenTaskmgr', 'OpenSettings', 'OpenServices', 'OpenDevMgmt', 'OpenCleanmgr', 'OpenSysdm',
    'OpenPowerOptions', 'OpenRegedit', 'OpenControl', 'OpenNetwork', 'OpenWindowsUpdate',
    'OpenStartupApps', 'OpenMsinfo', 'CreateGodMode', 'FlushDns', 'ClearTemp',
    'OpenCmd', 'OpenPwsh', 'OpenWindowsTerminal'
)

# Registry areas that a drafted entry may never touch, whatever the model says.
$script:AiDeniedPaths = @(
    '\CurrentControlSet\Services',
    '\CurrentControlSet\Control\Session Manager',
    '\SAM',
    '\SECURITY',
    '\Winlogon',
    'Image File Execution Options',
    'CurrentVersion\Run',
    'CurrentVersion\RunOnce',
    '\SafeBoot',
    'Classes\.exe', 'Classes\.bat', 'Classes\.cmd', 'Classes\.com', 'Classes\.ps1'
)

# ---------------------------------------------------------------- key storage

function Initialize-AiProtection {
    try { Add-Type -AssemblyName System.Security -ErrorAction Stop } catch { }
}

function Get-AiApiKey {
    if (-not (Test-Path -LiteralPath $script:AiKeyPath)) { return '' }
    Initialize-AiProtection
    try {
        $bytes = [System.IO.File]::ReadAllBytes($script:AiKeyPath)
        $plain = [System.Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [System.Text.Encoding]::UTF8.GetString($plain)
    } catch {
        Write-AppLog ("Could not read the saved API key: {0}" -f $_.Exception.Message)
        return ''
    }
}

function Save-AiApiKey {
    param([string]$Key)

    Initialize-AppData
    if ([string]::IsNullOrWhiteSpace($Key)) {
        if (Test-Path -LiteralPath $script:AiKeyPath) { Remove-Item -LiteralPath $script:AiKeyPath -Force -ErrorAction SilentlyContinue }
        return $true
    }

    Initialize-AiProtection
    try {
        $plain = [System.Text.Encoding]::UTF8.GetBytes($Key.Trim())
        $data = [System.Security.Cryptography.ProtectedData]::Protect($plain, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        [System.IO.File]::WriteAllBytes($script:AiKeyPath, $data)
        return $true
    } catch {
        Write-AppLog ("Could not save the API key: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Test-AiConfigured {
    if (-not [string]::IsNullOrWhiteSpace((Get-AiApiKey))) { return $true }
    # A server running on this PC (Ollama, LM Studio) needs no key at all.
    return (Test-AiLocalEndpoint)
}

function Test-AiLocalEndpoint {
    param([string]$Base = '')

    if (-not $Base) { $Base = Get-AiBaseUrl }
    try {
        $uri = [System.Uri]$Base
    } catch {
        return $false
    }

    $hostName = $uri.Host.ToLowerInvariant()
    if ($hostName -eq 'localhost' -or $hostName -eq '::1') { return $true }

    # An Ollama or LM Studio box on the same network needs no key either, so accept
    # private addresses and names that do not look like a public domain.
    $address = $null
    if ([System.Net.IPAddress]::TryParse($hostName, [ref]$address)) {
        if ([System.Net.IPAddress]::IsLoopback($address)) { return $true }
        $bytes = $address.GetAddressBytes()
        if ($bytes.Length -eq 4) {
            if ($bytes[0] -eq 10) { return $true }
            if ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) { return $true }
            if ($bytes[0] -eq 192 -and $bytes[1] -eq 168) { return $true }
            if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return $true }
        }
        return $false
    }
    return (-not $hostName.Contains('.'))
}

function Get-AiSetting {
    param([string]$Name, [string]$Default = '')
    if ($script:Settings.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace([string]$script:Settings[$Name])) {
        return [string]$script:Settings[$Name]
    }
    return $Default
}

function Get-AiBaseUrl { return (Get-AiSetting -Name 'ai_base' -Default $script:AiDefaultBase) }
function Get-AiModel { return (Get-AiSetting -Name 'ai_model' -Default $script:AiDefaultModel) }

# ---------------------------------------------------------------- validation

function Test-CustomEntry {
    param($Raw)

    if ($null -eq $Raw) { return @{ Ok = $false; Error = 'The reply was empty.' } }
    if ($Raw.PSObject.Properties['error'] -and $Raw.error) {
        return @{ Ok = $false; Error = [string]$Raw.error }
    }

    $kind = ([string]$Raw.kind).Trim().ToLowerInvariant()
    if ($kind -ne 'tweak' -and $kind -ne 'command') {
        return @{ Ok = $false; Error = 'The reply was neither a tweak nor a command.' }
    }

    $id = ([string]$Raw.id).Trim().ToLowerInvariant()
    if ($id -notmatch '^[a-z][a-z0-9-]{2,39}$') {
        return @{ Ok = $false; Error = ("The id '{0}' is not a lowercase slug of 3 to 40 characters." -f $id) }
    }
    if ((Get-TweakById -Id $id) -or (Get-CommandById -Id $id)) {
        return @{ Ok = $false; Error = ("Something with the id '{0}' already exists." -f $id) }
    }

    $group = ([string]$Raw.group).Trim().ToLowerInvariant()
    $allowedGroups = if ($kind -eq 'tweak') { $script:AiTweakGroups } else { $script:AiCommandGroups }
    if ($allowedGroups -notcontains $group) {
        return @{ Ok = $false; Error = ("The group '{0}' is not valid for a {1}." -f $group, $kind) }
    }

    $title = ([string]$Raw.title).Trim()
    if ($title.Length -lt 3 -or $title.Length -gt 60) {
        return @{ Ok = $false; Error = 'The title must be between 3 and 60 characters.' }
    }

    $desc = ([string]$Raw.desc).Trim()
    if ($desc.Length -lt 10 -or $desc.Length -gt 240) {
        return @{ Ok = $false; Error = 'The description must be between 10 and 240 characters.' }
    }

    $risk = ([string]$Raw.risk).Trim().ToLowerInvariant()
    if ($script:AiRisks -notcontains $risk) { $risk = 'caution' }

    $warning = ''
    if ($null -ne $Raw.warning) { $warning = ([string]$Raw.warning).Trim() }
    if ($warning.Length -gt 300) { $warning = $warning.Substring(0, 300) }

    $entry = @{
        Id     = $id
        Group  = $group
        Title  = $title
        Desc   = $desc
        Risk   = $risk
        Custom = $true
    }

    if ($kind -eq 'command') {
        $handler = ([string]$Raw.handler).Trim()
        if ($script:AiAllowedHandlers -notcontains $handler) {
            return @{ Ok = $false; Error = ("'{0}' is not a handler PowerKit can run." -f $handler) }
        }
        $entry['Handler'] = $handler
        if ($warning) { $entry['Warning'] = $warning }
        if ($risk -ne 'safe') {
            $entry['Confirm'] = 'This command was drafted by the AI builder. Run it now?'
            $entry['ConfirmLabel'] = 'Run'
        }
        return @{ Ok = $true; Entry = $entry }
    }

    $restart = ''
    if ($null -ne $Raw.restart) { $restart = ([string]$Raw.restart).Trim().ToLowerInvariant() }
    if ($restart -and $script:AiRestarts -notcontains $restart) { $restart = '' }
    $entry['Restart'] = $(if ($restart) { $restart } else { $null })

    $values = @($Raw.values)
    if ($values.Count -lt 1 -or $values.Count -gt 6) {
        return @{ Ok = $false; Error = 'A tweak needs between 1 and 6 registry values.' }
    }

    $normalized = @()
    $seen = @{}
    $needsAdmin = $false

    foreach ($value in $values) {
        if ($null -eq $value) { return @{ Ok = $false; Error = 'One of the registry values was empty.' } }

        $hive = ([string]$value.hive).Trim().ToUpperInvariant()
        if ($script:AiHives -notcontains $hive) {
            return @{ Ok = $false; Error = ("The hive '{0}' is not one PowerKit writes." -f $hive) }
        }

        $path = ([string]$value.path).Trim()
        if (-not $path) { return @{ Ok = $false; Error = 'A registry value has no path.' } }
        if ($path -notmatch '^(Software|System|Control Panel)\\') {
            return @{ Ok = $false; Error = ("The path '{0}' is outside the keys PowerKit manages." -f $path) }
        }
        foreach ($denied in $script:AiDeniedPaths) {
            if ($path.IndexOf($denied, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return @{ Ok = $false; Error = ("The path '{0}' touches a key PowerKit refuses to write ({1})." -f $path, $denied) }
            }
        }

        $name = [string]$value.name
        if ($name -match '\\') { return @{ Ok = $false; Error = ("The value name '{0}' contains a backslash." -f $name) } }
        if ($name.Length -gt 255) { return @{ Ok = $false; Error = 'A value name is longer than 255 characters.' } }

        $valueKind = ([string]$value.kind).Trim()
        if ($script:AiKinds -notcontains $valueKind) {
            return @{ Ok = $false; Error = ("The kind '{0}' is not one PowerKit writes." -f $valueKind) }
        }

        $onValue = $null
        $offValue = $null

        if ($valueKind -eq 'DWord' -or $valueKind -eq 'QWord') {
            foreach ($candidate in @($value.on, $value.off)) {
                if ($null -eq $candidate) { continue }
                $number = 0
                if (-not [int]::TryParse(([string]$candidate).Trim(), [ref]$number)) {
                    return @{ Ok = $false; Error = ("'{0}' is not a number for a {1} value." -f $candidate, $valueKind) }
                }
                if ($number -lt 0 -or $number -gt 2147483647) {
                    return @{ Ok = $false; Error = ('The number {0} is out of range.' -f $number) }
                }
            }
            if ($null -ne $value.on) { $onValue = [int](([string]$value.on).Trim()) }
            if ($null -ne $value.off) { $offValue = [int](([string]$value.off).Trim()) }
        } else {
            if ($null -ne $value.on) {
                $onValue = [string]$value.on
                if ($onValue.Length -gt 260) { return @{ Ok = $false; Error = 'A string value is longer than 260 characters.' } }
            }
            if ($null -ne $value.off) {
                $offValue = [string]$value.off
                if ($offValue.Length -gt 260) { return @{ Ok = $false; Error = 'A string value is longer than 260 characters.' } }
            }
        }

        $signature = ('{0}|{1}|{2}' -f $hive, $path.ToLowerInvariant(), $name.ToLowerInvariant())
        if ($seen.ContainsKey($signature)) {
            return @{ Ok = $false; Error = ("'{0}\{1}' is written twice." -f $path, $name) }
        }
        $seen[$signature] = $true

        if ($hive -eq 'HKLM') { $needsAdmin = $true }

        $normalized += @{
            Hive = $hive
            Path = $path
            Name = $name
            Kind = $valueKind
            On   = $onValue
            Off  = $offValue
        }
    }

    $entry['Values'] = $normalized
    if ($needsAdmin) { $entry['Admin'] = $true }
    if ($warning) { $entry['Warning'] = $warning }
    return @{ Ok = $true; Entry = $entry }
}

# ---------------------------------------------------------------- custom catalog

function ConvertTo-CatalogEntry {
    param($Raw)

    if ($null -eq $Raw) { return $null }
    $entry = @{
        Id     = [string]$Raw.id
        Group  = [string]$Raw.group
        Title  = [string]$Raw.title
        Desc   = [string]$Raw.desc
        Risk   = [string]$Raw.risk
        Custom = $true
    }
    if (-not $entry.Id) { return $null }

    if ($null -ne $Raw.PSObject.Properties['warning'] -and $Raw.warning) { $entry['Warning'] = [string]$Raw.warning }

    if ($null -ne $Raw.PSObject.Properties['handler'] -and $Raw.handler) {
        $entry['Handler'] = [string]$Raw.handler
        if ($null -ne $Raw.PSObject.Properties['confirm'] -and $Raw.confirm) { $entry['Confirm'] = [string]$Raw.confirm }
        if ($null -ne $Raw.PSObject.Properties['confirmlabel'] -and $Raw.confirmlabel) { $entry['ConfirmLabel'] = [string]$Raw.confirmlabel }
        return $entry
    }

    $entry['Restart'] = $null
    if ($null -ne $Raw.PSObject.Properties['restart'] -and $Raw.restart) { $entry['Restart'] = [string]$Raw.restart }
    if ($null -ne $Raw.PSObject.Properties['admin'] -and $Raw.admin) { $entry['Admin'] = $true }

    $values = @()
    foreach ($value in @($Raw.values)) {
        if ($null -eq $value) { continue }
        $values += @{
            Hive = [string]$value.hive
            Path = [string]$value.path
            Name = [string]$value.name
            Kind = [string]$value.kind
            On   = $value.on
            Off  = $value.off
        }
    }
    if ($values.Count -eq 0) { return $null }
    $entry['Values'] = $values
    return $entry
}

function Get-CustomCatalogEntries {
    if (-not (Test-Path -LiteralPath $script:CustomCatalogPath)) { return @() }
    try {
        $raw = [System.IO.File]::ReadAllText($script:CustomCatalogPath)
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $doc = ConvertFrom-Json $raw
        return @($doc.Actions)
    } catch {
        return @()
    }
}

function Load-CustomCatalog {
    if (-not (Test-Path -LiteralPath $script:CustomCatalogPath)) { return }

    try {
        $raw = Get-Content -LiteralPath $script:CustomCatalogPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return }
        $doc = $raw | ConvertFrom-Json
        foreach ($item in @($doc.actions)) {
            $entry = ConvertTo-CatalogEntry -Raw $item
            if ($null -eq $entry) { continue }
            if ((Get-TweakById -Id $entry.Id) -or (Get-CommandById -Id $entry.Id)) { continue }
            if ($entry.ContainsKey('Values')) {
                $script:TweakDefs += $entry
            } else {
                $script:CommandDefs += $entry
            }
        }
    } catch {
        Write-AppLog ("Could not read custom.json: {0}" -f $_.Exception.Message)
    }
}

function Save-CustomCatalog {
    Initialize-AppData
    $items = @()

    foreach ($tweak in $script:TweakDefs) {
        if (-not ($tweak.ContainsKey('Custom') -and $tweak.Custom)) { continue }
        $items += [ordered]@{
            kind    = 'tweak'
            id      = $tweak.Id
            group   = $tweak.Group
            title   = $tweak.Title
            desc    = $tweak.Desc
            risk    = $tweak.Risk
            restart = $(if ($tweak.Restart) { $tweak.Restart } else { $null })
            warning = $(if ($tweak.ContainsKey('Warning') -and $tweak.Warning) { $tweak.Warning } else { '' })
            values  = @($tweak.Values | ForEach-Object {
                    [ordered]@{ hive = $_.Hive; path = $_.Path; name = $_.Name; kind = $_.Kind; on = $_.On; off = $_.Off }
                })
        }
    }

    foreach ($command in $script:CommandDefs) {
        if (-not ($command.ContainsKey('Custom') -and $command.Custom)) { continue }
        $items += [ordered]@{
            kind         = 'command'
            id           = $command.Id
            group        = $command.Group
            title        = $command.Title
            desc         = $command.Desc
            risk         = $command.Risk
            handler      = $command.Handler
            confirm      = $(if ($command.ContainsKey('Confirm')) { $command.Confirm } else { '' })
            confirmlabel = $(if ($command.ContainsKey('ConfirmLabel')) { $command.ConfirmLabel } else { '' })
            warning      = $(if ($command.ContainsKey('Warning') -and $command.Warning) { $command.Warning } else { '' })
        }
    }

    $doc = [ordered]@{ Version = 1; Actions = $items }
    $json = ConvertTo-Json -InputObject $doc -Depth 8
    [System.IO.File]::WriteAllText($script:CustomCatalogPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------- prompting

function Get-AiSystemPrompt {
    $tweakGroups = $script:AiTweakGroups -join ', '
    $commandGroups = $script:AiCommandGroups -join ', '
    $handlers = $script:AiAllowedHandlers -join ', '
    $existing = @($script:TweakDefs | ForEach-Object { $_.Id }) + @($script:CommandDefs | ForEach-Object { $_.Id })
    $existingText = ($existing | Select-Object -First 120) -join ', '

    return @"
You draft entries for PowerKit, a Windows 11 registry tweak tool. Reply with ONE JSON object and nothing else - no prose, no markdown fences.

A registry tweak looks like this:
{"kind":"tweak","id":"kebab-case-id","group":"<group>","title":"under 60 chars","desc":"one or two plain sentences","risk":"safe|caution|advanced","restart":"explorer|signout|reboot|null","warning":"short warning or empty string","values":[{"hive":"HKCU","path":"Software\\Microsoft\\Windows\\...","name":"ValueName","kind":"DWord","on":0,"off":1}]}

A one-click command looks like this:
{"kind":"command","id":"kebab-case-id","group":"power|tools","title":"...","desc":"...","risk":"safe|caution|advanced","warning":"","handler":"<existing handler>"}

Rules:
- Tweak groups: $tweakGroups. Command groups: $commandGroups.
- kind must be one of DWord, QWord, String, ExpandString. on/off are whole numbers for DWord and QWord, strings for String and ExpandString, and null means delete the value.
- 1 to 6 values. Use HKCU when possible; HKLM means the user must approve an administrator prompt.
- Never write keys under CurrentControlSet\Services, Session Manager, SAM, SECURITY, Winlogon, Image File Execution Options, CurrentVersion\Run or RunOnce, SafeBoot, or file association keys.
- Do not reuse an existing id. Existing ids: $existingText
- A command handler must be one of: $handlers
- If the request cannot be expressed with registry values or those handlers, reply {"error":"one sentence explaining why"}.
"@
}

$script:AiRequestScript = @'
param([string]$BaseUrl, [string]$Model, [string]$ApiKey, [string]$SystemPrompt, [string]$UserPrompt)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$body = @{
    model       = $Model
    temperature = 0.2
    messages    = @(
        @{ role = 'system'; content = $SystemPrompt }
        @{ role = 'user';   content = $UserPrompt }
    )
} | ConvertTo-Json -Depth 8

$headers = @{}
if (-not [string]::IsNullOrWhiteSpace($ApiKey)) { $headers['Authorization'] = 'Bearer ' + $ApiKey }
$uri = $BaseUrl.TrimEnd('/') + '/chat/completions'

try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
        -ContentType 'application/json; charset=utf-8' -TimeoutSec 60 -ErrorAction Stop
} catch {
    $detail = $_.Exception.Message
    try {
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $detail = $reader.ReadToEnd()
            $reader.Dispose()
        }
    } catch { }
    throw $detail
}

$content = ''
try { $content = [string]$response.choices[0].message.content } catch { }
if (-not $content) { throw 'The endpoint replied without any content.' }
return $content
'@

# A one-prompt check used by the Settings dialog: it validates the key, endpoint and
# model without drafting anything, and reports what the endpoint actually said.
$script:AiTestPending = $null

$script:AiTestScript = @'
param([string]$BaseUrl, [string]$Model, [string]$ApiKey)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$body = @{
    model       = $Model
    temperature = 0
    max_tokens  = 8
    messages    = @(@{ role = 'user'; content = 'Reply with the single word: ready' })
} | ConvertTo-Json -Depth 6

$headers = @{}
if (-not [string]::IsNullOrWhiteSpace($ApiKey)) { $headers['Authorization'] = 'Bearer ' + $ApiKey }
$uri = $BaseUrl.TrimEnd('/') + '/chat/completions'

$watch = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
        -ContentType 'application/json; charset=utf-8' -TimeoutSec 30 -ErrorAction Stop
} catch {
    $detail = $_.Exception.Message
    try {
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $detail = $reader.ReadToEnd()
            $reader.Dispose()
        }
    } catch { }
    $watch.Stop()
    return @{ ok = $false; error = $detail; ms = [int]$watch.ElapsedMilliseconds }
}
$watch.Stop()

$served = ''
try { if ($response.model) { $served = [string]$response.model } } catch { }
if (-not $served) { $served = $Model }
return @{ ok = $true; model = $served; ms = [int]$watch.ElapsedMilliseconds }
'@

function Start-AiConnectionTest {
    param([string]$Base, [string]$Model, [string]$Key)

    $ps = [powershell]::Create()
    [void]$ps.AddScript($script:AiTestScript)
    [void]$ps.AddParameter('BaseUrl', $Base)
    [void]$ps.AddParameter('Model', $Model)
    [void]$ps.AddParameter('ApiKey', $Key)

    $script:AiTestPending = @{ Ps = $ps; Handle = $ps.BeginInvoke() }
    return $script:AiTestPending
}

function Complete-AiConnectionTest {
    param($Pending)

    if ($null -eq $Pending) { return @{ ok = $false; error = 'The test was not started.' } }

    $result = $null
    $failure = ''
    try {
        $output = $Pending.Ps.EndInvoke($Pending.Handle)
        if ($output -and $output.Count -gt 0) { $result = $output[$output.Count - 1] }
    } catch {
        $failure = $_.Exception.Message
        if ($null -ne $_.Exception.InnerException -and $_.Exception.InnerException.Message) {
            $failure = $_.Exception.InnerException.Message
        }
    } finally {
        try { $Pending.Ps.Dispose() } catch { }
        $script:AiTestPending = $null
    }

    if ($failure) { return @{ ok = $false; error = $failure } }
    if ($null -eq $result) { return @{ ok = $false; error = 'The endpoint returned nothing.' } }
    return $result
}

function Get-AiRepairRequest {
    param([string]$Request, [string]$Error)

    return ($Request + "`nYour previous reply was rejected: " + $Error + ' Reply again with one JSON object that follows every rule.')
}

function Start-AiDraft {
    param([string]$Request, [int]$Attempt = 1)

    $key = Get-AiApiKey
    if ([string]::IsNullOrWhiteSpace($key) -and -not (Test-AiLocalEndpoint)) { return $null }

    $ps = [powershell]::Create()
    [void]$ps.AddScript($script:AiRequestScript)
    [void]$ps.AddParameter('BaseUrl', (Get-AiBaseUrl))
    [void]$ps.AddParameter('Model', (Get-AiModel))
    [void]$ps.AddParameter('ApiKey', $key)
    [void]$ps.AddParameter('SystemPrompt', (Get-AiSystemPrompt))
    [void]$ps.AddParameter('UserPrompt', $Request)

    $pending = @{ Ps = $ps; Handle = $ps.BeginInvoke(); Started = (Get-Date); Request = $Request; Attempt = $Attempt }
    $script:AiPending = $pending
    return $pending
}

function Complete-AiDraft {
    param($Pending)

    if ($null -eq $Pending) { return @{ Ok = $false; Error = 'The request was not started.' } }

    $text = ''
    $failure = ''
    try {
        $output = $Pending.Ps.EndInvoke($Pending.Handle)
        if ($output -and $output.Count -gt 0) { $text = [string]$output[$output.Count - 1] }
    } catch {
        $failure = $_.Exception.Message
        if ($null -ne $_.Exception.InnerException -and $_.Exception.InnerException.Message) {
            $failure = $_.Exception.InnerException.Message
        }
    } finally {
        try { $Pending.Ps.Dispose() } catch { }
        $script:AiPending = $null
    }

    if ($failure) { return @{ Ok = $false; Error = $failure } }

    $json = $text.Trim()
    if ($json.StartsWith('```')) {
        $json = $json -replace '^```[a-zA-Z]*', ''
        $json = $json -replace '```$', ''
        $json = $json.Trim()
    }
    if (-not $json) { return @{ Ok = $false; Error = 'The model replied with nothing.' } }

    try {
        $parsed = $json | ConvertFrom-Json
    } catch {
        return @{ Ok = $false; Error = ("The model did not reply with JSON: {0}" -f $text) }
    }

    return @{ Ok = $true; Raw = $parsed; Text = $text }
}

# ---------------------------------------------------------------- catalog edits

function Save-CustomEntry {
    param($Entry)

    if ($Entry.ContainsKey('Values')) {
        $script:TweakDefs += $Entry
    } else {
        $script:CommandDefs += $Entry
    }
    Save-CustomCatalog

    $detail = if ($Entry.ContainsKey('Values')) {
        ($Entry.Values | ForEach-Object { '{0}\{1}\{2}' -f $_.Hive, $_.Path, $_.Name }) -join '; '
    } else {
        'handler ' + $Entry.Handler
    }
    Write-AppLog ("CUSTOM added {0} ({1}) - {2}" -f $Entry.Id, $Entry.Group, $detail)
    Add-CustomEntryToUi -Entry $Entry
}

function Add-CustomEntryToUi {
    param($Entry)

    $section = $null
    foreach ($item in $script:Sections) { if ($item.Group -eq $Entry.Group) { $section = $item } }
    if ($null -eq $section) { return }

    $groupTitle = ''
    foreach ($group in $script:GroupDefs) { if ($group.Id -eq $Entry.Group) { $groupTitle = $group.Title } }

    if ($Entry.ContainsKey('Values')) {
        $card = New-TweakCard -Tweak $Entry
        [void]$section.Panel.Children.Add($card)
        [void]$section.Entries.Add(@{
            Card       = $card
            SearchText = ($Entry.Title + ' ' + $Entry.Desc + ' ' + $groupTitle).ToLowerInvariant()
        })
        Update-TweakVisuals -Tweak $Entry
    } else {
        $card = New-CommandCard -Command $Entry
        [void]$section.Panel.Children.Add($card)
        [void]$section.Entries.Add(@{
            Card       = $card
            SearchText = ($Entry.Title + ' ' + $Entry.Desc + ' ' + $groupTitle).ToLowerInvariant()
        })
    }

    $script:CustomCards[$Entry.Id] = @{ Card = $card; Section = $section }
    Update-NavCounts
    Update-SectionCounts
    Update-Filter
    Update-GridColumns
    try { $card.BringIntoView() } catch { }
}

function Remove-CustomAction {
    param([string]$Id)

    $entry = Get-TweakById -Id $Id
    $isTweak = $true
    if ($null -eq $entry) {
        $entry = Get-CommandById -Id $Id
        $isTweak = $false
    }
    if ($null -eq $entry) { return }

    $answer = Show-Dialog -Title ("Remove '{0}'?" -f $entry.Title) -Message 'This only removes the card from PowerKit. Nothing is written to the registry, and any value it already changed stays as it is.' -Primary 'Remove' -Secondary 'Cancel' -Danger
    if ($answer -ne 'primary') { return }

    if ($isTweak) {
        $script:TweakDefs = @($script:TweakDefs | Where-Object { $_.Id -ne $Id })
    } else {
        $script:CommandDefs = @($script:CommandDefs | Where-Object { $_.Id -ne $Id })
    }

    if ($script:CustomCards.ContainsKey($Id)) {
        $cardRef = $script:CustomCards[$Id]
        foreach ($section in $script:Sections) {
            if ($section.Group -ne $cardRef.Section.Group) { continue }
            $keep = @()
            foreach ($item in $section.Entries) { if ($item.Card -ne $cardRef.Card) { $keep += $item } }
            $section.Entries.Clear()
            foreach ($item in $keep) { [void]$section.Entries.Add($item) }
        }
        try { $cardRef.Card.Parent.Children.Remove($cardRef.Card) } catch { }
        [void]$script:CustomCards.Remove($Id)

        # Removing the card also drops its pin, so neither the pinned strip nor the
        # desktop menu keeps an entry that can no longer open anything.
        if ((Get-PinnedCards).Contains([string]$Id)) {
            [void](Get-PinnedCards).Remove([string]$Id)
            Save-PinnedCards
            Sync-PinnedSection
        }
    }

    if ($script:TweakCards.ContainsKey($Id)) { [void]$script:TweakCards.Remove($Id) }
    if ($script:CommandCards.ContainsKey($Id)) { [void]$script:CommandCards.Remove($Id) }

    Save-CustomCatalog
    Write-AppLog ("CUSTOM removed {0}" -f $Id)
    Refresh-AllVisuals
    Show-Toast -Message ("'{0}' removed from PowerKit" -f $entry.Title) -Kind 'success'
}

# ---------------------------------------------------------------- dialogs

function New-OverlayDialog {
    param([string]$Width = 480)

    $dialog = New-Object System.Windows.Window
    $dialog.WindowStyle = 'None'
    $dialog.AllowsTransparency = $true
    $dialog.Background = [System.Windows.Media.Brushes]::Transparent
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.SizeToContent = 'Height'
    $dialog.Width = $Width
    $dialog.ResizeMode = 'NoResize'
    $dialog.ShowInTaskbar = $false
    $dialog.FontFamily = $script:FontText
    [System.Windows.Media.TextOptions]::SetTextFormattingMode($dialog, 'Display')
    Add-AppResources -Resources $dialog.Resources -Mode $script:ThemeMode
    Register-ThemeWindow -Window $dialog
    if ($null -ne $script:Window) { $dialog.Owner = $script:Window }

    $card = New-Object System.Windows.Controls.Border
    $card.Background = Get-Resource 'WindowBg'
    $card.BorderBrush = Get-Resource 'BorderSubtle'
    $card.BorderThickness = New-Object System.Windows.Thickness(1)
    $card.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $card.Padding = New-Object System.Windows.Thickness(24, 20, 24, 18)
    $card.Margin = New-Object System.Windows.Thickness(14)

    $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
    $shadow.BlurRadius = 20
    $shadow.ShadowDepth = 4
    $shadow.Opacity = 0.4
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $card.Effect = $shadow

    $stack = New-Object System.Windows.Controls.StackPanel
    $card.Child = $stack
    $dialog.Content = $card

    $dialog.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            $sender.Tag = 'cancel'
            $sender.Close()
            $eventArgs.Handled = $true
        }
    })

    return @{ Window = $dialog; Stack = $stack }
}

function New-FieldLabel {
    param([string]$Text, [double]$Top = 12)
    $label = New-TextBlock -Text $Text -Size 11.5 -Weight 'SemiBold' -ColorKey 'TextSecondary'
    $label.Margin = New-Object System.Windows.Thickness(0, $Top, 0, 5)
    return $label
}

function New-SettingsDialog {
    $dialog = New-OverlayDialog -Width 520
    $window = $dialog.Window
    $stack = $dialog.Stack

    $title = New-TextBlock -Text 'Settings' -Size 16 -Weight 'SemiBold' -Font $script:FontDisplay
    [void]$stack.Children.Add($title)

    $hint = New-TextBlock -Text 'PowerKit sends your description to this endpoint and turns the reply into a card. Nothing is sent until you press Generate, and the key never leaves this PC unencrypted. A local endpoint such as Ollama (http://localhost:11434/v1) needs no key.' -Size 12 -ColorKey 'TextSecondary' -Wrap 'Wrap'
    $hint.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
    $hint.MaxWidth = 460
    [void]$stack.Children.Add($hint)

    [void]$stack.Children.Add((New-FieldLabel -Text 'API key' -Top 16))
    # A TextBox cannot mask its text, so the key field is a PasswordBox in a styled border.
    $keyBorder = New-Object System.Windows.Controls.Border
    $keyBorder.Background = Get-Resource 'InputBg'
    $keyBorder.BorderBrush = Get-Resource 'BorderSubtle'
    $keyBorder.BorderThickness = New-Object System.Windows.Thickness(1)
    $keyBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
    $keyBorder.Padding = New-Object System.Windows.Thickness(10, 7, 10, 7)
    $keyBox = New-Object System.Windows.Controls.PasswordBox
    $keyBox.Background = [System.Windows.Media.Brushes]::Transparent
    $keyBox.BorderThickness = New-Object System.Windows.Thickness(0)
    $keyBox.Foreground = Get-Resource 'TextPrimary'
    $keyBox.CaretBrush = Get-Resource 'TextPrimary'
    $keyBox.FontSize = 12.5
    $keyBox.ToolTip = 'Stored encrypted for your Windows account in %LOCALAPPDATA%\PowerKit\ai-key.dat'
    $keyBorder.Child = $keyBox
    [void]$stack.Children.Add($keyBorder)

    $saved = Test-AiConfigured
    $keyNote = New-TextBlock -Text $(if ($saved) { 'A key is saved. Leave this box empty to keep it.' } else { 'No key saved yet. Only a hosted endpoint needs one; a server on this PC or your own network does not.' }) -Size 10.5 -ColorKey 'TextTertiary' -Wrap 'Wrap'
    $keyNote.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
    [void]$stack.Children.Add($keyNote)

    # Straight to the key page: a key is free to create, but only the Flash ids are $0 per token.
    $keyLink = New-Object System.Windows.Controls.Button
    $keyLink.Style = Get-Resource 'BtnGhost'
    $keyLink.Content = 'Get a z.ai API key'
    $keyLink.HorizontalAlignment = 'Left'
    $keyLink.Margin = New-Object System.Windows.Thickness(-6, 4, 0, 0)
    $keyLink.ToolTip = 'Opens z.ai in your browser. Creating the key costs nothing, but the key is not a free plan: only glm-4.7-flash, glm-4.5-flash and glm-4.6v-flash are $0 per token. Every other model bills per token.'
    $keyLink.Add_Click({
        try { Start-Process 'https://z.ai/manage-apikey/apikey-list' } catch { Show-Toast -Message ('Could not open the browser: ' + $_.Exception.Message) -Kind 'error' }
    })
    [void]$stack.Children.Add($keyLink)

    [void]$stack.Children.Add((New-FieldLabel -Text 'Endpoint'))
    $baseBox = New-Object System.Windows.Controls.TextBox
    $baseBox.Style = Get-Resource 'InputTextBox'
    $baseBox.Text = Get-AiBaseUrl
    [void]$stack.Children.Add($baseBox)

    [void]$stack.Children.Add((New-FieldLabel -Text 'Model'))
    $modelBox = New-Object System.Windows.Controls.TextBox
    $modelBox.Style = Get-Resource 'InputTextBox'
    $modelBox.Text = Get-AiModel
    [void]$stack.Children.Add($modelBox)

    $testStatus = New-TextBlock -Text 'Press Test to send one short prompt with the values above. A test stores nothing.' -Size 11 -ColorKey 'TextTertiary' -Wrap 'Wrap'
    $testStatus.MaxWidth = 460
    $testStatus.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
    [void]$stack.Children.Add($testStatus)

    $buttons = New-Object System.Windows.Controls.Grid
    $bc1 = New-Object System.Windows.Controls.ColumnDefinition
    $bc1.Width = [System.Windows.GridLength]::new(1, 'Star')
    $bc2 = New-Object System.Windows.Controls.ColumnDefinition
    $bc2.Width = [System.Windows.GridLength]::Auto
    [void]$buttons.ColumnDefinitions.Add($bc1)
    [void]$buttons.ColumnDefinitions.Add($bc2)
    $buttons.Margin = New-Object System.Windows.Thickness(0, 20, 0, 0)
    [void]$stack.Children.Add($buttons)

    $remove = New-Object System.Windows.Controls.Button
    $remove.Style = Get-Resource 'BtnGhost'
    $remove.Content = 'Remove saved key'
    $remove.HorizontalAlignment = 'Left'
    $remove.Margin = New-Object System.Windows.Thickness(-6, 0, 0, 0)
    $remove.Add_Click({
        param($sender, $eventArgs)
        [void](Save-AiApiKey -Key '')
        Show-Toast -Message 'Saved API key removed' -Kind 'info'
        $window = [System.Windows.Window]::GetWindow($sender)
        if ($window) { $window.Tag = 'cancel'; $window.Close() }
    })
    [System.Windows.Controls.Grid]::SetColumn($remove, 0)
    [void]$buttons.Children.Add($remove)

    $right = New-Object System.Windows.Controls.StackPanel
    $right.Orientation = 'Horizontal'
    $right.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($right, 1)
    [void]$buttons.Children.Add($right)

    $test = New-Object System.Windows.Controls.Button
    $test.Style = Get-Resource 'BtnSecondary'
    $test.Content = 'Test'
    $test.MinWidth = 84
    $test.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $test.ToolTip = 'Send one short prompt to this endpoint and report what comes back'
    $test.Add_Click({
        param($sender, $eventArgs)
        if ($null -ne $script:AiTestPending) { return }

        $base = $baseBox.Text.Trim()
        $model = $modelBox.Text.Trim()
        $typed = $keyBox.Password.Trim()
        $key = if ($typed) { $typed } else { Get-AiApiKey }

        if (-not $base) {
            $testStatus.Text = 'Enter an endpoint first.'
            $testStatus.Foreground = Get-Resource 'DangerText'
            return
        }
        if (-not $model) {
            $testStatus.Text = 'Enter a model first.'
            $testStatus.Foreground = Get-Resource 'DangerText'
            return
        }
        if (-not $key -and -not (Test-AiLocalEndpoint -Base $base)) {
            $testStatus.Text = 'A hosted endpoint needs an API key. Paste one above first.'
            $testStatus.Foreground = Get-Resource 'DangerText'
            return
        }

        $testStatus.Text = ('Sending a test prompt to {0} ...' -f $model)
        $testStatus.Foreground = Get-Resource 'TextTertiary'
        $sender.IsEnabled = $false
        $script:AiTestPending = Start-AiConnectionTest -Base $base -Model $model -Key $key
        $testTimer.Start()
    })
    [void]$right.Children.Add($test)

    # Polling keeps the dialog responsive while the endpoint answers, and stops as
    # soon as the window closes.
    $testTimer = New-Object System.Windows.Threading.DispatcherTimer
    $testTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $testTimer.Add_Tick({
        param($sender, $eventArgs)
        $pending = $script:AiTestPending
        if ($null -eq $pending) { $sender.Stop(); $test.IsEnabled = $true; return }
        if (-not $pending.Handle.IsCompleted) { return }

        $sender.Stop()
        $result = Complete-AiConnectionTest -Pending $pending
        $test.IsEnabled = $true
        if ($result.ok) {
            $testStatus.Text = ('Connected. {0} answered in {1} ms. Press Save to keep these values.' -f $result.model, $result.ms)
            $testStatus.Foreground = Get-Resource 'SuccessText'
        } else {
            $detail = [string]$result.error
            if ($detail.Length -gt 260) { $detail = $detail.Substring(0, 260) + '...' }
            $testStatus.Text = ('No answer: ' + $detail)
            $testStatus.Foreground = Get-Resource 'DangerText'
        }
    })

    $window.Add_Closed({
        param($sender, $eventArgs)
        $testTimer.Stop()
        if ($null -ne $script:AiTestPending) {
            try { $script:AiTestPending.Ps.Stop() } catch { }
            try { $script:AiTestPending.Ps.Dispose() } catch { }
            $script:AiTestPending = $null
        }
    })

    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Style = Get-Resource 'BtnSecondary'
    $cancel.Content = 'Cancel'
    $cancel.MinWidth = 92
    $cancel.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $cancel.Add_Click({
        param($sender, $eventArgs)
        $window = [System.Windows.Window]::GetWindow($sender)
        if ($window) { $window.Tag = 'cancel'; $window.Close() }
    })
    [void]$right.Children.Add($cancel)

    $save = New-Object System.Windows.Controls.Button
    $save.Style = Get-Resource 'BtnPrimary'
    $save.Content = 'Save'
    $save.MinWidth = 92
    $save.Add_Click({
        param($sender, $eventArgs)
        $window = [System.Windows.Window]::GetWindow($sender)
        $ok = $true
        if ($keyBox.Password.Trim().Length -gt 0) {
            $ok = Save-AiApiKey -Key $keyBox.Password.Trim()
        }
        $script:Settings['ai_base'] = $baseBox.Text.Trim()
        $script:Settings['ai_model'] = $modelBox.Text.Trim()
        Save-AppSettings
        if ($window) { $window.Tag = $(if ($ok) { 'saved' } else { 'failed' }); $window.Close() }
    })
    [void]$right.Children.Add($save)

    $window.Tag = 'cancel'
    return @{ Window = $window; Test = $test; Status = $testStatus }
}

function Show-SettingsDialog {
    $dialog = New-SettingsDialog
    $window = $dialog.Window
    $window.Tag = 'cancel'
    [void]$window.ShowDialog()
    if ($window.Tag -eq 'saved') { Show-Toast -Message 'Settings saved' -Kind 'success' }
    elseif ($window.Tag -eq 'failed') { Show-Toast -Message 'The API key could not be saved' -Kind 'error' }
}

function Show-NewActionDialog {
    if (-not (Test-AiConfigured)) {
        $answer = Show-Dialog -Title 'An API key is needed' -Message "The AI builder sends your description to a model endpoint and turns the reply into a card. Add an API key in Settings first - it is stored encrypted for your Windows account." -Primary 'Open settings' -Secondary 'Cancel'
        if ($answer -eq 'primary') { Show-SettingsDialog }
        if (-not (Test-AiConfigured)) { return }
    }

    $dialog = New-OverlayDialog -Width 560
    $window = $dialog.Window
    $stack = $dialog.Stack

    $title = New-TextBlock -Text 'New action' -Size 16 -Weight 'SemiBold' -Font $script:FontDisplay
    [void]$stack.Children.Add($title)

    $hint = New-TextBlock -Text 'Describe the tweak or tool you want. It is drafted as a normal PowerKit card that you can inspect before it is added, and removed again at any time.' -Size 12 -ColorKey 'TextSecondary' -Wrap 'Wrap'
    $hint.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
    $hint.MaxWidth = 500
    [void]$stack.Children.Add($hint)

    $inputBorder = New-Object System.Windows.Controls.Border
    $inputBorder.Margin = New-Object System.Windows.Thickness(0, 14, 0, 0)
    $inputBorder.Child = $null
    $inputBox = New-Object System.Windows.Controls.TextBox
    $inputBox.Style = Get-Resource 'InputTextBox'
    $inputBox.AcceptsReturn = $true
    $inputBox.TextWrapping = 'Wrap'
    $inputBox.Height = 76
    $inputBox.VerticalContentAlignment = 'Top'
    $inputBox.ToolTip = 'For example: stop Windows searching the web from the Start menu'
    $inputBorder.Child = $inputBox
    [void]$stack.Children.Add($inputBorder)

    $statusRow = New-Object System.Windows.Controls.Grid
    $sc1 = New-Object System.Windows.Controls.ColumnDefinition
    $sc1.Width = [System.Windows.GridLength]::Auto
    $sc2 = New-Object System.Windows.Controls.ColumnDefinition
    $sc2.Width = [System.Windows.GridLength]::new(1, 'Star')
    [void]$statusRow.ColumnDefinitions.Add($sc1)
    [void]$statusRow.ColumnDefinitions.Add($sc2)
    $statusRow.Margin = New-Object System.Windows.Thickness(0, 12, 0, 0)
    [void]$stack.Children.Add($statusRow)

    $generate = New-Object System.Windows.Controls.Button
    $generate.Style = Get-Resource 'BtnPrimary'
    $generate.Content = 'Generate'
    $generate.MinWidth = 108
    $generate.HorizontalAlignment = 'Left'
    [void]$statusRow.Children.Add($generate)

    $status = New-TextBlock -Text ('Uses ' + (Get-AiModel)) -Size 11 -ColorKey 'TextTertiary' -Wrap 'Wrap'
    $status.VerticalAlignment = 'Center'
    $status.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($status, 1)
    [void]$statusRow.Children.Add($status)

    $preview = New-Object System.Windows.Controls.Border
    $preview.Background = Get-Resource 'CardBg'
    $preview.BorderBrush = Get-Resource 'BorderSubtle'
    $preview.BorderThickness = New-Object System.Windows.Thickness(1)
    $preview.CornerRadius = New-Object System.Windows.CornerRadius(6)
    $preview.Padding = New-Object System.Windows.Thickness(14, 12, 14, 12)
    $preview.Margin = New-Object System.Windows.Thickness(0, 14, 0, 0)
    $preview.Visibility = 'Collapsed'
    $previewBody = New-Object System.Windows.Controls.StackPanel
    $preview.Child = $previewBody
    [void]$stack.Children.Add($preview)

    $footer = New-Object System.Windows.Controls.StackPanel
    $footer.Orientation = 'Horizontal'
    $footer.HorizontalAlignment = 'Right'
    $footer.Margin = New-Object System.Windows.Thickness(0, 18, 0, 0)
    [void]$stack.Children.Add($footer)

    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Style = Get-Resource 'BtnSecondary'
    $cancel.Content = 'Close'
    $cancel.MinWidth = 92
    $cancel.Add_Click({
        param($sender, $eventArgs)
        $window = [System.Windows.Window]::GetWindow($sender)
        if ($window) { $window.Tag = 'cancel'; $window.Close() }
    })
    [void]$footer.Children.Add($cancel)

    $add = New-Object System.Windows.Controls.Button
    $add.Style = Get-Resource 'BtnPrimary'
    $add.Content = 'Add to PowerKit'
    $add.MinWidth = 132
    $add.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
    $add.Visibility = 'Collapsed'
    [void]$footer.Children.Add($add)

    $script:AiDraftEntry = $null
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)

    $generate.Add_Click({
        param($sender, $eventArgs)
        $text = $inputBox.Text.Trim()
        if ($text.Length -lt 6) {
            $status.Text = 'Describe the action in a few more words.'
            $status.Foreground = Get-Resource 'DangerText'
            return
        }
        $preview.Visibility = 'Collapsed'
        $add.Visibility = 'Collapsed'
        $sender.IsEnabled = $false
        $status.Foreground = Get-Resource 'TextTertiary'
        $status.Text = 'Drafting with ' + (Get-AiModel) + '...'

        $pending = Start-AiDraft -Request $text
        if ($null -eq $pending) {
            $sender.IsEnabled = $true
            $status.Text = 'No API key is saved. Open Settings to add one.'
            return
        }
        $timer.Start()
    })

    $timer.Add_Tick({
        param($sender, $eventArgs)
        $pending = $script:AiPending
        if ($null -eq $pending) { $timer.Stop(); $generate.IsEnabled = $true; return }
        if (-not $pending.Handle.IsCompleted) {
            $seconds = [int]((Get-Date) - $pending.Started).TotalSeconds
            $status.Text = ('Drafting with {0}... {1}s' -f (Get-AiModel), $seconds)
            return
        }
        $timer.Stop()
        $generate.IsEnabled = $true

        $result = Complete-AiDraft -Pending $pending
        if (-not $result.Ok -and $pending.Attempt -lt 2) {
            # A small local model usually slips on one rule and fixes it when told
            # what it got wrong, so give it one repair pass instead of failing.
            $next = Start-AiDraft -Request (Get-AiRepairRequest -Request $pending.Request -Error $result.Error) -Attempt 2
            if ($null -ne $next) { $timer.Start(); return }
        }
        if (-not $result.Ok) {
            $status.Foreground = Get-Resource 'DangerText'
            $status.Text = $result.Error
            return
        }
        if ($result.Raw.PSObject.Properties['error'] -and $result.Raw.error) {
            $status.Foreground = Get-Resource 'DangerText'
            $status.Text = ('The model could not draft that: ' + [string]$result.Raw.error)
            return
        }

        $check = Test-CustomEntry -Raw $result.Raw
        if (-not $check.Ok -and $pending.Attempt -lt 2) {
            $next = Start-AiDraft -Request (Get-AiRepairRequest -Request $pending.Request -Error $check.Error) -Attempt 2
            if ($null -ne $next) { $timer.Start(); return }
        }
        if (-not $check.Ok) {
            $status.Foreground = Get-Resource 'DangerText'
            $status.Text = ('Rejected: ' + $check.Error)
            return
        }

        $script:AiDraftEntry = $check.Entry
        $entry = $check.Entry

        $previewBody.Children.Clear()

        $head = New-TextBlock -Text $entry.Title -Size 13.5 -Weight 'SemiBold' -Wrap 'Wrap'
        [void]$previewBody.Children.Add($head)

        $pills = New-Object System.Windows.Controls.StackPanel
        $pills.Orientation = 'Horizontal'
        $pills.Margin = New-Object System.Windows.Thickness(0, 6, 0, 0)
        [void]$pills.Children.Add((New-Pill -Text 'AI' -ColorKey 'Accent' -BgKey 'AccentSoft' -Tip 'Drafted from your description.'))
        [void]$pills.Children.Add((New-Pill -Text $entry.Group.ToUpperInvariant() -ColorKey 'TextTertiary' -BgKey 'PillBg' -Tip 'Card group'))
        if ($entry.Risk -ne 'safe') {
            [void]$pills.Children.Add((New-Pill -Text $entry.Risk.ToUpperInvariant() -ColorKey 'WarnGlyph' -BgKey 'PillBg' -Tip 'Check what this does before switching it on.'))
        }
        [void]$previewBody.Children.Add($pills)

        $body = New-TextBlock -Text $entry.Desc -Size 12 -ColorKey 'TextSecondary' -Wrap 'Wrap'
        $body.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
        [void]$previewBody.Children.Add($body)

        if ($entry.ContainsKey('Values')) {
            foreach ($value in $entry.Values) {
                $line = New-TextBlock -Text ('{0}\{1}\{2}  =  {3}' -f $value.Hive, $value.Path, $value.Name, $(if ($null -eq $value.On) { '(deleted)' } else { [string]$value.On })) -Size 11 -ColorKey 'TextTertiary' -Wrap 'Wrap'
                $line.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas, Cascadia Mono')
                $line.Margin = New-Object System.Windows.Thickness(0, 6, 0, 0)
                [void]$previewBody.Children.Add($line)
            }
            if ($entry.ContainsKey('Admin')) {
                [void]$previewBody.Children.Add((New-WarningBox -Text 'This writes a machine-wide setting, so switching it on asks for administrator approval.'))
            }
        } else {
            $line = New-TextBlock -Text ('Runs the existing action: ' + $entry.Handler) -Size 11 -ColorKey 'TextTertiary' -Wrap 'Wrap'
            $line.Margin = New-Object System.Windows.Thickness(0, 6, 0, 0)
            [void]$previewBody.Children.Add($line)
        }

        if ($entry.ContainsKey('Warning') -and $entry.Warning) {
            [void]$previewBody.Children.Add((New-WarningBox -Text $entry.Warning))
        }

        $preview.Visibility = 'Visible'
        $add.Visibility = 'Visible'
        $status.Foreground = Get-Resource 'TextTertiary'
        $status.Text = 'Check the card above, then add it.'
    })

    $add.Add_Click({
        param($sender, $eventArgs)
        $entry = $script:AiDraftEntry
        if ($null -eq $entry) { return }
        Save-CustomEntry -Entry $entry
        $script:AiDraftEntry = $null
        $window = [System.Windows.Window]::GetWindow($sender)
        if ($window) { $window.Tag = 'added'; $window.Close() }
        Show-Toast -Message ("'{0}' added to PowerKit" -f $entry.Title) -Kind 'success'
    })

    $window.Add_Closed({
        $timer.Stop()
        if ($null -ne $script:AiPending) {
            try { $script:AiPending.Ps.Stop() } catch { }
            try { $script:AiPending.Ps.Dispose() } catch { }
            $script:AiPending = $null
        }
    })

    $window.Tag = 'cancel'
    $inputBox.Focus() | Out-Null
    [void]$window.ShowDialog()
}
