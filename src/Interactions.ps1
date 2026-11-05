# Interactions.ps1 - user actions, dialogs, toasts, filtering and application startup.

$script:DialogValue = 'close'
$script:NavOverride = $null
$script:RunHistorySuppress = $false
$script:GroupOrder = @{}
$script:DefaultsInfoText = $null

function Show-Toast {
    param([string]$Message, [string]$Kind = 'info')

    if ($null -eq $script:ToastBorder) { return }

    $script:ToastText.Text = $Message
    switch ($Kind) {
        'error' {
            $script:ToastBorder.Background = Get-Resource 'DangerBg'
            $script:ToastBorder.BorderBrush = Get-Resource 'DangerText'
            $script:ToastText.Foreground = Get-Resource 'DangerText'
        }
        'success' {
            $script:ToastBorder.Background = Get-Resource 'CardBg'
            $script:ToastBorder.BorderBrush = Get-Resource 'Accent'
            $script:ToastText.Foreground = Get-Resource 'TextPrimary'
        }
        default {
            $script:ToastBorder.Background = Get-Resource 'CardBg'
            $script:ToastBorder.BorderBrush = Get-Resource 'BorderStrong'
            $script:ToastText.Foreground = Get-Resource 'TextPrimary'
        }
    }

    $script:ToastBorder.Visibility = 'Visible'
    $script:ToastTimer.Stop()
    $script:ToastTimer.Start()
}

function Show-Dialog {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Primary = 'OK',
        [string]$Secondary = '',
        [switch]$Danger,
        $Owner = $null
    )

    $dialog = New-Object System.Windows.Window
    $dialog.WindowStyle = 'None'
    $dialog.AllowsTransparency = $true
    $dialog.Background = [System.Windows.Media.Brushes]::Transparent
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.SizeToContent = 'Height'
    $dialog.Width = 428
    $dialog.ResizeMode = 'NoResize'
    $dialog.ShowInTaskbar = $false
    $dialog.FontFamily = $script:FontText
    [System.Windows.Media.TextOptions]::SetTextFormattingMode($dialog, 'Display')
    Add-AppResources -Resources $dialog.Resources -Mode $script:ThemeMode
    Register-ThemeWindow -Window $dialog
    if ($null -eq $Owner) { $Owner = $script:Window }
    if ($null -ne $Owner) { $dialog.Owner = $Owner }

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
    $titleText = New-TextBlock -Text $Title -Size 16 -Weight 'SemiBold' -Font $script:FontDisplay
    $titleText.TextWrapping = 'Wrap'
    [void]$stack.Children.Add($titleText)

    $messageText = New-TextBlock -Text $Message -Size 12.5 -ColorKey 'TextSecondary' -Wrap 'Wrap'
    $messageText.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
    $messageText.MaxWidth = 360
    $messageText.HorizontalAlignment = 'Left'
    [void]$stack.Children.Add($messageText)

    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = New-Object System.Windows.Thickness(0, 20, 0, 0)
    [void]$stack.Children.Add($buttons)

    if ($Secondary) {
        $secondaryButton = New-Object System.Windows.Controls.Button
        $secondaryButton.Style = Get-Resource 'BtnSecondary'
        $secondaryButton.Content = $Secondary
        $secondaryButton.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        $secondaryButton.MinWidth = 96
        $secondaryButton.Add_Click({
            param($sender, $eventArgs)
            $script:DialogValue = 'secondary'
            $sender.Tag = 'done'
            $window = [System.Windows.Window]::GetWindow($sender)
            if ($window) { $window.Close() }
        })
        [void]$buttons.Children.Add($secondaryButton)
    }

    $primaryButton = New-Object System.Windows.Controls.Button
    $primaryButton.Style = Get-Resource 'BtnPrimary'
    $primaryButton.Content = $Primary
    $primaryButton.MinWidth = 96
    if ($Danger) {
        $primaryButton.Background = Get-Resource 'DangerText'
        $primaryButton.Foreground = [System.Windows.Media.Brushes]::White
        $primaryButton.BorderBrush = Get-Resource 'DangerText'
    }
    $primaryButton.Add_Click({
        param($sender, $eventArgs)
        $script:DialogValue = 'primary'
        $window = [System.Windows.Window]::GetWindow($sender)
        if ($window) { $window.Close() }
    })
    [void]$buttons.Children.Add($primaryButton)

    $card.Child = $stack
    $dialog.Content = $card

    $dialog.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            $script:DialogValue = 'close'
            $sender.Close()
            $eventArgs.Handled = $true
        } elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::Enter) {
            $script:DialogValue = 'primary'
            $sender.Close()
            $eventArgs.Handled = $true
        }
    })

    $script:DialogValue = 'close'
    [void]$dialog.ShowDialog()
    return $script:DialogValue
}

function Show-AdminRequired {
    param([string]$Detail = '')

    $message = 'This action changes a machine-wide setting, which only an elevated process can write.'
    if ($Detail) { $message = $message + "`n`n" + $Detail }
    $message = $message + "`n`nPowerKit can ask Windows for approval when you retry, or you can restart the whole app as administrator. User-level tweaks keep working without elevation."

    $answer = Show-Dialog -Title 'Administrator rights required' -Message $message -Primary 'Got it' -Secondary 'Restart elevated'
    if ($answer -eq 'secondary') { Restart-Elevated }
}

function Restart-Elevated {
    try {
        $scriptPath = $script:ScriptPath
        $exe = (Get-Process -Id $PID).Path
        Start-Process -FilePath $exe -Verb RunAs -ArgumentList @(
            '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$scriptPath`""
        ) | Out-Null
        $script:Window.Close()
    } catch {
        Show-Toast -Message 'Elevation was cancelled or blocked.' -Kind 'error'
    }
}

