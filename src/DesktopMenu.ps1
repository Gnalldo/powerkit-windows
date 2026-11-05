# DesktopMenu.ps1 - the PowerKit submenu on the desktop right-click menu.
#
# Windows 11 keeps third-party verbs in the classic menu, so this appears under
# "Show more options" (or Shift+F10). The submenu is rebuilt from the pinned cards on
# every start and whenever a pin changes, so the app and the menu never disagree.

$script:DesktopMenuVerb = 'PowerKit'
$script:DesktopMenuMaxTitle = 70

function Get-DesktopMenuKey {
    return 'HKCU:\Software\Classes\DesktopBackground\Shell\PowerKit'
}

# Registry command strings are not parsed like shell arguments, but quoting the paths
# is still what the shell expects for anything with a space in it.
function Get-PowerKitCommandLine {
    param([string]$FocusId = '')

    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $exe)) { $exe = 'powershell.exe' }
    $app = Join-Path $script:AppRoot 'PowerKit.ps1'

    $line = '"{0}" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $exe, $app
    if ($FocusId) { $line += (' -Focus "{0}"' -f $FocusId) }
    return $line
}

# Pinned ids that still resolve to a card, in pin order, with the title Windows shows.
function Get-DesktopMenuPins {
    $items = @()
    $seen = @{}

    foreach ($pinnedId in @((Get-PinnedCards).Keys)) {
        $id = [string]$pinnedId
        if (-not $id -or $seen.ContainsKey($id)) { continue }

        $entry = Get-ActionById -Id $id
        if ($null -eq $entry) { continue }
        $seen[$id] = $true

        $title = [string]$entry.Title
        if ($title.Length -gt $script:DesktopMenuMaxTitle) {
            $title = $title.Substring(0, $script:DesktopMenuMaxTitle - 3) + '...'
        }

        # The key name has to survive a registry path, and AI-drafted ids are only
        # slug-shaped by convention.
        $key = 'pin-' + ($id -replace '[^A-Za-z0-9_.-]', '-')
        $items += @{ Key = $key; Title = $title; Id = $id }
    }

    return $items
}

function Set-DesktopMenuItem {
    param([string]$Key, [string]$Text, [string]$CommandLine = '', [string]$Icon = '')

    if (-not (Test-Path -LiteralPath $Key)) { $null = New-Item -Path $Key -Force }
    Set-Item -LiteralPath $Key -Value $Text
    if ($Icon) { $null = New-ItemProperty -LiteralPath $Key -Name 'Icon' -Value $Icon -PropertyType String -Force }

    if ($CommandLine) {
        $commandKey = Join-Path $Key 'command'
        if (-not (Test-Path -LiteralPath $commandKey)) { $null = New-Item -Path $commandKey -Force }
        Set-Item -LiteralPath $commandKey -Value $CommandLine
    }
}

function Sync-DesktopMenu {
    # Without the app root the menu would point at nothing, so leave the existing one be.
    if ([string]::IsNullOrWhiteSpace($script:AppRoot)) { return }

    try {
        $root = Get-DesktopMenuKey
        $shellKey = Join-Path $root 'shell'
        $iconPath = Join-Path $script:AppRoot 'src\powerkit.ico'
        $icon = if (Test-Path -LiteralPath $iconPath) { $iconPath } else { '' }

        if (-not (Test-Path -LiteralPath $root)) { $null = New-Item -Path $root -Force }
        # MUIVerb names the submenu and an empty SubCommands turns it into a cascade.
        $null = New-ItemProperty -LiteralPath $root -Name 'MUIVerb' -Value $script:DesktopMenuVerb -PropertyType String -Force
        $null = New-ItemProperty -LiteralPath $root -Name 'SubCommands' -Value ([string]::Empty) -PropertyType String -Force
        if ($icon) { $null = New-ItemProperty -LiteralPath $root -Name 'Icon' -Value $icon -PropertyType String -Force }

        # The children are rewritten from scratch so an unpinned card cannot linger.
        if (Test-Path -LiteralPath $shellKey) { Remove-Item -LiteralPath $shellKey -Recurse -Force }
        $null = New-Item -Path $shellKey -Force

        Set-DesktopMenuItem -Key (Join-Path $shellKey 'launch') -Text 'Launch PowerKit' `
            -CommandLine (Get-PowerKitCommandLine) -Icon $icon

        $pins = @(Get-DesktopMenuPins)
        if ($pins.Count -gt 0) {
            # CommandFlags 0x20 is MF_SEPARATOR: a plain divider, no text.
            $separatorKey = Join-Path $shellKey 'separator'
            $null = New-Item -Path $separatorKey -Force
            $null = New-ItemProperty -LiteralPath $separatorKey -Name 'CommandFlags' -Value 32 -PropertyType DWord -Force
        }

        foreach ($pin in $pins) {
            Set-DesktopMenuItem -Key (Join-Path $shellKey $pin.Key) -Text $pin.Title `
                -CommandLine (Get-PowerKitCommandLine -FocusId $pin.Id)
        }
    } catch {
        # A failed menu write must never stop the app from starting.
        Write-AppLog ('Desktop menu not updated: {0}' -f $_.Exception.Message)
    }
}
