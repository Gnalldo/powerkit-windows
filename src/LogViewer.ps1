# LogViewer.ps1 - in-app activity log with filtering, newest first.

$script:LogWindow = $null
$script:LogEntryPanel = $null
$script:LogScroll = $null
$script:LogFilterBox = $null
$script:LogFilterPlaceholder = $null
$script:LogCountText = $null
$script:LogRefreshTimer = $null
$script:LogLastWriteTicks = -1
$script:LogDisplayLimit = 500
$script:LogMonoFont = New-Object System.Windows.Media.FontFamily('Cascadia Mono, Consolas, Courier New')
$script:HighlightCard = $null
$script:HighlightOriginal = $null
$script:HighlightTimer = $null

function ConvertFrom-LogLine {
    param([string]$Line)

    $entry = @{
        Time = ''; Kind = 'INFO'; Text = $Line; Helper = $false
        TweakId = ''; HasTweak = $false; CommandId = ''; HasCommand = $false
        Hive = ''; Path = ''; Name = ''; Was = ''; HasWas = $false
    }

    if ($Line -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+\[helper (\d+)\]\s*(.*)$') {
        $entry.Time = $matches[1]
        $entry.Helper = $true
        $entry.Text = $matches[3]
    } elseif ($Line -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(.*)$') {
        $entry.Time = $matches[1]
        $entry.Text = $matches[2]
    }

    # SET lines start with the catalog id of the tweak that produced them, which is
    # what lets a row jump back to its card.
    if ($entry.Text -match '^SET ([A-Za-z0-9_.-]+)\s') { $entry.TweakId = $matches[1] }

    # RUN lines carry the id of the command that launched them, when a card did.
    if ($entry.Text -match '^RUN ([A-Za-z0-9_.-]+)\s') { $entry.CommandId = $matches[1] }

    # A SET line names the exact value it wrote and what was there before, which is
    # what lets a single row undo that one write.
    if ($entry.Text -match '^SET [A-Za-z0-9_.-]+ (HKCU|HKLM|HKCR)\\(.+?) \[([^\]]+)\] = (.*)$') {
        $entry.Hive = $matches[1]
        $entry.Path = $matches[2]
        $entry.Name = $matches[3]
        if ($matches[4] -match '^(.*) \(was (.*)\)$') {
            $entry.Was = $matches[2]
            $entry.HasWas = $true
        }
    }

    if ($entry.Text -match '^(SET|RUN)\b') {
        $entry.Kind = $matches[1]
    } elseif ($entry.Text -match '(?i)FATAL|failed|error|exception|refused|could not|timed out|rejected') {
        $entry.Kind = 'ERROR'
    } elseif ($entry.Text -match '(?i)elevated helper|administrator approval|authorisation') {
        $entry.Kind = 'ELEVATED'
    }

    return $entry
}

function Read-ActivityLog {
    param([int]$MaxRows = 600)

    $entries = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $script:LogPath)) { return ,$entries }

    $stream = $null
    $reader = $null
    $lines = New-Object System.Collections.ArrayList

    try {
        $stream = [System.IO.File]::Open($script:LogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$lines.Add($line) }
        }
    } catch {
        return ,$entries
    } finally {
        if ($null -ne $reader) { $reader.Dispose() } elseif ($null -ne $stream) { $stream.Dispose() }
    }

    $start = [Math]::Max(0, $lines.Count - $MaxRows)
    for ($i = $start; $i -lt $lines.Count; $i++) {
        [void]$entries.Add((ConvertFrom-LogLine -Line $lines[$i]))
    }
    return ,$entries
}

function Get-LogKindLabel {
    param([string]$Kind)
    switch ($Kind) {
        'SET'      { return 'WRITE' }
        'RUN'      { return 'RUN' }
        'ERROR'    { return 'ERROR' }
        'ELEVATED' { return 'HELPER' }
        default    { return 'INFO' }
    }
}

function Get-LogKindColorKey {
    param([string]$Kind)
    switch ($Kind) {
        'SET'      { return 'Accent' }
        'RUN'      { return 'Accent' }
        'ERROR'    { return 'DangerText' }
        'ELEVATED' { return 'SuccessText' }
        default    { return 'TextTertiary' }
    }
}

