# RegistryTools.ps1 - registry access, default baseline capture, tweak state and apply/reset.

$script:AppDataDir = Join-Path $env:LOCALAPPDATA 'PowerKit'
$script:DefaultsPath = Join-Path $script:AppDataDir 'defaults.json'
$script:LogPath = Join-Path $script:AppDataDir 'app.log'
$script:SettingsPath = Join-Path $script:AppDataDir 'settings.json'
$script:Settings = @{}
$script:Defaults = @{}
$script:DefaultsCapturedAt = $null

function Initialize-AppData {
    if (-not (Test-Path -LiteralPath $script:AppDataDir)) {
        New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null
    }
}

function Load-AppSettings {
    $script:Settings = @{}
    try {
        if (Test-Path -LiteralPath $script:SettingsPath) {
            $raw = [System.IO.File]::ReadAllText($script:SettingsPath)
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $data = ConvertFrom-Json $raw
                foreach ($property in $data.PSObject.Properties) { $script:Settings[$property.Name] = [string]$property.Value }
            }
        }
    } catch { }

    if (-not $script:Settings.ContainsKey('theme')) { $script:Settings['theme'] = 'system' }
    return $script:Settings
}

function Save-AppSettings {
    Initialize-AppData
    $doc = [ordered]@{}
    foreach ($name in @('theme', 'ai_base', 'ai_model', 'collapsed', 'pinned')) {
        if ($script:Settings.ContainsKey($name)) { $doc[$name] = [string]$script:Settings[$name] }
    }
    $json = ConvertTo-Json -InputObject $doc -Depth 3
    [System.IO.File]::WriteAllText($script:SettingsPath, $json, [System.Text.Encoding]::UTF8)
}

$script:LogMaxBytes = 524288
$script:LogArchiveCount = 2

# Rolls app.log to app.log.1 / app.log.2 so the file stays bounded.
function Invoke-LogRotation {
    $path = $script:LogPath
    $file = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    if ($null -eq $file -or $file.Length -lt $script:LogMaxBytes) { return }

    for ($i = $script:LogArchiveCount; $i -ge 1; $i--) {
        $archive = '{0}.{1}' -f $path, $i
        if (-not (Test-Path -LiteralPath $archive)) { continue }
        if ($i -eq $script:LogArchiveCount) {
            Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        } else {
            Move-Item -LiteralPath $archive -Destination ('{0}.{1}' -f $path, ($i + 1)) -Force -ErrorAction SilentlyContinue
        }
    }
    Move-Item -LiteralPath $path -Destination ('{0}.1' -f $path) -Force -ErrorAction SilentlyContinue
}

function Write-AppLog {
    param([string]$Message)

    # The elevated helper sets a tag so its writes are distinguishable in the log.
    $tag = ''
    if ($script:LogTag) { $tag = $script:LogTag + '  ' }
    $line = ('{0}  {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $tag, $Message) + [Environment]::NewLine

    # The window and the elevated helper both write here, so retry once if the
    # other process happens to be rotating the file at this instant.
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        try {
            Initialize-AppData
            Invoke-LogRotation
            [System.IO.File]::AppendAllText($script:LogPath, $line, [System.Text.Encoding]::UTF8)
            return
        } catch {
            Start-Sleep -Milliseconds 25
        }
    }
}

function Get-RegRoot {
    param([string]$Hive)
    switch ($Hive) {
        'HKCU' { return [Microsoft.Win32.Registry]::CurrentUser }
        'HKLM' { return [Microsoft.Win32.Registry]::LocalMachine }
        'HKCR' { return [Microsoft.Win32.Registry]::ClassesRoot }
        default { throw "Unsupported registry hive: $Hive" }
    }
}

function Read-RegValue {
    param([string]$Hive, [string]$Path, [string]$Name)

    $root = Get-RegRoot $Hive
    $key = $null
    try {
        $key = $root.OpenSubKey($Path, $false)
        if ($null -eq $key) { return @{ Exists = $false; Kind = $null; Value = $null } }

        $hasValue = $key.GetValueNames() -contains $Name
        if (-not $hasValue) { return @{ Exists = $false; Kind = $null; Value = $null } }

        $kind = $key.GetValueKind($Name).ToString()
        $value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        return @{ Exists = $true; Kind = $kind; Value = $value }
    } catch {
        return @{ Exists = $false; Kind = $null; Value = $null }
    } finally {
        if ($null -ne $key) { $key.Close() }
    }
}