function Update-TweakVisuals {
    param($Tweak)

    if (-not $script:TweakCards.ContainsKey($Tweak.Id)) { return }
    $state = Get-TweakState -Tweak $Tweak

    foreach ($instance in $script:TweakCards[$Tweak.Id]) {
        $instance.Toggle.IsChecked = [bool]$state.Active
        $instance.Reset.Visibility = if ($state.IsDefault) { 'Collapsed' } else { 'Visible' }
    }
}

function Set-TweakFromUi {
    param([string]$Id, [bool]$Desired)

    $tweak = Get-TweakById -Id $Id
    if ($null -eq $tweak) { return }

    $needsElevation = (-not $script:IsAdmin) -and (Test-TweakAdmin -Tweak $tweak)

    try {
        if ($needsElevation) {
            $response = Invoke-ElevatedTweakAction -Tweak $tweak -Action 'apply' -TurnOn $Desired
            if (-not $response.ok) {
                Update-TweakVisuals -Tweak $tweak
                if ($response.needsApproval) {
                    Show-AdminRequired -Detail $response.error
                } else {
                    Show-Toast -Message $response.error -Kind 'error'
                }
                return
            }
        } else {
            Apply-Tweak -Tweak $tweak -TurnOn $Desired
        }
        $state = Get-TweakState -Tweak $tweak
        if ($state.Active -ne $Desired) {
            Update-TweakVisuals -Tweak $tweak
            Show-Toast -Message ("Windows did not accept the new value for '{0}'. It may be controlled by policy on this PC." -f $tweak.Title) -Kind 'error'
            return
        }
        Update-TweakVisuals -Tweak $tweak
        Sync-ActiveSection
        Sync-PinnedSection
        Update-NavCounts
        Update-SectionCounts
        if ($Desired) { Add-PendingRestart -Kind $tweak.Restart }
        $verb = if ($Desired) { 'enabled' } else { 'disabled' }
        Show-Toast -Message ("{0} {1}" -f $tweak.Title, $verb) -Kind 'success'
    } catch {
        Update-TweakVisuals -Tweak $tweak
        Show-Toast -Message $_.Exception.Message -Kind 'error'
    }
}

function Reset-TweakFromUi {
    param([string]$Id)

    $tweak = Get-TweakById -Id $Id
    if ($null -eq $tweak) { return }

    $needsElevation = (-not $script:IsAdmin) -and (Test-TweakAdmin -Tweak $tweak)

    try {
        if ($needsElevation) {
            $response = Invoke-ElevatedTweakAction -Tweak $tweak -Action 'reset'
            if (-not $response.ok) {
                if ($response.needsApproval) {
                    Show-AdminRequired -Detail $response.error
                } else {
                    Show-Toast -Message $response.error -Kind 'error'
                }
                return
            }
        } else {
            Reset-Tweak -Tweak $tweak
        }
        Update-TweakVisuals -Tweak $tweak
        Sync-ActiveSection
        Sync-PinnedSection
        Update-NavCounts
        Update-SectionCounts
        Show-Toast -Message ("{0} reset to its default" -f $tweak.Title) -Kind 'success'
    } catch {
        Show-Toast -Message $_.Exception.Message -Kind 'error'
    }
}

function Reset-AllFromUi {
    $changed = @()
    $adminChanged = @()
    foreach ($tweak in $script:TweakDefs) {
        if ((Get-TweakState -Tweak $tweak).IsDefault) { continue }
        $changed += $tweak
        if ((-not $script:IsAdmin) -and (Test-TweakAdmin -Tweak $tweak)) { $adminChanged += $tweak }
    }

    if ($changed.Count -eq 0) {
        Show-Toast -Message 'Every tweak is already at its captured default.' -Kind 'info'
        return
    }

    $message = "{0} tweak(s) differ from the value PowerKit captured when it first ran. They will be restored to that value. Nothing else on your PC is touched." -f $changed.Count
    if ($adminChanged.Count -gt 0) {
        $message = $message + "`n`n{0} of them write machine-wide settings and need one administrator approval." -f $adminChanged.Count
    }
    $answer = Show-Dialog -Title 'Reset all tweaks?' -Message $message -Primary 'Reset everything' -Secondary 'Cancel'
    if ($answer -ne 'primary') { return }

    $elevationReady = $false
    if ($adminChanged.Count -gt 0) {
        $elevationReady = Ensure-ElevatedHelper
    }

    $errors = @()
    $skipped = 0
    foreach ($tweak in $changed) {
        $isAdminTweak = ($adminChanged -contains $tweak)
        if ($isAdminTweak) {
            if (-not $elevationReady) { $skipped++; continue }
            $response = Invoke-ElevatedRequest -Payload @{ action = 'reset'; id = $tweak.Id } -ConnectTimeoutMs 5000
            if (-not $response.ok) { $errors += ("{0}: {1}" -f $tweak.Title, $response.error) }
            continue
        }
        try {
            Reset-Tweak -Tweak $tweak
        } catch {
            $errors += ("{0}: {1}" -f $tweak.Title, $_.Exception.Message)
        }
    }

    Refresh-AllVisuals
    if ($errors.Count -gt 0) {
        Show-Toast -Message ("Reset finished with {0} problem(s): {1}" -f $errors.Count, ($errors -join ' ')) -Kind 'error'
    } elseif ($skipped -gt 0) {
        Show-Toast -Message ("{0} tweak(s) reset. {1} machine-wide tweak(s) left unchanged because administrator approval was not granted." -f ($changed.Count - $skipped), $skipped) -Kind 'info'
    } else {
        Show-Toast -Message ("{0} tweak(s) reset to their default" -f $changed.Count) -Kind 'success'
    }
}