function New-LogRow {
    param($Entry)

    $row = New-Object System.Windows.Controls.Border
    $row.BorderBrush = Get-Resource 'Divider'
    $row.BorderThickness = New-Object System.Windows.Thickness(0, 0, 0, 1)
    $row.Padding = New-Object System.Windows.Thickness(4, 5, 6, 5)

    $grid = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = [System.Windows.GridLength]::Auto
    $c2 = New-Object System.Windows.Controls.ColumnDefinition
    $c2.Width = [System.Windows.GridLength]::Auto
    $c3 = New-Object System.Windows.Controls.ColumnDefinition
    $c3.Width = [System.Windows.GridLength]::new(1, 'Star')
    $c4 = New-Object System.Windows.Controls.ColumnDefinition
    $c4.Width = [System.Windows.GridLength]::Auto
    [void]$grid.ColumnDefinitions.Add($c1)
    [void]$grid.ColumnDefinitions.Add($c2)
    [void]$grid.ColumnDefinitions.Add($c3)
    [void]$grid.ColumnDefinitions.Add($c4)

    $stamp = New-TextBlock -Text $(if ($Entry.Time) { $Entry.Time } else { '-' }) -Size 10.5 -ColorKey 'TextTertiary' -Font $script:LogMonoFont
    $stamp.VerticalAlignment = 'Top'
    $stamp.Margin = New-Object System.Windows.Thickness(0, 2, 10, 0)
    [System.Windows.Controls.Grid]::SetColumn($stamp, 0)
    [void]$grid.Children.Add($stamp)

    $badges = New-Object System.Windows.Controls.StackPanel
    $badges.Orientation = 'Horizontal'
    $badges.VerticalAlignment = 'Top'
    $badges.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    [void]$badges.Children.Add((New-Pill -Text (Get-LogKindLabel -Kind $Entry.Kind) -ColorKey (Get-LogKindColorKey -Kind $Entry.Kind) -BgKey 'PillBg'))
    if ($Entry.Helper) {
        [void]$badges.Children.Add((New-Pill -Text 'ADMIN' -ColorKey 'TextTertiary' -BgKey 'PillBg' -Tip 'Written by the elevated helper process'))
    }
    [System.Windows.Controls.Grid]::SetColumn($badges, 1)
    [void]$grid.Children.Add($badges)

    $colorKey = if ($Entry.Kind -eq 'ERROR') { 'DangerText' } else { 'TextPrimary' }
    $text = New-TextBlock -Text $Entry.Text -Size 11.5 -ColorKey $colorKey -Wrap 'Wrap'
    $text.VerticalAlignment = 'Top'
    [System.Windows.Controls.Grid]::SetColumn($text, 2)
    [void]$grid.Children.Add($text)

    $linkKind = ''
    $linkId = ''
    $linkLabel = ''

    if ($Entry.HasTweak) {
        $linkKind = 'tweak'
        $linkId = [string]$Entry.TweakId
        $linkLabel = $linkId
        $tweak = Get-TweakById -Id $linkId
        if ($null -ne $tweak) { $linkLabel = $tweak.Title }
    } elseif ($Entry.HasCommand) {
        $linkKind = 'command'
        $linkId = [string]$Entry.CommandId
        $linkLabel = $linkId
        $command = Get-CommandById -Id $linkId
        if ($null -ne $command) { $linkLabel = $command.Title }
    }

    if ($linkKind -or $Entry.HasWas) {
        $rowActions = New-Object System.Windows.Controls.StackPanel
        $rowActions.Orientation = 'Horizontal'
        $rowActions.VerticalAlignment = 'Top'
        [System.Windows.Controls.Grid]::SetColumn($rowActions, 3)
        [void]$grid.Children.Add($rowActions)

        # A write row knows the value it replaced, so it can put that one back.
        if ($Entry.HasWas -and $Entry.TweakId) {
            $undo = New-Object System.Windows.Controls.Button
            $undo.Style = Get-Resource 'BtnGhost'
            $undo.Content = 'Undo'
            $undo.FontSize = 11
            $undo.Padding = New-Object System.Windows.Thickness(4, 1, 4, 1)
            $undo.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
            $undo.VerticalAlignment = 'Top'
            $undo.Tag = $Entry
            $undo.ToolTip = ('Put {0}\{1} [{2}] back to {3}' -f $Entry.Hive, $Entry.Path, $Entry.Name, $(if ($Entry.Was -eq 'absent') { 'not set at all' } else { $Entry.Was }))
            $undo.Add_Click({
                param($sender, $eventArgs)
                $eventArgs.Handled = $true
                Restore-LogValue -Entry $sender.Tag
            })
            [void]$rowActions.Children.Add($undo)
        }

        if ($linkKind) {
            $chevron = New-TextBlock -Text ([char]0xE76C) -Size 10 -ColorKey 'TextTertiary' -Font $script:FontIcon
            $chevron.VerticalAlignment = 'Top'
            $chevron.Margin = New-Object System.Windows.Thickness(8, 5, 2, 0)
            [void]$rowActions.Children.Add($chevron)
        }
    }

    $row.Child = $grid

    # Rows that belong to a catalog card can jump back to it.
    if ($linkKind) {
        $row.Tag = @{ Kind = $linkKind; Id = $linkId }
        $row.Cursor = 'Hand'
        $row.ToolTip = if ($linkKind -eq 'tweak') { 'Show the "{0}" tweak' -f $linkLabel } else { 'Show the "{0}" command' -f $linkLabel }
        $row.Add_MouseEnter({
            param($sender, $eventArgs)
            $sender.Background = Get-Resource 'RowHoverBg'
        })
        $row.Add_MouseLeave({
            param($sender, $eventArgs)
            $sender.ClearValue([System.Windows.Controls.Border]::BackgroundProperty)
        })
        $row.Add_MouseLeftButtonUp({
            param($sender, $eventArgs)
            $target = $sender.Tag
            if ($null -eq $target) { return }
            if ($target.Kind -eq 'tweak') { Show-TweakFromLog -TweakId $target.Id } else { Show-CommandFromLog -CommandId $target.Id }
        })
    }

    return $row
}