function Write-RegValue {
    param(
        [string]$Hive,
        [string]$Path,
        [string]$Name,
        [string]$Kind,
        $Value,
        [bool]$DeleteKeyIfNull = $false
    )

    $root = Get-RegRoot $Hive

    if ($null -eq $Value) {
        if ($DeleteKeyIfNull) {
            try { $root.DeleteSubKeyTree($Path, $false) } catch { }
            return
        }
        $key = $null
        $isEmpty = $false
        try {
            $key = $root.OpenSubKey($Path, $true)
            if ($null -ne $key) {
                if ($key.GetValueNames() -contains $Name) { $key.DeleteValue($Name, $false) }
                $isEmpty = ($key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0)
            }
        } catch { } finally {
            if ($null -ne $key) { $key.Close() }
        }
        # Do not leave empty keys behind: the tweak that created this key is gone.
        if ($isEmpty) {
            try { $root.DeleteSubKey($Path, $false) } catch { }
        }
        return
    }

    $key = $null
    try {
        $key = $root.CreateSubKey($Path)
        switch ($Kind) {
            'DWord'        { $key.SetValue($Name, [int]$Value, [Microsoft.Win32.RegistryValueKind]::DWord) }
            'QWord'        { $key.SetValue($Name, [long]$Value, [Microsoft.Win32.RegistryValueKind]::QWord) }
            'String'       { $key.SetValue($Name, [string]$Value, [Microsoft.Win32.RegistryValueKind]::String) }
            'ExpandString' { $key.SetValue($Name, [string]$Value, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
            default        { $key.SetValue($Name, $Value) }
        }
    } finally {
        if ($null -ne $key) { $key.Close() }
    }
}

function Get-ValueKey {
    param([string]$TweakId, [int]$Index)
    return ('{0}#{1}' -f $TweakId, $Index)
}

function ConvertTo-Baseline {
    param($Entry)
    if ($null -eq $Entry) { return @{ Exists = $false; Kind = $null; Value = $null } }
    return @{ Exists = [bool]$Entry.Exists; Kind = $Entry.Kind; Value = $Entry.Value }
}

function Load-Defaults {
    Initialize-AppData
    if (Test-Path -LiteralPath $script:DefaultsPath) {
        try {
            $raw = Get-Content -LiteralPath $script:DefaultsPath -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $doc = $raw | ConvertFrom-Json
                $script:DefaultsCapturedAt = $doc.CapturedAt
                $map = @{}
                if ($null -ne $doc.Values) {
                    foreach ($prop in $doc.Values.PSObject.Properties) {
                        $map[$prop.Name] = @{
                            Exists = [bool]$prop.Value.Exists
                            Kind   = $prop.Value.Kind
                            Value  = $prop.Value.Value
                        }
                    }
                }
                $script:Defaults = $map
                return
            }
        } catch {
            Write-AppLog "Could not read defaults.json: $($_.Exception.Message)"
        }
    }
    $script:Defaults = @{}
}

function Save-Defaults {
    Initialize-AppData
    $doc = [ordered]@{
        Version     = 1
        CapturedAt  = $script:DefaultsCapturedAt
        Values      = $script:Defaults
    }
    $json = $doc | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $script:DefaultsPath -Value $json -Encoding UTF8
}

# Records the current registry state as the "factory default" for values we have
# never seen before, so Reset can always restore exactly what was there originally.
function Initialize-Defaults {
    Load-Defaults
    $changed = $false

    foreach ($tweak in $script:TweakDefs) {
        for ($i = 0; $i -lt $tweak.Values.Count; $i++) {
            $value = $tweak.Values[$i]
            $storeKey = Get-ValueKey -TweakId $tweak.Id -Index $i
            if ($script:Defaults.ContainsKey($storeKey)) { continue }

            $current = Read-RegValue -Hive $value.Hive -Path $value.Path -Name $value.Name
            $script:Defaults[$storeKey] = @{ Exists = $current.Exists; Kind = $current.Kind; Value = $current.Value }
            $changed = $true
        }
    }

    if ($changed -or [string]::IsNullOrWhiteSpace($script:DefaultsCapturedAt)) {
        $script:DefaultsCapturedAt = (Get-Date).ToString('o')
        Save-Defaults
    }
}

function Reset-DefaultBaseline {
    # Re-captures every value from whatever is currently in the registry.
    $map = @{}
    foreach ($tweak in $script:TweakDefs) {
        for ($i = 0; $i -lt $tweak.Values.Count; $i++) {
            $value = $tweak.Values[$i]
            $current = Read-RegValue -Hive $value.Hive -Path $value.Path -Name $value.Name
            $map[(Get-ValueKey -TweakId $tweak.Id -Index $i)] = @{ Exists = $current.Exists; Kind = $current.Kind; Value = $current.Value }
        }
    }
    $script:Defaults = $map
    $script:DefaultsCapturedAt = (Get-Date).ToString('o')
    Save-Defaults
}

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-TweakAdmin {
    param($Tweak)
    if ($Tweak.ContainsKey('Admin') -and $Tweak.Admin) { return $true }
    foreach ($value in $Tweak.Values) {
        if ($value.Hive -eq 'HKLM' -or $value.Hive -eq 'HKCR') { return $true }
    }
    return $false
}

function Test-SameValue {
    param($Current, $Expected, [string]$ExpectedKind)

    if ($null -eq $Expected) { return (-not $Current.Exists) }
    if (-not $Current.Exists) { return $false }
    if ($ExpectedKind -and $Current.Kind -and $Current.Kind -ne $ExpectedKind) { return $false }

    if ($Current.Value -is [int] -or $Current.Value -is [long]) {
        $expectedNumber = 0
        if ([int]::TryParse([string]$Expected, [ref]$expectedNumber)) {
            return ([long]$Current.Value -eq [long]$expectedNumber)
        }
        return $false
    }
    return ([string]$Current.Value -eq [string]$Expected)
}

function Get-TweakState {
    param($Tweak)

    $allOn = $true
    $allDefault = $true

    for ($i = 0; $i -lt $Tweak.Values.Count; $i++) {
        $value = $Tweak.Values[$i]
        $current = Read-RegValue -Hive $value.Hive -Path $value.Path -Name $value.Name

        $expectedKind = $value.Kind
        if (-not (Test-SameValue -Current $current -Expected $value.On -ExpectedKind $expectedKind)) { $allOn = $false }

        $baseline = $script:Defaults[(Get-ValueKey -TweakId $Tweak.Id -Index $i)]
        if ($null -eq $baseline) {
            $baseline = @{ Exists = $false; Kind = $null; Value = $null }
        }
        if ($baseline.Exists) {
            if (-not (Test-SameValue -Current $current -Expected $baseline.Value -ExpectedKind $baseline.Kind)) { $allDefault = $false }
        } elseif ($current.Exists) {
            $allDefault = $false
        }
    }

    return @{ Active = $allOn; IsDefault = $allDefault }
}

function Get-TweakById {
    param([string]$Id)
    foreach ($tweak in $script:TweakDefs) { if ($tweak.Id -eq $Id) { return $tweak } }
    return $null
}

function Set-TweakValue {
    param($Tweak, $ValueDef, $Value, [bool]$DeleteKeyIfNull = $false)

    if ($ValueDef.Hive -eq 'HKLM' -and -not $script:IsAdmin) {
        throw 'Administrator rights are required for this system-wide tweak.'
    }
    # The old value goes into the log line, so a single write can be undone from the
    # activity log instead of resetting the whole card.
    $previous = Read-RegValue -Hive $ValueDef.Hive -Path $ValueDef.Path -Name $ValueDef.Name
    Write-RegValue -Hive $ValueDef.Hive -Path $ValueDef.Path -Name $ValueDef.Name -Kind $ValueDef.Kind -Value $Value `
        -DeleteKeyIfNull ($DeleteKeyIfNull -and $ValueDef.ContainsKey('DeleteKey') -and $ValueDef.DeleteKey)
    $was = if ($previous.Exists) { '{0} {1}' -f $previous.Kind, $previous.Value } else { 'absent' }
    Write-AppLog ("SET {0} {1}\{2} [{3}] = {4} (was {5})" -f $Tweak.Id, $ValueDef.Hive, $ValueDef.Path, $ValueDef.Name, $(if ($null -eq $Value) { '<deleted>' } else { $Value }), $was)
}

function Apply-Tweak {
    param($Tweak, [bool]$TurnOn)

    $failed = @()
    foreach ($value in $Tweak.Values) {
        $target = if ($TurnOn) { $value.On } else { $value.Off }
        try {
            Set-TweakValue -Tweak $Tweak -ValueDef $value -Value $target
        } catch {
            $failed += $_.Exception.Message
        }
    }
    if ($failed.Count -gt 0) { throw ($failed | Select-Object -Unique) -join ' ' }
}

function Reset-Tweak {
    param($Tweak)

    $failed = @()
    for ($i = 0; $i -lt $Tweak.Values.Count; $i++) {
        $value = $Tweak.Values[$i]
        $baseline = $script:Defaults[(Get-ValueKey -TweakId $Tweak.Id -Index $i)]
        if ($null -eq $baseline) { $baseline = @{ Exists = $false; Kind = $null; Value = $null } }

        try {
            if ($baseline.Exists) {
                $kind = if ($baseline.Kind) { $baseline.Kind } else { $value.Kind }
                Set-TweakValue -Tweak $Tweak -ValueDef $value -Value $baseline.Value
            } else {
                Set-TweakValue -Tweak $Tweak -ValueDef $value -Value $null
            }
        } catch {
            $failed += $_.Exception.Message
        }
    }
    if ($failed.Count -gt 0) { throw ($failed | Select-Object -Unique) -join ' ' }
}

function Get-ActiveTweaks {
    param([switch]$SkipLocked)

    $active = @()
    foreach ($tweak in $script:TweakDefs) {
        $state = Get-TweakState $tweak
        if ($state.Active) {
            if ($SkipLocked -and (Test-TweakAdmin $tweak) -and -not $script:IsAdmin) { continue }
            $active += $tweak
        }
    }
    return $active
}