function Recapture-Defaults {
    $answer = Show-Dialog -Title 'Re-capture defaults?' -Message 'The current state of every setting becomes the new default. Resetting later will restore what is in the registry right now.' -Primary 'Capture now' -Secondary 'Cancel'
    if ($answer -ne 'primary') { return }

    try {
        Reset-DefaultBaseline
        if ($null -ne $script:DefaultsInfoText) {
            $captured = ([datetime]$script:DefaultsCapturedAt).ToString('d MMM yyyy HH:mm')
            $script:DefaultsInfoText.Text = "Defaults captured: $captured"
        }
        Refresh-AllVisuals
        Show-Toast -Message 'Current settings captured as the new defaults' -Kind 'success'
    } catch {
        Show-Toast -Message $_.Exception.Message -Kind 'error'
    }
}

function Write-PowerKitSetupFile {
    param([string]$Path)

    # The key is left out on purpose: DPAPI ties it to this account on this PC.
    $doc = [ordered]@{
        Version  = 1
        Exported = (Get-Date).ToString('o')
        Computer = $env:COMPUTERNAME
        Settings = [ordered]@{
            theme    = [string]$script:Settings['theme']
            ai_base  = Get-AiBaseUrl
            ai_model = Get-AiModel
            pinned   = (@((Get-PinnedCards).Keys) -join ',')
        }
        Defaults = [ordered]@{
            CapturedAt = $script:DefaultsCapturedAt
            Values     = $script:Defaults
        }
        Custom   = @(Get-CustomCatalogEntries)
    }

    $json = $doc | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-AppLog ("EXPORT setup to {0}" -f $Path)
    return $Path
}

function Read-PowerKitSetupFile {
    param([string]$Path)

    $raw = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) { throw 'That file is empty.' }
    $doc = ConvertFrom-Json $raw
    if ($null -eq $doc.PSObject.Properties['Version']) { throw 'That file is not a PowerKit setup export.' }
    return $doc
}

function Export-PowerKitSetup {
    try {
        $dialog = New-Object Microsoft.Win32.SaveFileDialog
        $dialog.Title = 'Export PowerKit setup'
        $dialog.Filter = 'PowerKit setup (*.json)|*.json|All files (*.*)|*.*'
        $dialog.DefaultExt = 'json'
        $dialog.AddExtension = $true
        $dialog.FileName = 'PowerKit-setup.json'
        $saved = if ($null -ne $script:Window) { $dialog.ShowDialog($script:Window) } else { $dialog.ShowDialog() }
        if ($saved -ne $true) { return }

        Write-PowerKitSetupFile -Path $dialog.FileName
        Show-Toast -Message ('Setup exported to ' + [System.IO.Path]::GetFileName($dialog.FileName)) -Kind 'success'
    } catch {
        Show-Toast -Message ('Export failed: ' + $_.Exception.Message) -Kind 'error'
    }
}

function Import-PowerKitSetup {
    try {
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = 'Import PowerKit setup'
        $dialog.Filter = 'PowerKit setup (*.json)|*.json|All files (*.*)|*.*'
        $dialog.CheckFileExists = $true
        $opened = if ($null -ne $script:Window) { $dialog.ShowDialog($script:Window) } else { $dialog.ShowDialog() }
        if ($opened -ne $true) { return }

        $doc = Read-PowerKitSetupFile -Path $dialog.FileName

        $answer = Show-Dialog -Title 'Import this setup?' -Message 'Settings, the Reset baseline and any AI-drafted cards in the file replace what is on this PC. The API key is not part of an export, so a saved key stays as it is.' -Primary 'Import' -Secondary 'Cancel' -Danger
        if ($answer -ne 'primary') { return }

        $added = Apply-PowerKitSetup -Document $doc -Source $dialog.FileName

        if ($null -ne $script:DefaultsInfoText) {
            $captured = if ($script:DefaultsCapturedAt) { ([datetime]$script:DefaultsCapturedAt).ToString('d MMM yyyy HH:mm') } else { 'not captured yet' }
            $script:DefaultsInfoText.Text = "Defaults captured: $captured"
        }

        Write-AppLog ("IMPORT setup from {0} ({1} card(s) added)" -f $dialog.FileName, $added)
        Refresh-AllVisuals
        Show-Toast -Message ("Setup imported. {0} card(s) added." -f $added) -Kind 'success'
    } catch {
        Show-Toast -Message ('Import failed: ' + $_.Exception.Message) -Kind 'error'
    }
}

function Apply-PowerKitSetup {
    param($Document, [string]$Source = '')

    $settings = $Document.Settings
    if ($null -ne $settings) {
        foreach ($name in @('ai_base', 'ai_model')) {
            if ($null -ne $settings.PSObject.Properties[$name]) { $script:Settings[$name] = [string]$settings.$name }
        }
        if ($null -ne $settings.PSObject.Properties['pinned']) {
            # Drop the cache so the imported pin list is read instead of the old one.
            $script:PinnedCards = $null
            $script:Settings['pinned'] = [string]$settings.pinned
        }
    }
    Save-AppSettings

    if ($null -ne $Document.Defaults -and $null -ne $Document.Defaults.PSObject.Properties['Values']) {
        $defaultsDoc = [ordered]@{
            Version    = 1
            CapturedAt = [string]$Document.Defaults.CapturedAt
            Values     = $Document.Defaults.Values
        }
        $defaultsJson = $defaultsDoc | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($script:DefaultsPath, $defaultsJson, [System.Text.Encoding]::UTF8)
        Load-Defaults
    }

    $added = 0
    $known = @{}
    foreach ($tweak in $script:TweakDefs) { $known[$tweak.Id] = $true }
    foreach ($command in $script:CommandDefs) { $known[$command.Id] = $true }

    foreach ($rawEntry in @($Document.Custom)) {
        if ($null -eq $rawEntry) { continue }
        $entry = ConvertTo-CatalogEntry -Raw $rawEntry
        if ($null -eq $entry) { continue }
        if ($known.ContainsKey($entry.Id)) { continue }
        if ($entry.ContainsKey('Values')) { $script:TweakDefs += $entry } else { $script:CommandDefs += $entry }
        $known[$entry.Id] = $true
        Add-CustomEntryToUi -Entry $entry
        $added++
    }
    if ($added -gt 0) { Save-CustomCatalog }

    if ($null -ne $settings -and $null -ne $settings.PSObject.Properties['theme']) {
        $choice = [string]$settings.theme
        if ($choice -eq 'light' -or $choice -eq 'dark' -or $choice -eq 'system') { [void](Set-ThemeChoice -Choice $choice) }
    }

    return $added
}