function Restore-LogValue {
    param($Entry)

    if ($null -eq $Entry -or -not $Entry.HasWas) { return }

    $hive = [string]$Entry.Hive
    if ($hive -eq 'HKLM' -and -not $script:IsAdmin) {
        Show-Toast -Message 'That write was machine-wide, so undoing it needs administrator approval. Use Reset on the card instead.' -Kind 'info'
        return
    }

    $kind = 'String'
    $value = $null
    if ([string]$Entry.Was -ne 'absent') {
        $text = [string]$Entry.Was
        if ($text -match '^(DWord|QWord|String|ExpandString|Binary) (.*)$') {
            $kind = $matches[1]
            $text = $matches[2]
        }
        $value = $text
        if ($kind -eq 'DWord' -or $kind -eq 'QWord') {
            $number = [long]0
            if ([long]::TryParse($text, [ref]$number)) { $value = $number }
        }
        if ($kind -eq 'Binary') { $kind = 'String' }
    }

    try {
        Write-RegValue -Hive $hive -Path ([string]$Entry.Path) -Name ([string]$Entry.Name) -Kind $kind -Value $value
        Write-AppLog ("UNDO {0}\{1} [{2}] restored to {3}" -f $hive, $Entry.Path, $Entry.Name, $(if ($null -eq $value) { '<absent>' } else { $value }))

        $tweak = Get-TweakById -Id ([string]$Entry.TweakId)
        if ($null -ne $tweak) {
            Update-TweakVisuals -Tweak $tweak
            Update-PinButtons -Id $tweak.Id
        }
        Sync-ActiveSection
        Sync-PinnedSection
        Update-NavCounts
        Update-SectionCounts
        Show-Toast -Message 'That write was undone' -Kind 'success'

        # The rows below this one are rebuilt after the click handler returns.
        if ($null -ne $script:LogWindow) {
            $script:LogWindow.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                $script:LogLastWriteTicks = -1
                Update-ActivityLogView -Force
            }) | Out-Null
        }
    } catch {
        Show-Toast -Message ('Undo failed: ' + $_.Exception.Message) -Kind 'error'
    }
}