function Invoke-CommandFromUi {
    param([string]$Id)

    $command = $null
    foreach ($entry in $script:CommandDefs) { if ($entry.Id -eq $Id) { $command = $entry } }
    if ($null -eq $command) { return }

    if ($command.ContainsKey('Confirm') -and $command.Confirm) {
        $label = if ($command.ContainsKey('ConfirmLabel') -and $command.ConfirmLabel) { $command.ConfirmLabel } else { 'Continue' }
        $answer = Show-Dialog -Title $command.Title -Message $command.Confirm -Primary $label -Secondary 'Cancel' -Danger
        if ($answer -ne 'primary') { return }
    }

    $needsElevation = ($command.ContainsKey('Admin') -and $command.Admin -and -not $script:IsAdmin)

    try {
        if ($needsElevation) {
            $response = Invoke-ElevatedAction -Payload @{ action = 'command'; id = $command.Id }
            if (-not $response.ok) {
                if ($response.needsApproval) {
                    Show-AdminRequired -Detail $response.error
                } else {
                    Show-Toast -Message ('Administrator helper: ' + $response.error) -Kind 'error'
                }
                return
            }
            Show-Toast -Message $response.message -Kind 'success'
            return
        }

        # Tag the RUN lines this command writes so the log row can point back at its card.
        $script:LogCommandId = $command.Id
        try {
            $message = Get-HandlerAction -Handler $command.Handler
        } finally {
            $script:LogCommandId = ''
        }
        Show-Toast -Message $message -Kind 'success'
    } catch {
        Show-Toast -Message $_.Exception.Message -Kind 'error'
    }
}

function Sync-ActiveSection {
    if ($null -eq $script:ActivePanel) { return }

    $active = @(Get-ActiveTweaks | Sort-Object -Property @{ Expression = { $script:GroupOrder[$_.Group] } }, Title)

    $script:ActivePanel.Children.Clear()
    foreach ($tweak in $active) {
        $card = New-TweakCard -Tweak $tweak -Compact
        [void]$script:ActivePanel.Children.Add($card)
        Update-TweakVisuals -Tweak $tweak
    }

    if ($null -ne $script:ActiveCountText) {
        $script:ActiveCountText.Child.Text = [string]$active.Count
    }
    Update-Filter
    Update-GridColumns
}

# Pins cover tweaks and command cards alike, so every pin lookup goes through one
# helper instead of each caller guessing which list to search.
function Get-ActionById {
    param([string]$Id)

    $tweak = Get-TweakById -Id $Id
    if ($null -ne $tweak) { return $tweak }
    return (Get-CommandById -Id $Id)
}

function Sync-PinnedSection {
    if ($null -eq $script:PinnedPanel) { return }

    $pinned = Get-PinnedCards
    $entries = @()
    foreach ($id in @($pinned.Keys)) {
        $entry = Get-ActionById -Id ([string]$id)
        # A pin whose card was removed drops out of the strip rather than showing blank.
        if ($null -eq $entry) { continue }
        $entries += @{ Entry = $entry; IsTweak = $entry.ContainsKey('Values') }
    }

    $script:PinnedPanel.Children.Clear()
    foreach ($item in $entries) {
        if ($item.IsTweak) {
            $card = New-TweakCard -Tweak $item.Entry -Compact
            [void]$script:PinnedPanel.Children.Add($card)
            Update-TweakVisuals -Tweak $item.Entry
        } else {
            [void]$script:PinnedPanel.Children.Add((New-CommandCard -Command $item.Entry -Compact))
        }
    }

    if ($null -ne $script:PinnedCountText) { $script:PinnedCountText.Child.Text = [string]$entries.Count }
    Update-Filter
    Update-GridColumns
}

function Toggle-PinFromUi {
    param([string]$Id)

    $entry = Get-ActionById -Id $Id
    if ($null -eq $entry) { return }

    $pinned = Get-PinnedCards
    if ($pinned.Contains([string]$Id)) {
        [void]$pinned.Remove([string]$Id)
        $verb = 'unpinned'
    } else {
        $pinned[[string]$Id] = $true
        $verb = 'pinned'
    }

    # Save-PinnedCards also rewrites the desktop menu, so the two stay in step.
    Save-PinnedCards
    Update-PinButtons -Id $Id
    Sync-PinnedSection
    Show-Toast -Message ("'{0}' {1}" -f $entry.Title, $verb) -Kind 'info'
}