function Update-ActivityLogView {
    param([switch]$Force)

    if ($null -eq $script:LogWindow) { return }

    $lastWrite = -1
    try {
        $file = Get-Item -LiteralPath $script:LogPath -ErrorAction SilentlyContinue
        if ($null -ne $file) { $lastWrite = $file.LastWriteTimeUtc.Ticks }
    } catch { }

    if (-not $Force -and $lastWrite -eq $script:LogLastWriteTicks) { return }
    $script:LogLastWriteTicks = $lastWrite

    $offset = 0
    if ($null -ne $script:LogScroll) { $offset = $script:LogScroll.VerticalOffset }

    $filter = ''
    if ($null -ne $script:LogFilterBox) { $filter = $script:LogFilterBox.Text.Trim().ToLowerInvariant() }

    $entries = Read-ActivityLog -MaxRows 800
    $knownTweaks = @{}
    foreach ($tweak in $script:TweakDefs) { $knownTweaks[$tweak.Id] = $true }
    $knownCommands = @{}
    foreach ($command in $script:CommandDefs) { $knownCommands[$command.Id] = $true }
    $matching = New-Object System.Collections.ArrayList
    foreach ($entry in $entries) {
        if ($entry.TweakId) { $entry.HasTweak = $knownTweaks.ContainsKey($entry.TweakId) }
        if ($entry.CommandId) { $entry.HasCommand = $knownCommands.ContainsKey($entry.CommandId) }
        if ($filter) {
            $haystack = ($entry.Time + ' ' + $entry.Kind + ' ' + $entry.Text).ToLowerInvariant()
            if (-not $haystack.Contains($filter)) { continue }
        }
        [void]$matching.Add($entry)
    }

    $script:LogEntryPanel.Children.Clear()
    $shown = 0
    for ($i = $matching.Count - 1; $i -ge 0; $i--) {
        [void]$script:LogEntryPanel.Children.Add((New-LogRow -Entry $matching[$i]))
        $shown++
        if ($shown -ge $script:LogDisplayLimit) { break }
    }

    if ($shown -eq 0) {
        $empty = New-TextBlock -Text $(if ($filter) { 'No entries match that filter.' } else { 'No activity recorded yet. Toggle a tweak or run a command and it will appear here.' }) -Size 12.5 -ColorKey 'TextTertiary' -Wrap 'Wrap'
        $empty.Margin = New-Object System.Windows.Thickness(6, 18, 6, 0)
        [void]$script:LogEntryPanel.Children.Add($empty)
    }

    if ($null -ne $script:LogCountText) {
        if ($matching.Count -gt $shown) {
            $script:LogCountText.Text = ('newest {0} of {1} entries' -f $shown, $matching.Count)
        } elseif ($matching.Count -eq 1) {
            $script:LogCountText.Text = '1 entry'
        } else {
            $script:LogCountText.Text = ('{0} entries' -f $matching.Count)
        }
    }

    if ($null -ne $script:LogScroll) { $script:LogScroll.ScrollToVerticalOffset($offset) }
}

function Open-ActivityLogFolder {
    try {
        Initialize-AppData
        Invoke-StartProcess -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $script:LogPath)
    } catch {
        Show-Toast -Message $_.Exception.Message -Kind 'error'
    }
}

function Clear-ActivityLog {
    $answer = Show-Dialog -Title 'Clear the activity log?' -Message 'Every recorded registry write and command, including the rotated archives, will be deleted. This cannot be undone.' -Primary 'Clear log' -Secondary 'Cancel' -Danger -Owner $script:LogWindow
    if ($answer -ne 'primary') { return }

    foreach ($path in @($script:LogPath, "$($script:LogPath).1", "$($script:LogPath).2")) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    $script:LogLastWriteTicks = -1
    Update-ActivityLogView -Force
    Show-Toast -Message 'Activity log cleared' -Kind 'success'
}

function Get-TweakCardTarget {
    param([string]$TweakId)

    if (-not $script:TweakCards.ContainsKey($TweakId)) { return $null }

    $compact = $null
    foreach ($instance in $script:TweakCards[$TweakId]) {
        $card = $instance.Card
        # Cards from an earlier render are detached; only a live one can be revealed.
        if ($null -eq $card -or $null -eq $card.Parent) { continue }
        if ($instance.ContainsKey('Compact') -and $instance.Compact) {
            if ($null -eq $compact) { $compact = $card }
            continue
        }
        return $card
    }
    return $compact
}