function Update-NavCounts {
    $active = Get-ActiveTweaks
    if ($script:NavCounts.ContainsKey('active')) { $script:NavCounts['active'].Text = [string]$active.Count }
    if ($script:NavCounts.ContainsKey('all')) { $script:NavCounts['all'].Text = [string]$script:TweakDefs.Count }

    foreach ($group in $script:GroupDefs) {
        if (-not $script:NavCounts.ContainsKey($group.Id)) { continue }
        $isCommandGroup = ($group.Id -eq 'power' -or $group.Id -eq 'tools')
        if ($isCommandGroup) {
            $count = 0
            foreach ($command in $script:CommandDefs) { if ($command.Group -eq $group.Id) { $count++ } }
            $script:NavCounts[$group.Id].Text = [string]$count
        } else {
            $count = 0
            foreach ($tweak in $active) { if ($tweak.Group -eq $group.Id) { $count++ } }
            $script:NavCounts[$group.Id].Text = $(if ($count -gt 0) { [string]$count } else { '' })
        }
    }
}

function Update-SectionCounts {
    $active = Get-ActiveTweaks
    foreach ($section in $script:Sections) {
        $total = 0
        $on = 0
        foreach ($entry in $section.Entries) { $total++ }
        if ($section.Group -ne 'power' -and $section.Group -ne 'tools') {
            foreach ($tweak in $script:TweakDefs) {
                if ($tweak.Group -ne $section.Group) { continue }
                foreach ($activeTweak in $active) { if ($activeTweak.Id -eq $tweak.Id) { $on++ } }
            }
            $section.CountText.Text = if ($on -gt 0) { "$on of $total tweaks on" } else { "$total tweaks" }
        } else {
            $section.CountText.Text = "$total commands"
        }
    }
}

function Refresh-AllVisuals {
    param([string]$Notify = '')

    foreach ($tweak in $script:TweakDefs) { Update-TweakVisuals -Tweak $tweak }

    $active = Get-ActiveTweaks
    Sync-ActiveSection
    Sync-PinnedSection
    Update-PinButtons
    Update-NavCounts
    Update-SectionCounts

    if ($null -ne $script:HeaderSubtitle) {
        $script:HeaderSubtitle.Text = ("{0} tweaks / {1} commands / {2} active" -f $script:TweakDefs.Count, $script:CommandDefs.Count, $active.Count)
    }
    if ($Notify) { Show-Toast -Message $Notify -Kind 'success' }
}

function Update-Filter {
    if ($null -eq $script:SearchBox) { return }

    $query = $script:SearchBox.Text.Trim().ToLowerInvariant()
    $searching = $query.Length -gt 0
    $script:SearchPlaceholder.Visibility = if ($script:SearchBox.Text.Length -eq 0) { 'Visible' } else { 'Collapsed' }

    $nav = $script:CurrentNav
    $anyVisible = $false
    $activeHasItems = ($null -ne $script:ActivePanel -and $script:ActivePanel.Children.Count -gt 0)

    $showActive = (-not $searching) -and ($nav -eq 'all' -or $nav -eq 'active') -and $activeHasItems
    if ($null -ne $script:ActiveSection) {
        $script:ActiveSection.Visibility = if ($showActive) { 'Visible' } else { 'Collapsed' }
    }
    if ($showActive) { $anyVisible = $true }

    # Pinned cards ride above everything else, so they only show in the full list.
    $pinnedHasItems = ($null -ne $script:PinnedPanel -and $script:PinnedPanel.Children.Count -gt 0)
    $showPinned = (-not $searching) -and ($nav -eq 'all') -and $pinnedHasItems
    if ($null -ne $script:PinnedSection) {
        $script:PinnedSection.Visibility = if ($showPinned) { 'Visible' } else { 'Collapsed' }
    }
    if ($showPinned) { $anyVisible = $true }

    $hideGroups = ($nav -eq 'active') -and (-not $searching)

    foreach ($section in $script:Sections) {
        $sectionVisible = $false

        if ($hideGroups) {
            foreach ($entry in $section.Entries) { $entry.Card.Visibility = 'Collapsed' }
        } else {
            foreach ($entry in $section.Entries) {
                $matches = (-not $searching) -or $entry.SearchText.Contains($query)
                $selected = $searching -or ($nav -eq 'all') -or ($nav -eq $section.Group)
                $show = $matches -and $selected
                $entry.Card.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }
                if ($show) { $sectionVisible = $true }
            }
        }

        $section.Root.Visibility = if ($sectionVisible) { 'Visible' } else { 'Collapsed' }
        Set-SectionOpen -Section $section -ForceOpen ([bool]$searching)
        if ($sectionVisible) { $anyVisible = $true }
    }

    if ($null -ne $script:NoResults) {
        if ($anyVisible) {
            $script:NoResults.Visibility = 'Collapsed'
        } else {
            if ($searching) {
                $script:NoResults.Text = 'Nothing matches that search.'
            } elseif ($nav -eq 'active') {
                $script:NoResults.Text = 'No tweaks are switched on right now. Flip a switch and it appears here.'
            } else {
                $script:NoResults.Text = 'Nothing to show.'
            }
            $script:NoResults.Visibility = 'Visible'
        }
    }
    Update-GridColumns

    # A section that just became visible is measured after this pass, so ask for one
    # more layout once its width is known.
    if ($null -ne $script:Window) {
        $script:Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
            Update-GridColumns
        }) | Out-Null
    }
}

function Update-NavSelection {
    if ($null -eq $script:NavList) { return }
    $item = $script:NavList.SelectedItem
    if ($null -eq $item) { return }
    $script:CurrentNav = [string]$item.Tag
    Expand-SectionForNav -GroupId $script:CurrentNav
    Update-Filter
}

function Update-NavPaneForWidth {
    if ($null -eq $script:NavColumn -or $null -eq $script:Window) { return }

    $wide = $script:Window.ActualWidth -ge 960
    $show = switch ($script:NavOverride) {
        'show' { $true }
        'hide' { $false }
        default { $wide }
    }

    $script:NavColumn.Width = if ($show) { New-Object System.Windows.GridLength(232) } else { New-Object System.Windows.GridLength(0) }
    if ($null -ne $script:NavList) { $script:NavList.Visibility = if ($show) { 'Visible' } else { 'Collapsed' } }
}

function Toggle-NavPane {
    $wide = $script:Window.ActualWidth -ge 960
    $currentlyShown = switch ($script:NavOverride) {
        'show' { $true }
        'hide' { $false }
        default { $wide }
    }
    $script:NavOverride = if ($currentlyShown) { 'hide' } else { 'show' }
    Update-NavPaneForWidth
}

function Toggle-Theme {
    # Light -> Dark -> follow Windows -> Light, so the pinned choice is reversible.
    $order = @('light', 'dark', 'system')
    $current = if ($script:ThemeOverridden) { $script:ThemeMode } else { 'system' }
    $index = [array]::IndexOf($order, $current)
    if ($index -lt 0) { $index = $order.Count - 1 }
    $choice = $order[($index + 1) % $order.Count]

    $null = Set-ThemeChoice -Choice $choice
    Update-ThemeButton
    Show-Toast -Message (Get-ThemeChoiceLabel -Choice $choice) -Kind 'info'
    Update-GridColumns
}

function Invoke-ChromeAction {
    param([string]$Action)

    if ($null -eq $script:Window) { return }
    switch ($Action) {
        'min'   { $script:Window.WindowState = 'Minimized' }
        'max'   {
            if ($script:Window.WindowState -eq 'Maximized') { $script:Window.WindowState = 'Normal' }
            else { $script:Window.WindowState = 'Maximized' }
        }
        'close' { $script:Window.Close() }
        default { return }
    }
    Update-ChromeState
}

function Update-ChromeState {
    if ($null -eq $script:MaxButton -or $null -eq $script:Window) { return }
    $maximized = ($script:Window.WindowState -eq 'Maximized')
    $content = $script:MaxButton.Content
    if ($null -ne $content -and $content -is [System.Windows.Controls.TextBlock]) {
        $content.Text = [string][char]$(if ($maximized) { 0xE923 } else { 0xE922 })
    }
    $script:MaxButton.ToolTip = $(if ($maximized) { 'Restore' } else { 'Maximise' })
}

function Update-ResponsiveChrome {
    if ($null -eq $script:Window) { return }
    $width = $script:Window.ActualWidth
    if ($null -ne $script:HeaderSearch) {
        $script:HeaderSearch.Visibility = $(if ($width -lt 900) { 'Collapsed' } else { 'Visible' })
    }
    if ($null -ne $script:HeaderSubtitle) {
        $script:HeaderSubtitle.Visibility = $(if ($width -lt 1040) { 'Collapsed' } else { 'Visible' })
    }
}

function Invoke-RunTarget {
    param([string]$Target)

    $Target = $Target.Trim()
    if (-not $Target) { return }

    Add-RunHistory -Target $Target

    try {
        # "start" copes with executables, folders, files and web addresses alike.
        $result = Invoke-CmdHidden -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/c', 'start', '""', $Target)
        if ($result.ExitCode -ne 0) {
            $detail = if ($result.Output) { $result.Output } else { 'Windows could not start that.' }
            throw $detail
        }
        Show-Toast -Message ("Launched {0}" -f $Target) -Kind 'success'
    } catch {
        Show-Toast -Message ("Could not start '{0}': {1}" -f $Target, $_.Exception.Message) -Kind 'error'
    }
}

function Get-RunHistoryPath {
    return (Join-Path $script:AppDataDir 'run-history.json')
}

function Get-RunHistory {
    $items = @()
    $path = Get-RunHistoryPath
    if (Test-Path -LiteralPath $path) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                # ConvertFrom-Json writes an array as ONE pipeline object, so wrapping it
                # in @() would nest it; read the property and iterate that instead.
                $doc = ConvertFrom-Json $raw
                $list = if ($null -ne $doc.PSObject.Properties['entries']) { $doc.entries } else { $doc }
                foreach ($entry in $list) {
                    if ($null -ne $entry -and -not [string]::IsNullOrWhiteSpace([string]$entry)) { $items += [string]$entry }
                }
            }
        } catch { }
    }
    return $items
}

function Get-SystemRunHistory {
    # Windows keeps its own Run history under RunMRU; reading it makes the box feel
    # like the real Run dialog on a fresh install.
    $items = @()
    $key = $null
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU', $false)
        if ($null -ne $key) {
            $order = [string]$key.GetValue('MRUList', '')
            foreach ($letter in $order.ToCharArray()) {
                $value = [string]$key.GetValue([string]$letter, '')
                if (-not $value) { continue }
                $clean = ($value -replace '\\1$', '').Trim()
                if ($clean) { $items += $clean }
            }
        }
    } catch { } finally {
        if ($null -ne $key) { $key.Close() }
    }
    return $items
}