function Get-CommandCardTarget {
    param([string]$CommandId)

    if (-not $script:CommandCards.ContainsKey($CommandId)) { return $null }

    foreach ($instance in $script:CommandCards[$CommandId]) {
        $card = $instance.Card
        if ($null -ne $card -and $null -ne $card.Parent) { return $card }
    }
    return $null
}

function Clear-TweakHighlight {
    if ($null -ne $script:HighlightTimer) {
        $script:HighlightTimer.Stop()
        $script:HighlightTimer = $null
    }

    $card = $script:HighlightCard
    $original = $script:HighlightOriginal
    $script:HighlightCard = $null
    $script:HighlightOriginal = $null
    if ($null -eq $card) { return }

    # Put back exactly what the card had: its own local value when it had one,
    # otherwise nothing so the style (or the default) applies again.
    try {
        if (-not [object]::ReferenceEquals($original.Brush, [System.Windows.DependencyProperty]::UnsetValue)) {
            $card.BorderBrush = $original.Brush
        } else {
            $card.ClearValue([System.Windows.Controls.Border]::BorderBrushProperty)
        }
        if (-not [object]::ReferenceEquals($original.Thickness, [System.Windows.DependencyProperty]::UnsetValue)) {
            $card.BorderThickness = $original.Thickness
        } else {
            $card.ClearValue([System.Windows.Controls.Border]::BorderThicknessProperty)
        }
        if (-not [object]::ReferenceEquals($original.Effect, [System.Windows.DependencyProperty]::UnsetValue)) {
            $card.Effect = $original.Effect
        } else {
            $card.ClearValue([System.Windows.UIElement]::EffectProperty)
        }
    } catch { }
}

function Show-TweakCardHighlight {
    param($Card)

    Clear-TweakHighlight
    if ($null -eq $Card) { return }
    $script:HighlightCard = $Card
    $script:HighlightOriginal = @{
        Brush     = $Card.ReadLocalValue([System.Windows.Controls.Border]::BorderBrushProperty)
        Thickness = $Card.ReadLocalValue([System.Windows.Controls.Border]::BorderThicknessProperty)
        Effect    = $Card.ReadLocalValue([System.Windows.UIElement]::EffectProperty)
    }

    $accent = Get-Resource 'Accent'
    $Card.BorderBrush = $accent
    $Card.BorderThickness = New-Object System.Windows.Thickness(2)
    try {
        $glow = New-Object System.Windows.Media.Effects.DropShadowEffect
        $glow.BlurRadius = 16
        $glow.ShadowDepth = 0
        $glow.Opacity = 0.8
        if ($accent -is [System.Windows.Media.SolidColorBrush]) { $glow.Color = $accent.Color }
        $Card.Effect = $glow
    } catch { }

    # Wait for the filter change to lay out, then bring the card into view.
    if ($null -ne $script:Window) {
        $script:Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
            if ($null -ne $script:HighlightCard) {
                try { $script:HighlightCard.BringIntoView() } catch { }
            }
        }) | Out-Null
    }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(2.6)
    $timer.Add_Tick({
        param($sender, $eventArgs)
        Clear-TweakHighlight
    })
    $script:HighlightTimer = $timer
    $timer.Start()
}

function Set-NavToGroup {
    param([string]$Group)

    if ($null -eq $script:NavList) { return }

    $target = $null
    foreach ($item in $script:NavList.Items) {
        if ($null -ne $item.Tag -and [string]$item.Tag -eq $Group) { $target = $item; break }
    }
    if ($null -eq $target) {
        foreach ($item in $script:NavList.Items) {
            if ($null -ne $item.Tag -and [string]$item.Tag -eq 'all') { $target = $item; break }
        }
    }

    if ($null -ne $target) { $script:NavList.SelectedItem = $target }
    $script:CurrentNav = if ($null -ne $target) { [string]$target.Tag } else { 'all' }
    Expand-SectionForNav -GroupId $script:CurrentNav
    Update-Filter
}