function Add-RunHistory {
    param([string]$Target)

    $target = $Target.Trim()
    if (-not $target) { return }

    $items = @($target) + @(Get-RunHistory | Where-Object { $_.ToLowerInvariant() -ne $target.ToLowerInvariant() })
    if ($items.Count -gt 12) { $items = $items[0..11] }

    Initialize-AppData
    try {
        $json = ConvertTo-Json -InputObject ([ordered]@{ entries = @($items) }) -Depth 3
        [System.IO.File]::WriteAllText((Get-RunHistoryPath), $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        Write-AppLog ("Could not save the run history: {0}" -f $_.Exception.Message)
    }
}

function Get-RunHistoryList {
    $seen = @{}
    $list = @()
    foreach ($entry in (@(Get-RunHistory) + @(Get-SystemRunHistory))) {
        $text = ([string]$entry).Trim()
        if (-not $text) { continue }
        $key = $text.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $list += $text
        if ($list.Count -ge 14) { break }
    }
    return $list
}

function Find-VisualChild {
    param($Parent, [string]$TypeName)

    if ($null -eq $Parent) { return $null }
    $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent)
    for ($i = 0; $i -lt $count; $i++) {
        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $i)
        if ($child.GetType().Name -eq $TypeName) { return $child }
        $found = Find-VisualChild -Parent $child -TypeName $TypeName
        if ($null -ne $found) { return $found }
    }
    return $null
}

function New-RunHistoryRow {
    param([string]$Text)

    $row = New-Object System.Windows.Controls.Border
    $row.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $row.Padding = New-Object System.Windows.Thickness(8, 6, 8, 6)
    $row.Background = [System.Windows.Media.Brushes]::Transparent
    $row.Cursor = 'Hand'
    $row.Tag = $Text
    $row.ToolTip = 'Put this in the box'

    $label = New-TextBlock -Text $Text -Size 12.5 -Wrap 'NoWrap'
    $label.TextTrimming = 'CharacterEllipsis'
    $row.Child = $label

    $row.Add_MouseEnter({ param($sender, $eventArgs) $sender.Background = Get-Resource 'CardHoverBg' })
    $row.Add_MouseLeave({ param($sender, $eventArgs) $sender.Background = [System.Windows.Media.Brushes]::Transparent })
    $row.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        # The handler runs long after this function returned, so it must not rely on
        # its parameters; everything is found again from the visual tree.
        $owner = [System.Windows.Window]::GetWindow($sender)
        if ($null -eq $owner) { return }
        $target = Find-VisualChild -Parent $owner -TypeName 'TextBox'
        if ($null -ne $target) {
            # Setting the text raises TextChanged, which would rebuild and reopen the list;
            # the flag keeps it shut for the pick itself.
            $script:RunHistorySuppress = $true
            $target.Text = [string]$sender.Tag
            $script:RunHistorySuppress = $false
            $target.Focus() | Out-Null
            $target.CaretIndex = $target.Text.Length
        }
        $node = [System.Windows.Media.VisualTreeHelper]::GetParent($sender)
        while ($null -ne $node) {
            if ($node -is [System.Windows.Controls.Border] -and $node.Child -is [System.Windows.Controls.ScrollViewer]) {
                $node.Visibility = 'Collapsed'
                break
            }
            $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
        }
    })

    return $row
}

function Show-RunBox {
    $history = @(Get-RunHistoryList)
    $script:RunHistoryPick = -1

    $dialog = New-OverlayDialog -Width 520
    $window = $dialog.Window
    $stack = $dialog.Stack

    [void]$stack.Children.Add((New-TextBlock -Text 'Run' -Size 16 -Weight 'SemiBold' -Font $script:FontDisplay))

    $hint = New-TextBlock -Text 'Opens a program, file, folder or web address - what Win+R does, without leaving PowerKit. Recent entries sit under the box; the arrow keys step through them.' -Size 12 -ColorKey 'TextSecondary' -Wrap 'Wrap'
    $hint.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
    $hint.MaxWidth = 460
    [void]$stack.Children.Add($hint)

    [void]$stack.Children.Add((New-FieldLabel -Text 'Open' -Top 14))

    $box = New-Object System.Windows.Controls.TextBox
    $box.Style = Get-Resource 'InputTextBox'
    [void]$stack.Children.Add($box)

    $drop = New-Object System.Windows.Controls.Border
    $drop.Background = Get-Resource 'CardBg'
    $drop.BorderBrush = Get-Resource 'BorderSubtle'
    $drop.BorderThickness = New-Object System.Windows.Thickness(1)
    $drop.CornerRadius = New-Object System.Windows.CornerRadius(6)
    $drop.Padding = New-Object System.Windows.Thickness(4)
    $drop.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
    $drop.MaxHeight = 224
    $drop.Visibility = 'Collapsed'
    [void]$stack.Children.Add($drop)

    $dropScroll = New-Object System.Windows.Controls.ScrollViewer
    $dropScroll.VerticalScrollBarVisibility = 'Auto'
    $dropScroll.HorizontalScrollBarVisibility = 'Disabled'
    $dropScroll.Padding = New-Object System.Windows.Thickness(0)
    $dropRows = New-Object System.Windows.Controls.StackPanel
    $dropScroll.Content = $dropRows
    $drop.Child = $dropScroll

    # Rebuilt on every keystroke, so the list narrows down as you type.
    $render = {
        if ($script:RunHistorySuppress) { return }
        $dropRows.Children.Clear()
        $query = $box.Text.Trim().ToLowerInvariant()
        $matches = @()
        foreach ($entry in $history) {
            if ($query -and -not $entry.ToLowerInvariant().Contains($query)) { continue }
            $matches += $entry
        }
        if ($matches.Count -eq 0) {
            $drop.Visibility = 'Collapsed'
            return
        }
        $caption = New-TextBlock -Text 'RECENT' -Size 9.5 -Weight 'SemiBold' -ColorKey 'TextTertiary'
        $caption.Margin = New-Object System.Windows.Thickness(8, 6, 8, 4)
        [void]$dropRows.Children.Add($caption)
        foreach ($entry in $matches) {
            [void]$dropRows.Children.Add((New-RunHistoryRow -Text $entry))
        }
        $drop.Visibility = 'Visible'
    }

    $box.Add_TextChanged({ param($sender, $eventArgs) & $render })

    $box.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -ne [System.Windows.Input.Key]::Down -and $eventArgs.Key -ne [System.Windows.Input.Key]::Up) { return }
        if ($history.Count -eq 0) { return }
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Down) {
            $script:RunHistoryPick = ($script:RunHistoryPick + 1) % $history.Count
        } elseif ($script:RunHistoryPick -le 0) {
            $script:RunHistoryPick = $history.Count - 1
        } else {
            $script:RunHistoryPick = $script:RunHistoryPick - 1
        }
        $sender.Text = $history[$script:RunHistoryPick]
        $sender.CaretIndex = $sender.Text.Length
        $eventArgs.Handled = $true
    })

    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = New-Object System.Windows.Thickness(0, 16, 0, 0)
    [void]$stack.Children.Add($buttons)

    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Style = Get-Resource 'BtnSecondary'
    $cancel.Content = 'Cancel'
    $cancel.MinWidth = 92
    $cancel.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $cancel.Add_Click({
        param($sender, $eventArgs)
        $owner = [System.Windows.Window]::GetWindow($sender)
        if ($owner) { $owner.Tag = 'cancel'; $owner.Close() }
    })
    [void]$buttons.Children.Add($cancel)

    $run = New-Object System.Windows.Controls.Button
    $run.Style = Get-Resource 'BtnPrimary'
    $run.Content = 'Run'
    $run.MinWidth = 92
    $run.Add_Click({
        param($sender, $eventArgs)
        $owner = [System.Windows.Window]::GetWindow($sender)
        if ($owner) { $owner.Tag = 'ok'; $owner.Close() }
    })
    [void]$buttons.Children.Add($run)

    $window.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Enter) {
            $sender.Tag = 'ok'
            $sender.Close()
            $eventArgs.Handled = $true
        }
    })

    & $render
    $window.Tag = 'cancel'
    $box.Focus() | Out-Null
    [void]$window.ShowDialog()

    if ($window.Tag -ne 'ok') { return }
    $target = $box.Text.Trim()
    if (-not $target) { return }
    Invoke-RunTarget -Target $target
}