# Jumps from an activity-log row to the card that produced the write.
function Show-TweakFromLog {
    param([string]$TweakId)

    $tweak = Get-TweakById -Id $TweakId
    if ($null -eq $tweak) {
        Show-Toast -Message ("'{0}' is no longer part of the tweak catalog." -f $TweakId) -Kind 'error'
        return
    }
    if ($null -eq $script:Window) { return }

    # The log is owned by the main window, so it would cover the card we reveal.
    if ($null -ne $script:LogWindow) {
        try { $script:LogWindow.Close() } catch { $script:LogWindow = $null }
    }

    if ($script:Window.WindowState -eq 'Minimized') { $script:Window.WindowState = 'Normal' }
    [void]$script:Window.Activate()

    # A leftover search or the Active view could hide the card entirely.
    if ($null -ne $script:SearchBox -and $script:SearchBox.Text.Length -gt 0) { $script:SearchBox.Text = '' }
    Set-NavToGroup -Group $tweak.Group

    $card = Get-TweakCardTarget -TweakId $tweak.Id
    if ($null -eq $card) {
        Show-Toast -Message ("No card is available for '{0}'." -f $tweak.Title) -Kind 'error'
        return
    }

    Show-TweakCardHighlight -Card $card
}

# Jumps from an activity-log row to the command card that launched it.
function Show-CommandFromLog {
    param([string]$CommandId)

    $command = Get-CommandById -Id $CommandId
    if ($null -eq $command) {
        Show-Toast -Message ("'{0}' is no longer part of the command list." -f $CommandId) -Kind 'error'
        return
    }
    if ($null -eq $script:Window) { return }

    if ($null -ne $script:LogWindow) {
        try { $script:LogWindow.Close() } catch { $script:LogWindow = $null }
    }

    if ($script:Window.WindowState -eq 'Minimized') { $script:Window.WindowState = 'Normal' }
    [void]$script:Window.Activate()

    if ($null -ne $script:SearchBox -and $script:SearchBox.Text.Length -gt 0) { $script:SearchBox.Text = '' }
    Set-NavToGroup -Group $command.Group

    $card = Get-CommandCardTarget -CommandId $command.Id
    if ($null -eq $card) {
        Show-Toast -Message ("No card is available for '{0}'." -f $command.Title) -Kind 'error'
        return
    }

    Show-TweakCardHighlight -Card $card
}