# Reached when the app is opened from a pinned desktop-menu entry. The menu never
# changes a setting on its own, it lands you on the card so you decide from there.
function Show-LaunchFocus {
    param([string]$Id)

    if ([string]::IsNullOrWhiteSpace($Id)) { return }

    $entry = Get-ActionById -Id $Id
    if ($null -eq $entry) { return }

    # The full list with no filter is the only view where every card is present.
    if ($null -ne $script:SearchBox) { $script:SearchBox.Text = '' }
    if ($null -ne $script:NavList -and $script:NavList.Items.Count -gt 0) { $script:NavList.SelectedIndex = 0 }
    if ($entry.ContainsKey('Group') -and (Get-CollapsedGroups).ContainsKey([string]$entry.Group)) {
        Set-SectionCollapsed -GroupId ([string]$entry.Group) -Collapsed $false -Persist
    }

    $target = $null
    if ($script:TweakCards.ContainsKey($Id) -and $script:TweakCards[$Id].Count -gt 0) { $target = $script:TweakCards[$Id][0].Card }
    if ($null -eq $target -and $script:CommandCards.ContainsKey($Id) -and $script:CommandCards[$Id].Count -gt 0) { $target = $script:CommandCards[$Id][0].Card }
    if ($null -eq $target) { return }

    # The section panels only get a real size after Show(), so the scroll has to wait
    # for the dispatcher instead of running straight away.
    $window = $script:Window
    if ($null -ne $window) {
        [void]$window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
            try { $target.BringIntoView() } catch { }
        })
    }

    Show-Toast -Message ("Opened at '{0}'" -f $entry.Title) -Kind 'info'
}

function Start-PowerKit {
    param([string]$Focus = '')

    $script:IsAdmin = Test-IsAdmin
    Initialize-AppData
    Load-AppSettings
    # Custom cards live in custom.json and must be in the catalog before the defaults
    # baseline is captured and the window is built.
    Load-CustomCatalog
    Initialize-Defaults

    # The desktop right-click menu mirrors the pinned cards; rebuilding it on every
    # start keeps it correct after settings are imported or a card is removed.
    Sync-DesktopMenu

    # A theme chosen in an earlier session wins over the Windows setting.
    $savedTheme = [string]$script:Settings['theme']
    if ($savedTheme -eq 'light' -or $savedTheme -eq 'dark') {
        $script:ThemeMode = $savedTheme
        $script:ThemeOverridden = $true
    } else {
        $script:ThemeMode = Get-SystemThemeMode
    }

    # A session marker gives the activity log a starting point on every launch.
    if ($script:IsAdmin) {
        Write-AppLog 'PowerKit started (running as administrator)'
    } else {
        Write-AppLog 'PowerKit started (standard user)'
    }

    $window = Build-MainWindow

    foreach ($group in $script:GroupDefs) { $script:GroupOrder[$group.Id] = [array]::IndexOf($script:GroupDefs, $group) }

    $window.Add_SourceInitialized({
        param($sender, $eventArgs)
        Set-WindowDarkTitleBar -Window $sender -Dark ($script:ThemeMode -eq 'dark')
    })

    Refresh-AllVisuals
    $window.Show()
    Update-GridColumns
    Show-LaunchFocus -Id $Focus
    Update-NavPaneForWidth
    Set-WindowDarkTitleBar -Window $window -Dark ($script:ThemeMode -eq 'dark')
    Start-AppearanceWatch

    $app = New-Object System.Windows.Application
    $app.ShutdownMode = 'OnMainWindowClose'
    [void]$app.Run($window)
}