function Show-ActivityLog {
    if ($null -ne $script:LogWindow) {
        try {
            $script:LogWindow.Activate()
            Update-ActivityLogView -Force
            return
        } catch {
            $script:LogWindow = $null
        }
    }

    $window = New-Object System.Windows.Window
    $window.Title = 'PowerKit - activity log'
    $window.Width = 880
    $window.Height = 600
    $window.MinWidth = 560
    $window.MinHeight = 320
    $window.WindowStartupLocation = 'CenterOwner'
    $window.Background = Get-Resource 'WindowBg'
    $window.FontFamily = $script:FontText
    $window.ShowInTaskbar = $false
    $window.UseLayoutRounding = $true
    [System.Windows.Media.TextOptions]::SetTextFormattingMode($window, 'Display')
    Add-AppResources -Resources $window.Resources -Mode $script:ThemeMode
    Register-ThemeWindow -Window $window
    # An owner must already be shown; fall back to an unowned window rather than failing to open.
    try { if ($null -ne $script:Window) { $window.Owner = $script:Window } } catch { }

    $root = New-Object System.Windows.Controls.Grid
    $r0 = New-Object System.Windows.Controls.RowDefinition
    $r0.Height = [System.Windows.GridLength]::Auto
    $r1 = New-Object System.Windows.Controls.RowDefinition
    $r1.Height = [System.Windows.GridLength]::Auto
    $r2 = New-Object System.Windows.Controls.RowDefinition
    $r2.Height = [System.Windows.GridLength]::new(1, 'Star')
    [void]$root.RowDefinitions.Add($r0)
    [void]$root.RowDefinitions.Add($r1)
    [void]$root.RowDefinitions.Add($r2)

    # ---------- header ----------
    $header = New-Object System.Windows.Controls.Border
    $header.Background = Get-Resource 'HeaderBg'
    $header.BorderBrush = Get-Resource 'Divider'
    $header.BorderThickness = New-Object System.Windows.Thickness(0, 0, 0, 1)
    $header.Padding = New-Object System.Windows.Thickness(20, 14, 20, 12)
    [System.Windows.Controls.Grid]::SetRow($header, 0)
    [void]$root.Children.Add($header)

    $headerGrid = New-Object System.Windows.Controls.Grid
    $hc1 = New-Object System.Windows.Controls.ColumnDefinition
    $hc1.Width = [System.Windows.GridLength]::new(1, 'Star')
    $hc2 = New-Object System.Windows.Controls.ColumnDefinition
    $hc2.Width = [System.Windows.GridLength]::Auto
    [void]$headerGrid.ColumnDefinitions.Add($hc1)
    [void]$headerGrid.ColumnDefinitions.Add($hc2)
    $header.Child = $headerGrid

    $titleStack = New-Object System.Windows.Controls.StackPanel
    $titleStack.VerticalAlignment = 'Center'
    $title = New-TextBlock -Text 'Activity log' -Size 18 -Weight 'SemiBold' -Font $script:FontDisplay
    $subtitle = New-TextBlock -Text 'Every registry write and command PowerKit has recorded, newest first.' -Size 11.5 -ColorKey 'TextTertiary' -Wrap 'Wrap'
    $subtitle.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    [void]$titleStack.Children.Add($title)
    [void]$titleStack.Children.Add($subtitle)
    [void]$headerGrid.Children.Add($titleStack)

    $actions = New-Object System.Windows.Controls.StackPanel
    $actions.Orientation = 'Horizontal'
    $actions.VerticalAlignment = 'Center'
    $actions.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($actions, 1)
    [void]$headerGrid.Children.Add($actions)

    $refresh = New-Object System.Windows.Controls.Button
    $refresh.Style = Get-Resource 'BtnSecondary'
    $refresh.Content = 'Refresh'
    $refresh.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $refresh.Add_Click({
        param($sender, $eventArgs)
        $script:LogLastWriteTicks = -1
        Update-ActivityLogView -Force
    })
    [void]$actions.Children.Add($refresh)

    $openFolder = New-Object System.Windows.Controls.Button
    $openFolder.Style = Get-Resource 'BtnSecondary'
    $openFolder.Content = 'Open folder'
    $openFolder.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $openFolder.ToolTip = 'Show app.log in File Explorer'
    $openFolder.Add_Click({ Open-ActivityLogFolder })
    [void]$actions.Children.Add($openFolder)

    $clear = New-Object System.Windows.Controls.Button
    $clear.Style = Get-Resource 'BtnSecondary'
    $clear.Content = 'Clear log'
    $clear.Add_Click({ Clear-ActivityLog })
    [void]$actions.Children.Add($clear)

    # ---------- filter ----------
    $filterRow = New-Object System.Windows.Controls.Grid
    $filterRow.Margin = New-Object System.Windows.Thickness(20, 10, 20, 8)
    $fc1 = New-Object System.Windows.Controls.ColumnDefinition
    $fc1.Width = [System.Windows.GridLength]::new(1, 'Star')
    $fc2 = New-Object System.Windows.Controls.ColumnDefinition
    $fc2.Width = [System.Windows.GridLength]::Auto
    [void]$filterRow.ColumnDefinitions.Add($fc1)
    [void]$filterRow.ColumnDefinitions.Add($fc2)
    [System.Windows.Controls.Grid]::SetRow($filterRow, 1)
    [void]$root.Children.Add($filterRow)

    $filterBorder = New-Object System.Windows.Controls.Border
    $filterBorder.Height = 32
    $filterBorder.MaxWidth = 340
    $filterBorder.HorizontalAlignment = 'Left'
    $filterBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
    $filterBorder.Background = Get-Resource 'InputBg'
    $filterBorder.BorderBrush = Get-Resource 'BorderSubtle'
    $filterBorder.BorderThickness = New-Object System.Windows.Thickness(1)

    $filterGrid = New-Object System.Windows.Controls.Grid
    $fg1 = New-Object System.Windows.Controls.ColumnDefinition
    $fg1.Width = [System.Windows.GridLength]::Auto
    $fg2 = New-Object System.Windows.Controls.ColumnDefinition
    $fg2.Width = [System.Windows.GridLength]::new(1, 'Star')
    [void]$filterGrid.ColumnDefinitions.Add($fg1)
    [void]$filterGrid.ColumnDefinitions.Add($fg2)

    $filterIcon = New-TextBlock -Text ([char]0xE721) -Size 12 -ColorKey 'TextTertiary' -Font $script:FontIcon
    $filterIcon.Margin = New-Object System.Windows.Thickness(10, 0, 8, 0)
    $filterIcon.VerticalAlignment = 'Center'
    [void]$filterGrid.Children.Add($filterIcon)

    $filterBox = New-Object System.Windows.Controls.TextBox
    $filterBox.Style = Get-Resource 'SearchTextBox'
    $filterBox.VerticalAlignment = 'Center'
    $filterBox.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
    $filterBox.Add_TextChanged({
        param($sender, $eventArgs)
        $script:LogFilterPlaceholder.Visibility = if ($sender.Text.Length -eq 0) { 'Visible' } else { 'Collapsed' }
        Update-ActivityLogView -Force
    })
    $script:LogFilterBox = $filterBox
    [System.Windows.Controls.Grid]::SetColumn($filterBox, 1)
    [void]$filterGrid.Children.Add($filterBox)

    $filterPlaceholder = New-TextBlock -Text 'Filter entries' -Size 12 -ColorKey 'TextTertiary'
    $filterPlaceholder.VerticalAlignment = 'Center'
    $filterPlaceholder.IsHitTestVisible = $false
    $script:LogFilterPlaceholder = $filterPlaceholder
    [System.Windows.Controls.Grid]::SetColumn($filterPlaceholder, 1)
    [void]$filterGrid.Children.Add($filterPlaceholder)

    $filterBorder.Child = $filterGrid
    [System.Windows.Controls.Grid]::SetColumn($filterBorder, 0)
    [void]$filterRow.Children.Add($filterBorder)

    $countText = New-TextBlock -Text '' -Size 11 -ColorKey 'TextTertiary'
    $countText.VerticalAlignment = 'Center'
    $countText.HorizontalAlignment = 'Right'
    $countText.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
    $script:LogCountText = $countText
    [System.Windows.Controls.Grid]::SetColumn($countText, 1)
    [void]$filterRow.Children.Add($countText)

    # ---------- entries ----------
    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $scroll.HorizontalScrollBarVisibility = 'Disabled'
    $scroll.Padding = New-Object System.Windows.Thickness(18, 0, 8, 12)
    [System.Windows.Controls.Grid]::SetRow($scroll, 2)
    [void]$root.Children.Add($scroll)
    $script:LogScroll = $scroll

    $panel = New-Object System.Windows.Controls.StackPanel
    $scroll.Content = $panel
    $script:LogEntryPanel = $panel

    $window.Content = $root
    $window.Add_SourceInitialized({
        param($sender, $eventArgs)
        Set-WindowDarkTitleBar -Window $sender -Dark ($script:ThemeMode -eq 'dark')
    })
    $window.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            $sender.Close()
            $eventArgs.Handled = $true
        } elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::F5) {
            $script:LogLastWriteTicks = -1
            Update-ActivityLogView -Force
            $eventArgs.Handled = $true
        }
    })
    $window.Add_Closed({
        param($sender, $eventArgs)
        if ($null -ne $script:LogRefreshTimer) {
            $script:LogRefreshTimer.Stop()
            $script:LogRefreshTimer = $null
        }
        $script:LogWindow = $null
    })

    $script:LogWindow = $window
    $script:LogLastWriteTicks = -1
    $window.Show()
    Update-ActivityLogView -Force

    # Live refresh while the window stays open.
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(3)
    $timer.Add_Tick({
        param($sender, $eventArgs)
        if ($null -eq $script:LogWindow) { $sender.Stop(); return }
        Update-ActivityLogView
    })
    $script:LogRefreshTimer = $timer
    $timer.Start()
}
