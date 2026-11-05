# Ui.ps1 - builds the window, navigation, sections, cards and responsive grid.

$script:Window = $null
$script:ContentStack = $null
$script:CardPanels = New-Object System.Collections.ArrayList
$script:Sections = New-Object System.Collections.ArrayList
$script:TweakCards = @{}
$script:CommandCards = @{}
$script:ActiveSection = $null
$script:ActivePanel = $null
$script:ActiveCountText = $null
$script:SearchBox = $null
$script:SearchPlaceholder = $null
$script:NavList = $null
$script:NavColumn = $null
$script:HeaderSubtitle = $null
$script:PendingBanner = $null
$script:PendingText = $null
$script:NoResults = $null
$script:SectionMap = @{}
$script:CollapsedGroups = $null
$script:PinnedCards = $null
$script:PinnedSection = $null
$script:PinnedPanel = $null
$script:PinnedCountText = $null
$script:CurrentNav = 'all'
$script:NavForceHidden = $false
$script:NavForceShown = $false
$script:ToastBorder = $null
$script:ToastText = $null
$script:ToastTimer = $null
$script:PendingRestarts = @{}
$script:IsAdmin = $false

$script:FontText = New-Object System.Windows.Media.FontFamily('Segoe UI Variable Text, Segoe UI')
$script:FontDisplay = New-Object System.Windows.Media.FontFamily('Segoe UI Variable Display, Segoe UI')
$script:FontIcon = New-Object System.Windows.Media.FontFamily('Segoe Fluent Icons, Segoe MDL2 Assets')

function Get-Resource {
    param([string]$Key)

    # Palette brushes come from their mutable master so elements built here recolour in
    # place; styles resolve the dictionary copy instead, which WPF freezes.
    if ($null -ne $script:ThemeBrushes -and $script:ThemeBrushes.ContainsKey($Key)) { return $script:ThemeBrushes[$Key] }
    return $script:Window.Resources[$Key]
}

function Add-AppResources {
    param($Resources, [string]$Mode)

    # Each window is its own visual tree and {DynamicResource} does not cross that
    # boundary, so every window needs the style dictionary and a copy of the palette.
    $stylesPath = Join-Path $script:AppRoot 'src\Styles.xaml'
    $dictionary = New-Object System.Windows.ResourceDictionary
    # ResourceDictionary is an IDictionary, and PowerShell resolves property
    # assignment through the dictionary indexer first, so `$dictionary.Source = ...`
    # only adds an entry named "Source" and never loads the file. Call the CLR
    # property setter so Styles.xaml is really parsed into the dictionary.
    $dictionary.set_Source((New-Object System.Uri($stylesPath, [System.UriKind]::Absolute)))
    [void]$Resources.MergedDictionaries.Add($dictionary)
    Set-ThemeResources -Resources $Resources -Mode $Mode
}

function New-TextBlock {
    param(
        [string]$Text = '',
        [double]$Size = 13,
        [string]$Weight = 'Normal',
        [string]$ColorKey = 'TextPrimary',
        $Font = $null,
        [string]$Wrap = 'NoWrap',
        [double]$Margin = 0
    )

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.FontSize = $Size
    switch ($Weight) {
        'Bold'     { $tb.FontWeight = [System.Windows.FontWeights]::Bold }
        'SemiBold' { $tb.FontWeight = [System.Windows.FontWeights]::SemiBold }
        'Light'    { $tb.FontWeight = [System.Windows.FontWeights]::Light }
        default    { $tb.FontWeight = [System.Windows.FontWeights]::Normal }
    }
    $tb.Foreground = Get-Resource $ColorKey
    $tb.FontFamily = if ($Font) { $Font } else { $script:FontText }
    $tb.TextWrapping = $Wrap
    if ($Margin -ne 0) { $tb.Margin = New-Object System.Windows.Thickness($Margin) }
    return $tb
}

function New-Pill {
    param([string]$Text, [string]$ColorKey = 'PillText', [string]$BgKey = 'PillBg', [string]$Tip = '')

    $border = New-Object System.Windows.Controls.Border
    $border.Background = Get-Resource $BgKey
    $border.CornerRadius = New-Object System.Windows.CornerRadius(3)
    $border.Padding = New-Object System.Windows.Thickness(6, 1, 6, 2)
    $border.VerticalAlignment = 'Center'
    $border.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)

    $label = New-TextBlock -Text $Text -Size 10.5 -ColorKey $ColorKey -Weight 'SemiBold'
    $border.Child = $label
    if ($Tip) { $border.ToolTip = $Tip }
    return $border
}

function New-WarningBox {
    param([string]$Text)

    $border = New-Object System.Windows.Controls.Border
    $border.Background = Get-Resource 'WarnBg'
    $border.BorderBrush = Get-Resource 'WarnBorder'
    $border.BorderThickness = New-Object System.Windows.Thickness(1)
    $border.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $border.Padding = New-Object System.Windows.Thickness(8, 6, 8, 6)
    $border.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)

    $grid = New-Object System.Windows.Controls.Grid
    $col1 = New-Object System.Windows.Controls.ColumnDefinition
    $col1.Width = [System.Windows.GridLength]::Auto
    $col2 = New-Object System.Windows.Controls.ColumnDefinition
    $col2.Width = [System.Windows.GridLength]::new(1, 'Star')
    [void]$grid.ColumnDefinitions.Add($col1)
    [void]$grid.ColumnDefinitions.Add($col2)

    $mark = New-Object System.Windows.Controls.Border
    $mark.Width = 14
    $mark.Height = 14
    $mark.CornerRadius = New-Object System.Windows.CornerRadius(7)
    $mark.Background = Get-Resource 'WarnGlyph'
    $mark.VerticalAlignment = 'Top'
    $mark.Margin = New-Object System.Windows.Thickness(0, 1, 7, 0)
    $mark.Child = (New-TextBlock -Text '!' -Size 9.5 -Weight 'Bold' -ColorKey 'CardBg' -Wrap 'Wrap')
    $mark.Child.HorizontalAlignment = 'Center'
    $mark.Child.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($mark, 0)
    [void]$grid.Children.Add($mark)

    $body = New-TextBlock -Text $Text -Size 11.5 -ColorKey 'WarnText' -Wrap 'Wrap'
    $body.Margin = New-Object System.Windows.Thickness(0, 0, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($body, 1)
    [void]$grid.Children.Add($body)

    $border.Child = $grid
    return $border
}

function New-ToggleControl {
    param([string]$Id, [bool]$Checked, [string]$Tip = 'Toggle this tweak')

    $toggle = New-Object System.Windows.Controls.Primitives.ToggleButton
    $toggle.Style = Get-Resource 'ToggleSwitch'
    $toggle.IsChecked = $Checked
    $toggle.Tag = $Id
    $toggle.ToolTip = $Tip
    $toggle.VerticalAlignment = 'Center'
    $toggle.Add_Click({
        param($sender, $eventArgs)
        Set-TweakFromUi -Id ([string]$sender.Tag) -Desired ([bool]$sender.IsChecked)
    })
    return $toggle
}

function New-ResetButton {
    param([string]$Id)

    $button = New-Object System.Windows.Controls.Button
    $button.Style = Get-Resource 'BtnGhost'
    $button.Content = 'Reset'
    $button.Tag = $Id
    $button.VerticalAlignment = 'Center'
    $button.ToolTip = 'Restore this tweak to the value captured when PowerKit first ran'
    $button.Visibility = 'Collapsed'
    $button.Add_Click({
        param($sender, $eventArgs)
        Reset-TweakFromUi -Id ([string]$sender.Tag)
    })
    return $button
}

function New-DeleteButton {
    param([string]$Id)

    $button = New-Object System.Windows.Controls.Button
    $button.Style = Get-Resource 'BtnGhost'
    $button.Content = 'Remove'
    $button.Tag = $Id
    $button.VerticalAlignment = 'Center'
    $button.ToolTip = 'Remove this AI-drafted card from PowerKit. Nothing in the registry is changed.'
    $button.Add_Click({
        param($sender, $eventArgs)
        Remove-CustomAction -Id ([string]$sender.Tag)
    })
    return $button
}

function New-ChromeButton {
    param([int]$Glyph, [string]$Tip, [string]$Action)

    $button = New-Object System.Windows.Controls.Button
    $button.Style = Get-Resource 'BtnIcon'
    $button.Content = New-TextBlock -Text ([char]$Glyph) -Size 11 -Font $script:FontIcon -ColorKey 'TextSecondary'
    $button.ToolTip = $Tip
    $button.Tag = $Action
    $button.Padding = New-Object System.Windows.Thickness(9, 6, 9, 6)
    $button.Margin = New-Object System.Windows.Thickness(2, 0, 0, 0)
    $button.VerticalAlignment = 'Center'
    $button.Add_Click({
        param($sender, $eventArgs)
        Invoke-ChromeAction -Action ([string]$sender.Tag)
    })
    return $button
}

# The header is the caption bar now, so clicks on a real control must not start a drag.
function Test-ClickOnInteractive {
    param($Source)

    $node = $Source
    while ($null -ne $node) {
        if ($node -is [System.Windows.Controls.Primitives.ButtonBase]) { return $true }
        if ($node -is [System.Windows.Controls.TextBox]) { return $true }
        if ($node -is [System.Windows.Controls.Primitives.Thumb]) { return $true }
        if ($node -is [System.Windows.Controls.ListBoxItem]) { return $true }
        try { $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node) } catch { return $false }
    }
    return $false
}
# One place decides how a pin looks and what it promises, so the full cards, the
# pinned strip and the desktop menu never describe the same pin differently.
function Set-PinButtonState {
    param($Button, [bool]$Pinned)

    if ($null -eq $Button) { return }
    $Button.Content = New-TextBlock -Text ([char]0xE718) -Size 11 -Font $script:FontIcon -ColorKey $(if ($Pinned) { 'Accent' } else { 'TextTertiary' })
    $Button.ToolTip = if ($Pinned) {
        'Pinned to the top of the list and the desktop right-click menu - click to unpin'
    } else {
        'Pin this card to the top of the list and the desktop right-click menu'
    }
}

function New-PinButton {
    param([string]$Id)

    $button = New-Object System.Windows.Controls.Button
    $button.Style = Get-Resource 'BtnIcon'
    $button.Padding = New-Object System.Windows.Thickness(4, 1, 4, 1)
    $button.Margin = New-Object System.Windows.Thickness(0, 0, 2, 0)
    $button.VerticalAlignment = 'Center'
    $button.Tag = $Id
    Set-PinButtonState -Button $button -Pinned ((Get-PinnedCards).Contains([string]$Id))
    $button.Add_Click({
        param($sender, $eventArgs)
        $eventArgs.Handled = $true
        Toggle-PinFromUi -Id ([string]$sender.Tag)
    })
    return $button
}

function Register-TweakCard {
    param([string]$Id, $Card, $Toggle, $Reset, $Pin = $null, [switch]$Compact)

    if (-not $script:TweakCards.ContainsKey($Id)) { $script:TweakCards[$Id] = New-Object System.Collections.ArrayList }
    [void]$script:TweakCards[$Id].Add(@{ Card = $Card; Toggle = $Toggle; Reset = $Reset; Pin = $Pin; Compact = [bool]$Compact })
}

function New-Badges {
    param($Tweak)

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Orientation = 'Horizontal'
    $stack.VerticalAlignment = 'Center'
    $stack.HorizontalAlignment = 'Right'

    $isTweak = $Tweak.ContainsKey('Values')
    if ($Tweak.ContainsKey('Custom') -and $Tweak.Custom) {
        [void]$stack.Children.Add((New-Pill -Text 'AI' -ColorKey 'Accent' -BgKey 'AccentSoft' -Tip 'Drafted by the AI builder from your description. Remove it any time with the Remove button on the card.'))
    }
    if ($Tweak.Admin) {
        [void]$stack.Children.Add((New-Pill -Text 'ADMIN' -ColorKey 'TextTertiary' -BgKey 'PillBg' -Tip 'Machine-wide setting. The first change in a session asks for administrator approval, then applies in place.'))
    }
    switch ($Tweak.Risk) {
        'caution'  { [void]$stack.Children.Add((New-Pill -Text 'CAUTION' -ColorKey 'WarnGlyph' -BgKey 'PillBg' -Tip 'Changes a visible behaviour. Easy to undo with Reset.')) }
        'advanced' { [void]$stack.Children.Add((New-Pill -Text 'ADVANCED' -ColorKey 'DangerText' -BgKey 'PillBg' -Tip 'System-wide change with real consequences. Read the warning first.')) }
    }
    if ($isTweak -and -not $Tweak.Admin) {
        $tip = New-TextBlock -Text ([char]0xE72E) -Size 11 -ColorKey 'TextTertiary' -Font $script:FontIcon
        $tip.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)
        $tip.VerticalAlignment = 'Center'
        $tip.ToolTip = 'User-level tweak. Applies instantly without administrator rights.'
        [void]$stack.Children.Add($tip)
    }
    return $stack
}

function Get-RestartHint {
    param([string]$Restart)
    switch ($Restart) {
        'explorer' { return 'Restart Explorer to apply' }
        'signout'  { return 'Sign out to apply' }
        'reboot'   { return 'Restart PC to apply' }
        default    { return '' }
    }
}

function New-TweakCard {
    param($Tweak, [switch]$Compact)

    $card = New-Object System.Windows.Controls.Border
    $card.Margin = New-Object System.Windows.Thickness(6)
    $card.MinHeight = $(if ($Compact) { 52 } else { 132 })

    $toggle = New-ToggleControl -Id $Tweak.Id -Checked $false -Tip ('Turn this tweak on or off. Current state is read live from the registry.')
    $reset = New-ResetButton -Id $Tweak.Id
    $pin = $null

    if ($Compact) {
        $card.Style = Get-Resource 'CardActive'
        $card.Padding = New-Object System.Windows.Thickness(12, 8, 10, 8)
        $grid = New-Object System.Windows.Controls.Grid
        $c1 = New-Object System.Windows.Controls.ColumnDefinition
        $c1.Width = [System.Windows.GridLength]::new(1, 'Star')
        $c2 = New-Object System.Windows.Controls.ColumnDefinition
        $c2.Width = [System.Windows.GridLength]::Auto
        $c3 = New-Object System.Windows.Controls.ColumnDefinition
        $c3.Width = [System.Windows.GridLength]::Auto
        [void]$grid.ColumnDefinitions.Add($c1)
        [void]$grid.ColumnDefinitions.Add($c2)
        [void]$grid.ColumnDefinitions.Add($c3)

        $titleStack = New-Object System.Windows.Controls.StackPanel
        $titleStack.VerticalAlignment = 'Center'
        $title = New-TextBlock -Text $Tweak.Title -Size 13 -Weight 'SemiBold'
        $title.TextTrimming = 'CharacterEllipsis'
        $title.ToolTip = $Tweak.Title
        $groupTitle = ''
        foreach ($group in $script:GroupDefs) { if ($group.Id -eq $Tweak.Group) { $groupTitle = $group.Title } }
        $sub = New-TextBlock -Text $groupTitle -Size 10.5 -ColorKey 'TextTertiary'
        [void]$titleStack.Children.Add($title)
        [void]$titleStack.Children.Add($sub)
        [System.Windows.Controls.Grid]::SetColumn($titleStack, 0)
        [void]$grid.Children.Add($titleStack)

        $reset.Margin = New-Object System.Windows.Thickness(0, 0, 4, 0)
        [System.Windows.Controls.Grid]::SetColumn($reset, 1)
        [void]$grid.Children.Add($reset)
        [System.Windows.Controls.Grid]::SetColumn($toggle, 2)
        [void]$grid.Children.Add($toggle)

        $card.Child = $grid
    } else {
        $card.Style = Get-Resource 'Card'

        $grid = New-Object System.Windows.Controls.Grid
        $r1 = New-Object System.Windows.Controls.RowDefinition
        $r1.Height = [System.Windows.GridLength]::Auto
        $r2 = New-Object System.Windows.Controls.RowDefinition
        $r2.Height = [System.Windows.GridLength]::Auto
        $r3 = New-Object System.Windows.Controls.RowDefinition
        $r3.Height = [System.Windows.GridLength]::new(1, 'Star')
        $r4 = New-Object System.Windows.Controls.RowDefinition
        $r4.Height = [System.Windows.GridLength]::Auto
        [void]$grid.RowDefinitions.Add($r1)
        [void]$grid.RowDefinitions.Add($r2)
        [void]$grid.RowDefinitions.Add($r3)
        [void]$grid.RowDefinitions.Add($r4)

        $head = New-Object System.Windows.Controls.Grid
        $hc1 = New-Object System.Windows.Controls.ColumnDefinition
        $hc1.Width = [System.Windows.GridLength]::new(1, 'Star')
        $hc2 = New-Object System.Windows.Controls.ColumnDefinition
        $hc2.Width = [System.Windows.GridLength]::Auto
        $hc3 = New-Object System.Windows.Controls.ColumnDefinition
        $hc3.Width = [System.Windows.GridLength]::Auto
        [void]$head.ColumnDefinitions.Add($hc1)
        [void]$head.ColumnDefinitions.Add($hc2)
        [void]$head.ColumnDefinitions.Add($hc3)

        $title = New-TextBlock -Text $Tweak.Title -Size 13.5 -Weight 'SemiBold'
        $title.TextTrimming = 'CharacterEllipsis'
        $title.ToolTip = $Tweak.Title
        $title.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
        [void]$head.Children.Add($title)

        $pin = New-PinButton -Id $Tweak.Id
        [System.Windows.Controls.Grid]::SetColumn($pin, 1)
        [void]$head.Children.Add($pin)

        $badges = New-Badges -Tweak $Tweak
        [System.Windows.Controls.Grid]::SetColumn($badges, 2)
        [void]$head.Children.Add($badges)
        [System.Windows.Controls.Grid]::SetRow($head, 0)
        [void]$grid.Children.Add($head)

        $desc = New-TextBlock -Text $Tweak.Desc -Size 12 -ColorKey 'TextSecondary' -Wrap 'Wrap'
        $desc.Margin = New-Object System.Windows.Thickness(0, 5, 0, 0)
        $desc.MaxHeight = 54
        $desc.TextTrimming = 'WordEllipsis'
        $desc.ToolTip = $Tweak.Desc
        [System.Windows.Controls.Grid]::SetRow($desc, 1)
        [void]$grid.Children.Add($desc)

        $middle = New-Object System.Windows.Controls.StackPanel
        if ($Tweak.ContainsKey('Warning') -and $Tweak.Warning) {
            [void]$middle.Children.Add((New-WarningBox -Text $Tweak.Warning))
        }
        [System.Windows.Controls.Grid]::SetRow($middle, 2)
        [void]$grid.Children.Add($middle)

        $foot = New-Object System.Windows.Controls.Grid
        $fc1 = New-Object System.Windows.Controls.ColumnDefinition
        $fc1.Width = [System.Windows.GridLength]::new(1, 'Star')
        $fc2 = New-Object System.Windows.Controls.ColumnDefinition
        $fc2.Width = [System.Windows.GridLength]::Auto
        [void]$foot.ColumnDefinitions.Add($fc1)
        [void]$foot.ColumnDefinitions.Add($fc2)

        $hintText = Get-RestartHint -Restart $Tweak.Restart
        $left = New-Object System.Windows.Controls.StackPanel
        $left.Orientation = 'Horizontal'
        $left.VerticalAlignment = 'Center'
        $hint = New-TextBlock -Text $hintText -Size 10.5 -ColorKey 'TextTertiary'
        $hint.VerticalAlignment = 'Center'
        $hint.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        if ($hintText) { [void]$left.Children.Add($hint) }
        [void]$left.Children.Add($reset)
        if ($Tweak.ContainsKey('Custom') -and $Tweak.Custom) {
            [void]$left.Children.Add((New-DeleteButton -Id $Tweak.Id))
        }
        [System.Windows.Controls.Grid]::SetColumn($left, 0)
        [void]$foot.Children.Add($left)
        [System.Windows.Controls.Grid]::SetColumn($toggle, 1)
        [void]$foot.Children.Add($toggle)

        $foot.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
        [System.Windows.Controls.Grid]::SetRow($foot, 3)
        [void]$grid.Children.Add($foot)

        $card.Child = $grid
    }

    Register-TweakCard -Id $Tweak.Id -Card $card -Toggle $toggle -Reset $reset -Pin $pin -Compact:$Compact
    return $card
}

function New-CommandCard {
    param($Command, [switch]$Compact)

    $card = New-Object System.Windows.Controls.Border
    $card.Style = Get-Resource 'CardCommand'
    $card.Margin = New-Object System.Windows.Thickness(6)
    $card.MinHeight = 132

    # The pinned strip shows a one-line version with the same Run action, so a pinned
    # command behaves exactly like the full card it came from.
    if ($Compact) {
        $card.Style = Get-Resource 'CardActive'
        $card.MinHeight = 52
        $card.Padding = New-Object System.Windows.Thickness(12, 8, 10, 8)

        $compactGrid = New-Object System.Windows.Controls.Grid
        $cc1 = New-Object System.Windows.Controls.ColumnDefinition
        $cc1.Width = [System.Windows.GridLength]::new(1, 'Star')
        $cc2 = New-Object System.Windows.Controls.ColumnDefinition
        $cc2.Width = [System.Windows.GridLength]::Auto
        [void]$compactGrid.ColumnDefinitions.Add($cc1)
        [void]$compactGrid.ColumnDefinitions.Add($cc2)

        $groupTitle = ''
        foreach ($group in $script:GroupDefs) { if ($group.Id -eq $Command.Group) { $groupTitle = $group.Title } }

        $compactStack = New-Object System.Windows.Controls.StackPanel
        $compactStack.VerticalAlignment = 'Center'
        $compactTitle = New-TextBlock -Text $Command.Title -Size 13 -Weight 'SemiBold'
        $compactTitle.TextTrimming = 'CharacterEllipsis'
        $compactTitle.ToolTip = $Command.Title
        $compactSub = New-TextBlock -Text $groupTitle -Size 10.5 -ColorKey 'TextTertiary'
        [void]$compactStack.Children.Add($compactTitle)
        [void]$compactStack.Children.Add($compactSub)
        [void]$compactGrid.Children.Add($compactStack)

        $compactRun = New-Object System.Windows.Controls.Button
        $compactRun.Style = Get-Resource 'BtnSecondary'
        $compactRun.Content = 'Run'
        $compactRun.Tag = $Command.Id
        $compactRun.MinWidth = 62
        $compactRun.Padding = New-Object System.Windows.Thickness(10, 2, 10, 2)
        $compactRun.VerticalAlignment = 'Center'
        $compactRun.ToolTip = 'Run this command now'
        $compactRun.Add_Click({
            param($sender, $eventArgs)
            Invoke-CommandFromUi -Id ([string]$sender.Tag)
        })
        [System.Windows.Controls.Grid]::SetColumn($compactRun, 1)
        [void]$compactGrid.Children.Add($compactRun)

        $card.Child = $compactGrid
        if (-not $script:CommandCards.ContainsKey($Command.Id)) { $script:CommandCards[$Command.Id] = @() }
        $script:CommandCards[$Command.Id] += , @{ Card = $card; Button = $compactRun; Pin = $null }
        return $card
    }

    $grid = New-Object System.Windows.Controls.Grid
    $r1 = New-Object System.Windows.Controls.RowDefinition
    $r1.Height = [System.Windows.GridLength]::Auto
    $r2 = New-Object System.Windows.Controls.RowDefinition
    $r2.Height = [System.Windows.GridLength]::Auto
    $r3 = New-Object System.Windows.Controls.RowDefinition
    $r3.Height = [System.Windows.GridLength]::new(1, 'Star')
    $r4 = New-Object System.Windows.Controls.RowDefinition
    $r4.Height = [System.Windows.GridLength]::Auto
    [void]$grid.RowDefinitions.Add($r1)
    [void]$grid.RowDefinitions.Add($r2)
    [void]$grid.RowDefinitions.Add($r3)
    [void]$grid.RowDefinitions.Add($r4)

    $head = New-Object System.Windows.Controls.Grid
    $hc1 = New-Object System.Windows.Controls.ColumnDefinition
    $hc1.Width = [System.Windows.GridLength]::new(1, 'Star')
    $hc2 = New-Object System.Windows.Controls.ColumnDefinition
    $hc2.Width = [System.Windows.GridLength]::Auto
    $hc3 = New-Object System.Windows.Controls.ColumnDefinition
    $hc3.Width = [System.Windows.GridLength]::Auto
    [void]$head.ColumnDefinitions.Add($hc1)
    [void]$head.ColumnDefinitions.Add($hc2)
    [void]$head.ColumnDefinitions.Add($hc3)

    $title = New-TextBlock -Text $Command.Title -Size 13.5 -Weight 'SemiBold'
    $title.TextTrimming = 'CharacterEllipsis'
    $title.ToolTip = $Command.Title
    [void]$head.Children.Add($title)

    $pin = New-PinButton -Id $Command.Id
    [System.Windows.Controls.Grid]::SetColumn($pin, 1)
    [void]$head.Children.Add($pin)

    $badges = New-Badges -Tweak $Command
    [System.Windows.Controls.Grid]::SetColumn($badges, 2)
    [void]$head.Children.Add($badges)
    [System.Windows.Controls.Grid]::SetRow($head, 0)
    [void]$grid.Children.Add($head)

    $desc = New-TextBlock -Text $Command.Desc -Size 12 -ColorKey 'TextSecondary' -Wrap 'Wrap'
    $desc.Margin = New-Object System.Windows.Thickness(0, 5, 0, 0)
    $desc.MaxHeight = 54
    $desc.TextTrimming = 'WordEllipsis'
    [System.Windows.Controls.Grid]::SetRow($desc, 1)
    [void]$grid.Children.Add($desc)

    $middle = New-Object System.Windows.Controls.StackPanel
    if ($Command.ContainsKey('Warning') -and $Command.Warning) {
        [void]$middle.Children.Add((New-WarningBox -Text $Command.Warning))
    }
    [System.Windows.Controls.Grid]::SetRow($middle, 2)
    [void]$grid.Children.Add($middle)

    $run = New-Object System.Windows.Controls.Button
    $run.Style = Get-Resource 'BtnSecondary'
    $run.Content = 'Run'
    $run.Tag = $Command.Id
    $run.HorizontalAlignment = 'Right'
    $run.MinWidth = 78
    $run.ToolTip = 'Run this command now'
    $run.Add_Click({
        param($sender, $eventArgs)
        Invoke-CommandFromUi -Id ([string]$sender.Tag)
    })
    $foot = New-Object System.Windows.Controls.StackPanel
    $foot.Orientation = 'Horizontal'
    $foot.HorizontalAlignment = 'Right'
    $foot.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
    if ($Command.ContainsKey('Custom') -and $Command.Custom) {
        $remove = New-DeleteButton -Id $Command.Id
        $remove.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        [void]$foot.Children.Add($remove)
    }
    $run.Margin = New-Object System.Windows.Thickness(0)
    [void]$foot.Children.Add($run)
    [System.Windows.Controls.Grid]::SetRow($foot, 3)
    [void]$grid.Children.Add($foot)

    $card.Child = $grid
    if (-not $script:CommandCards.ContainsKey($Command.Id)) { $script:CommandCards[$Command.Id] = @() }
    $script:CommandCards[$Command.Id] += , @{ Card = $card; Button = $run; Pin = $pin }
    return $card
}

function New-SectionBlock {
    param([string]$GroupId, [string]$Title, [string]$Subtitle, [string]$Letter, [double]$MinCardWidth = 300)

    $root = New-Object System.Windows.Controls.StackPanel
    $root.Margin = New-Object System.Windows.Thickness(0, 0, 0, 18)

    $head = New-Object System.Windows.Controls.Grid
    $head.Margin = New-Object System.Windows.Thickness(6, 4, 6, 6)
    $head.Tag = $GroupId
    $head.Cursor = [System.Windows.Input.Cursors]::Hand
    # A transparent brush makes the empty space in the row clickable as well.
    $head.Background = [System.Windows.Media.Brushes]::Transparent
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = [System.Windows.GridLength]::Auto
    $c2 = New-Object System.Windows.Controls.ColumnDefinition
    $c2.Width = [System.Windows.GridLength]::new(1, 'Star')
    $c3 = New-Object System.Windows.Controls.ColumnDefinition
    $c3.Width = [System.Windows.GridLength]::Auto
    $c4 = New-Object System.Windows.Controls.ColumnDefinition
    $c4.Width = [System.Windows.GridLength]::Auto
    [void]$head.ColumnDefinitions.Add($c1)
    [void]$head.ColumnDefinitions.Add($c2)
    [void]$head.ColumnDefinitions.Add($c3)
    [void]$head.ColumnDefinitions.Add($c4)

    $head.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        if (Test-ClickOnInteractive -Source $eventArgs.OriginalSource) { return }
        Toggle-SectionCollapsed -GroupId ([string]$sender.Tag)
    })

    $badge = New-Object System.Windows.Controls.Border
    $badge.Width = 34
    $badge.Height = 34
    $badge.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $badge.Background = Get-Resource 'AccentSoft'
    $badge.BorderBrush = Get-Resource 'AccentBorderSoft'
    $badge.BorderThickness = New-Object System.Windows.Thickness(1)
    $badge.Margin = New-Object System.Windows.Thickness(0, 0, 12, 0)
    $badge.VerticalAlignment = 'Center'
    $letterText = New-TextBlock -Text $Letter -Size 11 -Weight 'SemiBold' -ColorKey 'Accent'
    $letterText.HorizontalAlignment = 'Center'
    $letterText.VerticalAlignment = 'Center'
    $badge.Child = $letterText
    [System.Windows.Controls.Grid]::SetColumn($badge, 0)
    [void]$head.Children.Add($badge)

    $titles = New-Object System.Windows.Controls.StackPanel
    $titles.VerticalAlignment = 'Center'
    $titleText = New-TextBlock -Text $Title -Size 17 -Weight 'SemiBold' -Font $script:FontDisplay
    $subText = New-TextBlock -Text $Subtitle -Size 11.5 -ColorKey 'TextTertiary'
    $subText.Margin = New-Object System.Windows.Thickness(0, 1, 0, 0)
    [void]$titles.Children.Add($titleText)
    [void]$titles.Children.Add($subText)
    [System.Windows.Controls.Grid]::SetColumn($titles, 1)
    [void]$head.Children.Add($titles)

    $countText = New-TextBlock -Text '' -Size 11 -ColorKey 'TextTertiary'
    $countText.VerticalAlignment = 'Center'
    $countText.HorizontalAlignment = 'Right'
    $countText.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($countText, 2)
    [void]$head.Children.Add($countText)

    $chevronButton = New-Object System.Windows.Controls.Button
    $chevronButton.Style = Get-Resource 'BtnGhost'
    $chevronButton.Padding = New-Object System.Windows.Thickness(6, 2, 2, 2)
    $chevronButton.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)
    $chevronButton.VerticalAlignment = 'Center'
    $chevronButton.Tag = $GroupId
    $chevronButton.Add_Click({
        param($sender, $eventArgs)
        $eventArgs.Handled = $true
        Toggle-SectionCollapsed -GroupId ([string]$sender.Tag)
    })

    $chevronText = New-TextBlock -Text ([char]0xE70D) -Size 10 -Font $script:FontIcon -ColorKey 'TextTertiary'
    $chevronText.HorizontalAlignment = 'Center'
    $chevronButton.Content = $chevronText
    [System.Windows.Controls.Grid]::SetColumn($chevronButton, 3)
    [void]$head.Children.Add($chevronButton)

    [void]$root.Children.Add($head)

    $panel = New-Object System.Windows.Controls.Primitives.UniformGrid
    $panel.Margin = New-Object System.Windows.Thickness(0)
    $panel.Tag = $MinCardWidth
    [void]$root.Children.Add($panel)
    [void]$script:CardPanels.Add($panel)

    $section = @{
        Root      = $root
        Panel     = $panel
        Head      = $head
        Chevron   = $chevronText
        CountText = $countText
        Group     = $GroupId
        Title     = $Title
        Entries   = (New-Object System.Collections.ArrayList)
    }
    $script:SectionMap[$GroupId] = $section
    return $section
}

# Folded categories are remembered in settings.json as a comma separated id list.
function Get-CollapsedGroups {
    if ($null -ne $script:CollapsedGroups) { return $script:CollapsedGroups }

    $script:CollapsedGroups = @{}
    $raw = ''
    if ($null -ne $script:Settings -and $script:Settings.ContainsKey('collapsed')) { $raw = [string]$script:Settings['collapsed'] }
    foreach ($id in ($raw -split ',')) {
        $id = $id.Trim()
        if ($id) { $script:CollapsedGroups[$id] = $true }
    }
    return $script:CollapsedGroups
}

# A search opens every category that has a hit, so a folded one never hides a match.
function Set-SectionOpen {
    param($Section, [bool]$ForceOpen)

    if ($null -eq $Section) { return }
    $open = $ForceOpen -or (-not (Get-CollapsedGroups).ContainsKey([string]$Section.Group))

    $Section.Panel.Visibility = if ($open) { 'Visible' } else { 'Collapsed' }
    $Section.Chevron.Text = if ($open) { [string][char]0xE70D } else { [string][char]0xE76C }
    $Section.Head.ToolTip = if ($open) { "Collapse $($Section.Title)" } else { "Expand $($Section.Title)" }
}

function Save-CollapsedGroups {
    $script:Settings['collapsed'] = ((@((Get-CollapsedGroups).Keys) | Sort-Object) -join ',')
    Save-AppSettings
}

function Set-SectionCollapsed {
    param([string]$GroupId, [bool]$Collapsed, [switch]$Persist)

    $section = $script:SectionMap[[string]$GroupId]
    if ($null -eq $section) { return }

    $groups = Get-CollapsedGroups
    if ($Collapsed) { $groups[[string]$GroupId] = $true } else { [void]$groups.Remove([string]$GroupId) }
    Set-SectionOpen -Section $section -ForceOpen $false

    if ($Persist) { Save-CollapsedGroups }
    if ($null -ne $script:Window) {
        # Re-run the responsive grid once the newly opened panel has been measured.
        $script:Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
            Update-GridColumns
        }) | Out-Null
    }
}

function Toggle-SectionCollapsed {
    param([string]$GroupId)
    if (-not $GroupId) { return }
    Set-SectionCollapsed -GroupId $GroupId -Collapsed (-not (Get-CollapsedGroups).ContainsKey([string]$GroupId)) -Persist
}

# Picking a category in the navigation pane un-folds it, otherwise the click looks inert.
function Expand-SectionForNav {
    param([string]$GroupId)
    if (-not $GroupId -or $GroupId -eq 'all' -or $GroupId -eq 'active') { return }
    if ((Get-CollapsedGroups).ContainsKey([string]$GroupId)) {
        Set-SectionCollapsed -GroupId $GroupId -Collapsed $false -Persist
    }
}

function Get-PinnedCards {
    if ($null -ne $script:PinnedCards) { return $script:PinnedCards }

    # An ordered map keeps the pin order, so the list does not reshuffle on every start.
    $map = [ordered]@{}
    $raw = ''
    if ($null -ne $script:Settings -and $script:Settings.ContainsKey('pinned')) { $raw = [string]$script:Settings['pinned'] }
    foreach ($id in ($raw -split ',')) {
        $id = $id.Trim()
        if ($id -and -not $map.Contains($id)) { $map[$id] = $true }
    }
    $script:PinnedCards = $map
    return $map
}

function Save-PinnedCards {
    $script:Settings['pinned'] = (@((Get-PinnedCards).Keys) -join ',')
    Save-AppSettings
    # The desktop right-click menu is a mirror of this list, so it is rebuilt here
    # instead of at every call site that can change a pin.
    Sync-DesktopMenu
}

# Colour and tooltip follow the pin state; the glyph stays the same pin either way.
# Tweaks and commands share one pinned list, so both card sets are refreshed here.
function Update-PinButtons {
    param([string]$Id = '')

    $pinned = Get-PinnedCards
    foreach ($key in @($script:TweakCards.Keys)) {
        if ($Id -and $key -ne $Id) { continue }
        foreach ($instance in $script:TweakCards[$key]) {
            if (-not $instance.ContainsKey('Pin') -or $null -eq $instance.Pin) { continue }
            Set-PinButtonState -Button $instance.Pin -Pinned $pinned.Contains([string]$key)
        }
    }
    foreach ($key in @($script:CommandCards.Keys)) {
        if ($Id -and $key -ne $Id) { continue }
        foreach ($instance in $script:CommandCards[$key]) {
            if (-not $instance.ContainsKey('Pin') -or $null -eq $instance.Pin) { continue }
            Set-PinButtonState -Button $instance.Pin -Pinned $pinned.Contains([string]$key)
        }
    }
}

function Build-ActiveSection {
    $root = New-Object System.Windows.Controls.StackPanel
    $root.Margin = New-Object System.Windows.Thickness(0, 0, 0, 20)

    $head = New-Object System.Windows.Controls.Grid
    $head.Margin = New-Object System.Windows.Thickness(6, 2, 6, 6)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = [System.Windows.GridLength]::new(1, 'Star')
    $c2 = New-Object System.Windows.Controls.ColumnDefinition
    $c2.Width = [System.Windows.GridLength]::Auto
    [void]$head.ColumnDefinitions.Add($c1)
    [void]$head.ColumnDefinitions.Add($c2)

    $left = New-Object System.Windows.Controls.StackPanel
    $left.Orientation = 'Horizontal'
    $bar = New-Object System.Windows.Controls.Border
    $bar.Width = 3
    $bar.Height = 18
    $bar.CornerRadius = New-Object System.Windows.CornerRadius(2)
    $bar.Background = Get-Resource 'Accent'
    $bar.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $bar.VerticalAlignment = 'Center'
    [void]$left.Children.Add($bar)

    $title = New-TextBlock -Text 'Active tweaks' -Size 15 -Weight 'SemiBold' -Font $script:FontDisplay
    $title.VerticalAlignment = 'Center'
    [void]$left.Children.Add($title)

    $script:ActiveCountText = New-Pill -Text '0' -ColorKey 'Accent' -BgKey 'AccentSoft'
    [void]$left.Children.Add($script:ActiveCountText)

    [System.Windows.Controls.Grid]::SetColumn($left, 0)
    [void]$head.Children.Add($left)

    $resetAll = New-Object System.Windows.Controls.Button
    $resetAll.Style = Get-Resource 'BtnGhost'
    $resetAll.Content = 'Reset all tweaks'
    $resetAll.VerticalAlignment = 'Center'
    $resetAll.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
    $resetAll.Add_Click({ Reset-AllFromUi })
    [System.Windows.Controls.Grid]::SetColumn($resetAll, 1)
    [void]$head.Children.Add($resetAll)

    [void]$root.Children.Add($head)

    $hint = New-TextBlock -Text 'Everything currently switched on, pinned here so the changes you made stay visible.' -Size 11.5 -ColorKey 'TextTertiary' -Wrap 'Wrap'
    $hint.Margin = New-Object System.Windows.Thickness(12, 0, 6, 8)
    [void]$root.Children.Add($hint)

    $panel = New-Object System.Windows.Controls.Primitives.UniformGrid
    $panel.Tag = 300
    [void]$root.Children.Add($panel)
    [void]$script:CardPanels.Add($panel)

    $script:ActivePanel = $panel
    $script:ActiveSection = $root
    $root.Visibility = 'Collapsed'
    return $root
}

function Build-PinnedSection {
    $root = New-Object System.Windows.Controls.StackPanel
    $root.Margin = New-Object System.Windows.Thickness(0, 0, 0, 20)

    $head = New-Object System.Windows.Controls.Grid
    $head.Margin = New-Object System.Windows.Thickness(6, 2, 6, 6)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = [System.Windows.GridLength]::new(1, 'Star')
    [void]$head.ColumnDefinitions.Add($c1)

    $left = New-Object System.Windows.Controls.StackPanel
    $left.Orientation = 'Horizontal'
    $icon = New-TextBlock -Text ([char]0xE718) -Size 13 -Font $script:FontIcon -ColorKey 'Accent'
    $icon.VerticalAlignment = 'Center'
    $icon.Margin = New-Object System.Windows.Thickness(0, 0, 7, 0)
    [void]$left.Children.Add($icon)

    $title = New-TextBlock -Text 'Pinned' -Size 15 -Weight 'SemiBold' -Font $script:FontDisplay
    $title.VerticalAlignment = 'Center'
    [void]$left.Children.Add($title)

    $script:PinnedCountText = New-Pill -Text '0' -ColorKey 'Accent' -BgKey 'AccentSoft'
    [void]$left.Children.Add($script:PinnedCountText)

    [System.Windows.Controls.Grid]::SetColumn($left, 0)
    [void]$head.Children.Add($left)
    [void]$root.Children.Add($head)

    $hint = New-TextBlock -Text 'Cards you pinned with the pin button, kept at the top. The same list drives the PowerKit desktop right-click menu.' -Size 11.5 -ColorKey 'TextTertiary' -Wrap 'Wrap'
    $hint.Margin = New-Object System.Windows.Thickness(12, 0, 6, 8)
    [void]$root.Children.Add($hint)

    $panel = New-Object System.Windows.Controls.Primitives.UniformGrid
    $panel.Tag = 300
    [void]$root.Children.Add($panel)
    [void]$script:CardPanels.Add($panel)

    $script:PinnedPanel = $panel
    $script:PinnedSection = $root
    $root.Visibility = 'Collapsed'
    return $root
}

function Build-PendingBanner {
    $border = New-Object System.Windows.Controls.Border
    $border.Background = Get-Resource 'AccentSoft'
    $border.BorderBrush = Get-Resource 'AccentBorderSoft'
    $border.BorderThickness = New-Object System.Windows.Thickness(1)
    $border.CornerRadius = New-Object System.Windows.CornerRadius(6)
    $border.Padding = New-Object System.Windows.Thickness(12, 8, 10, 8)
    $border.Margin = New-Object System.Windows.Thickness(6, 0, 6, 14)
    $border.Visibility = 'Collapsed'

    $grid = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = [System.Windows.GridLength]::new(1, 'Star')
    $c2 = New-Object System.Windows.Controls.ColumnDefinition
    $c2.Width = [System.Windows.GridLength]::Auto
    $c3 = New-Object System.Windows.Controls.ColumnDefinition
    $c3.Width = [System.Windows.GridLength]::Auto
    [void]$grid.ColumnDefinitions.Add($c1)
    [void]$grid.ColumnDefinitions.Add($c2)
    [void]$grid.ColumnDefinitions.Add($c3)

    $script:PendingText = New-TextBlock -Text '' -Size 12 -ColorKey 'TextPrimary' -Wrap 'Wrap'
    $script:PendingText.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($script:PendingText, 0)
    [void]$grid.Children.Add($script:PendingText)

    $apply = New-Object System.Windows.Controls.Button
    $apply.Style = Get-Resource 'BtnSecondary'
    $apply.Content = 'Restart Explorer'
    $apply.Margin = New-Object System.Windows.Thickness(8, 0, 4, 0)
    $apply.Add_Click({
        try {
            $message = Get-HandlerAction -Handler 'RestartExplorer'
            $script:PendingRestarts = @{}
            Update-PendingBanner
            Show-Toast -Message $message -Kind 'success'
        } catch {
            Show-Toast -Message $_.Exception.Message -Kind 'error'
        }
    })
    [System.Windows.Controls.Grid]::SetColumn($apply, 1)
    [void]$grid.Children.Add($apply)

    $dismiss = New-Object System.Windows.Controls.Button
    $dismiss.Style = Get-Resource 'BtnGhost'
    $dismiss.Content = 'Dismiss'
    $dismiss.VerticalAlignment = 'Center'
    $dismiss.Add_Click({
        $script:PendingRestarts = @{}
        Update-PendingBanner
    })
    [System.Windows.Controls.Grid]::SetColumn($dismiss, 2)
    [void]$grid.Children.Add($dismiss)

    $border.Child = $grid
    $script:PendingBanner = $border
    return $border
}

function Update-PendingBanner {
    if ($null -eq $script:PendingBanner) { return }
    if ($script:PendingRestarts.Count -eq 0) {
        $script:PendingBanner.Visibility = 'Collapsed'
        return
    }
    $parts = @()
    if ($script:PendingRestarts.ContainsKey('explorer')) { $parts += 'Explorer needs restarting' }
    if ($script:PendingRestarts.ContainsKey('signout')) { $parts += 'sign out to apply some changes' }
    if ($script:PendingRestarts.ContainsKey('reboot')) { $parts += 'restart the PC to apply some changes' }
    $script:PendingText.Text = ($parts -join ', ') + '.'
    $script:PendingBanner.Visibility = 'Visible'
}

function Add-PendingRestart {
    param([string]$Kind)
    if (-not $Kind) { return }
    if (-not $script:PendingRestarts.ContainsKey($Kind)) { $script:PendingRestarts[$Kind] = 0 }
    $script:PendingRestarts[$Kind] = $script:PendingRestarts[$Kind] + 1
    Update-PendingBanner
}

function Update-GridColumns {
    foreach ($panel in $script:CardPanels) {
        $width = $panel.ActualWidth
        if ($width -le 0 -and $null -ne $script:ContentStack) {
            # A panel that has never been shown still needs its column count, or the
            # first measure after it appears puts every card in one row.
            $width = $script:ContentStack.ActualWidth
        }
        if ($width -le 0) { continue }
        $min = [double]$panel.Tag
        if ($min -le 0) { $min = 320 }
        $cols = [int][Math]::Floor($width / $min)
        if ($cols -lt 1) { $cols = 1 }
        if ($cols -gt 6) { $cols = 6 }
        if ($panel.Columns -ne $cols) { $panel.Columns = $cols }
    }
}

function Build-NavItem {
    param([string]$Id, [string]$Title, [bool]$AccentCount = $false)

    $grid = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = [System.Windows.GridLength]::new(1, 'Star')
    $c2 = New-Object System.Windows.Controls.ColumnDefinition
    $c2.Width = [System.Windows.GridLength]::Auto
    [void]$grid.ColumnDefinitions.Add($c1)
    [void]$grid.ColumnDefinitions.Add($c2)

    $titleText = New-TextBlock -Text $Title -Size 13
    $titleText.VerticalAlignment = 'Center'
    [void]$grid.Children.Add($titleText)

    $countText = New-TextBlock -Text '' -Size 11 -ColorKey $(if ($AccentCount) { 'Accent' } else { 'TextTertiary' })
    $countText.VerticalAlignment = 'Center'
    $countText.HorizontalAlignment = 'Right'
    $countText.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($countText, 1)
    [void]$grid.Children.Add($countText)

    $item = New-Object System.Windows.Controls.ListBoxItem
    $item.Style = Get-Resource 'NavItem'
    $item.Content = $grid
    $item.Tag = $Id
    return @{ Item = $item; Count = $countText }
}

function Update-ThemeButton {
    # A sun for a light app and a moon for a dark one, so the header says it without words.
    if ($null -eq $script:ThemeButton) { return }

    $choice = if ($script:ThemeOverridden) { $script:ThemeMode } else { 'system' }
    $glyph = if ($script:ThemeMode -eq 'dark') { 0xE708 } else { 0xE706 }
    switch ($choice) {
        'light' { $label = 'Light theme - click for dark' }
        'dark'  { $label = 'Dark theme - click to follow Windows' }
        default { $label = 'Following the Windows theme - click for light' }
    }

    $script:ThemeButton.Content = New-TextBlock -Text ([char]$glyph) -Size 14 -Font $script:FontIcon -ColorKey 'TextPrimary'
    $script:ThemeButton.ToolTip = ($label + '. Your choice is remembered next time PowerKit starts.')
}

function Build-MainWindow {
    $window = New-Object System.Windows.Window
    $window.Title = 'PowerKit - Windows 11 power tools'
    $window.Width = 1220
    $window.Height = 840
    $window.MinWidth = 700
    $window.MinHeight = 540
    $window.WindowStartupLocation = 'CenterScreen'
    $window.FontFamily = $script:FontText
    $window.UseLayoutRounding = $true
    $window.SnapsToDevicePixels = $true
    [System.Windows.Media.TextOptions]::SetTextFormattingMode($window, 'Display')

    # The window has no title bar, so this icon is what the taskbar and Alt-Tab show.
    $iconPath = Join-Path $script:AppRoot 'src\powerkit.ico'
    if (Test-Path -LiteralPath $iconPath) {
        try {
            $decoder = New-Object System.Windows.Media.Imaging.IconBitmapDecoder(
                (New-Object System.Uri($iconPath)),
                [System.Windows.Media.Imaging.BitmapCreateOptions]::None,
                [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
            $frame = $decoder.Frames | Where-Object { $_.PixelWidth -ge 48 } | Sort-Object -Property PixelWidth | Select-Object -First 1
            if ($null -eq $frame) { $frame = $decoder.Frames | Sort-Object -Property PixelWidth | Select-Object -Last 1 }
            $window.Icon = $frame
        } catch { }
    }

    # No system title bar: the header row is the caption, with PowerKit's own buttons.
    $window.WindowStyle = 'None'
    $window.ResizeMode = 'CanResize'
    $chrome = New-Object System.Windows.Shell.WindowChrome
    $chrome.CaptionHeight = 0
    $chrome.ResizeBorderThickness = New-Object System.Windows.Thickness(6)
    $chrome.GlassFrameThickness = New-Object System.Windows.Thickness(0)
    $chrome.UseAeroCaptionButtons = $false
    [System.Windows.Shell.WindowChrome]::SetWindowChrome($window, $chrome)

    $script:Window = $window

    Add-AppResources -Resources $window.Resources -Mode $script:ThemeMode
    Register-ThemeWindow -Window $window
    $window.Background = Get-Resource 'WindowBg'

    $root = New-Object System.Windows.Controls.Grid
    $r0 = New-Object System.Windows.Controls.RowDefinition
    $r0.Height = [System.Windows.GridLength]::Auto
    $r1 = New-Object System.Windows.Controls.RowDefinition
    $r1.Height = [System.Windows.GridLength]::new(1, 'Star')
    [void]$root.RowDefinitions.Add($r0)
    [void]$root.RowDefinitions.Add($r1)

    # ---------- header ----------
    $header = New-Object System.Windows.Controls.Border
    $header.Background = Get-Resource 'HeaderBg'
    $header.BorderBrush = Get-Resource 'Divider'
    $header.BorderThickness = New-Object System.Windows.Thickness(0, 0, 0, 1)
    $header.Padding = New-Object System.Windows.Thickness(18, 10, 18, 10)
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

    # The app draws its own title bar, so dragging the header moves the window.
    $header.Add_MouseLeftButtonDown({
        param($sender, $eventArgs)
        if (Test-ClickOnInteractive -Source $eventArgs.OriginalSource) { return }
        if ($eventArgs.ClickCount -eq 2) {
            Invoke-ChromeAction -Action 'max'
            return
        }
        try { $script:Window.DragMove() } catch { }
    })

    $titleStack = New-Object System.Windows.Controls.StackPanel
    $titleStack.VerticalAlignment = 'Center'
    $appTitle = New-TextBlock -Text 'PowerKit' -Size 19 -Weight 'SemiBold' -Font $script:FontDisplay
    $script:HeaderSubtitle = New-TextBlock -Text '' -Size 11.5 -ColorKey 'TextTertiary' -Wrap 'NoWrap'
    $script:HeaderSubtitle.Margin = New-Object System.Windows.Thickness(0, 1, 0, 0)
    $script:HeaderSubtitle.TextTrimming = 'CharacterEllipsis'
    [void]$titleStack.Children.Add($appTitle)
    [void]$titleStack.Children.Add($script:HeaderSubtitle)
    [void]$headerGrid.Children.Add($titleStack)

    $tools = New-Object System.Windows.Controls.StackPanel
    $tools.Orientation = 'Horizontal'
    $tools.VerticalAlignment = 'Center'
    $tools.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($tools, 1)
    [void]$headerGrid.Children.Add($tools)

    # search
    $searchBorder = New-Object System.Windows.Controls.Border
    $searchBorder.Width = 268
    $searchBorder.Height = 34
    $searchBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
    $searchBorder.Background = Get-Resource 'InputBg'
    $searchBorder.BorderBrush = Get-Resource 'BorderSubtle'
    $searchBorder.BorderThickness = New-Object System.Windows.Thickness(1)
    $searchBorder.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
    $searchBorder.VerticalAlignment = 'Center'

    $searchGrid = New-Object System.Windows.Controls.Grid
    $sc1 = New-Object System.Windows.Controls.ColumnDefinition
    $sc1.Width = [System.Windows.GridLength]::Auto
    $sc2 = New-Object System.Windows.Controls.ColumnDefinition
    $sc2.Width = [System.Windows.GridLength]::new(1, 'Star')
    [void]$searchGrid.ColumnDefinitions.Add($sc1)
    [void]$searchGrid.ColumnDefinitions.Add($sc2)

    $searchIcon = New-TextBlock -Text ([char]0xE721) -Size 12 -ColorKey 'TextTertiary' -Font $script:FontIcon
    $searchIcon.Margin = New-Object System.Windows.Thickness(10, 0, 8, 0)
    $searchIcon.VerticalAlignment = 'Center'
    [void]$searchGrid.Children.Add($searchIcon)

    $searchBox = New-Object System.Windows.Controls.TextBox
    $searchBox.Style = Get-Resource 'SearchTextBox'
    $searchBox.VerticalAlignment = 'Center'
    $searchBox.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
    $searchBox.Add_TextChanged({
        param($sender, $eventArgs)
        Update-Filter
    })
    $script:SearchBox = $searchBox
    [System.Windows.Controls.Grid]::SetColumn($searchBox, 1)
    [void]$searchGrid.Children.Add($searchBox)

    $placeholder = New-TextBlock -Text 'Search tweaks and commands' -Size 12.5 -ColorKey 'TextTertiary'
    $placeholder.VerticalAlignment = 'Center'
    $placeholder.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
    $placeholder.IsHitTestVisible = $false
    $script:SearchPlaceholder = $placeholder
    [System.Windows.Controls.Grid]::SetColumn($placeholder, 1)
    [void]$searchGrid.Children.Add($placeholder)

    $searchBorder.Child = $searchGrid
    $script:HeaderSearch = $searchBorder
    [void]$tools.Children.Add($searchBorder)

    $themeButton = New-Object System.Windows.Controls.Button
    $themeButton.Style = Get-Resource 'BtnIcon'
    $themeButton.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
    $themeButton.VerticalAlignment = 'Center'
    $themeButton.Add_Click({ Toggle-Theme })
    $script:ThemeButton = $themeButton
    Update-ThemeButton
    [void]$tools.Children.Add($themeButton)

    $refreshButton = New-Object System.Windows.Controls.Button
    $refreshButton.Style = Get-Resource 'BtnIcon'
    $refreshButton.Content = New-TextBlock -Text ([char]0xE72C) -Size 13 -Font $script:FontIcon -ColorKey 'TextPrimary'
    $refreshButton.VerticalAlignment = 'Center'
    $refreshButton.ToolTip = 'Re-read every setting from the registry (F5)'
    $refreshButton.Add_Click({ Refresh-AllVisuals -Notify 'Settings reloaded from the registry' })
    [void]$tools.Children.Add($refreshButton)

    $newAction = New-Object System.Windows.Controls.Button
    $newAction.Style = Get-Resource 'BtnSecondary'
    $newAction.Content = '+ New'
    $newAction.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
    $newAction.Padding = New-Object System.Windows.Thickness(12, 5, 12, 5)
    $newAction.VerticalAlignment = 'Center'
    $newAction.ToolTip = 'Describe an action and let the AI builder turn it into a card'
    $newAction.Add_Click({
        try { Show-NewActionDialog } catch { Show-Toast -Message $_.Exception.Message -Kind 'error' }
    })
    $script:NewActionButton = $newAction
    [void]$tools.Children.Add($newAction)

    $runButton = New-Object System.Windows.Controls.Button
    $runButton.Style = Get-Resource 'BtnIcon'
    $runButton.Content = New-TextBlock -Text ([char]0xE768) -Size 12 -Font $script:FontIcon -ColorKey 'TextPrimary'
    $runButton.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
    $runButton.VerticalAlignment = 'Center'
    $runButton.ToolTip = 'Run box - open a program, file, folder or web address'
    $runButton.Add_Click({
        try { Show-RunBox } catch { Show-Toast -Message $_.Exception.Message -Kind 'error' }
    })
    [void]$tools.Children.Add($runButton)

    $settingsButton = New-Object System.Windows.Controls.Button
    $settingsButton.Style = Get-Resource 'BtnIcon'
    $settingsButton.Content = New-TextBlock -Text ([char]0xE713) -Size 12 -Font $script:FontIcon -ColorKey 'TextPrimary'
    $settingsButton.VerticalAlignment = 'Center'
    $settingsButton.ToolTip = 'Settings - API key, endpoint and model for the AI builder'
    $settingsButton.Add_Click({
        try { Show-SettingsDialog } catch { Show-Toast -Message $_.Exception.Message -Kind 'error' }
    })
    [void]$tools.Children.Add($settingsButton)

    # hamburger for narrow windows
    $navButton = New-Object System.Windows.Controls.Button
    $navButton.Style = Get-Resource 'BtnIcon'
    $navButton.Content = New-TextBlock -Text ([char]0xE700) -Size 13 -Font $script:FontIcon -ColorKey 'TextPrimary'
    $navButton.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)
    $navButton.VerticalAlignment = 'Center'
    $navButton.ToolTip = 'Show or hide the navigation pane'
    $navButton.Add_Click({ Toggle-NavPane })
    [void]$tools.Children.Add($navButton)

    $chromeDivider = New-Object System.Windows.Controls.Border
    $chromeDivider.Width = 1
    $chromeDivider.Height = 20
    $chromeDivider.Background = Get-Resource 'Divider'
    $chromeDivider.Margin = New-Object System.Windows.Thickness(8, 0, 6, 0)
    $chromeDivider.VerticalAlignment = 'Center'
    [void]$tools.Children.Add($chromeDivider)

    [void]$tools.Children.Add((New-ChromeButton -Glyph 0xE921 -Tip 'Minimise' -Action 'min'))
    $script:MaxButton = New-ChromeButton -Glyph 0xE922 -Tip 'Maximise' -Action 'max'
    [void]$tools.Children.Add($script:MaxButton)
    [void]$tools.Children.Add((New-ChromeButton -Glyph 0xE8BB -Tip 'Close' -Action 'close'))

    # ---------- body ----------
    $body = New-Object System.Windows.Controls.Grid
    [System.Windows.Controls.Grid]::SetRow($body, 1)
    [void]$root.Children.Add($body)

    $navColumn = New-Object System.Windows.Controls.ColumnDefinition
    $navColumn.Width = New-Object System.Windows.GridLength(232)
    $contentColumn = New-Object System.Windows.Controls.ColumnDefinition
    $contentColumn.Width = [System.Windows.GridLength]::new(1, 'Star')
    [void]$body.ColumnDefinitions.Add($navColumn)
    [void]$body.ColumnDefinitions.Add($contentColumn)
    $script:NavColumn = $navColumn

    $nav = New-Object System.Windows.Controls.Border
    $nav.Background = Get-Resource 'NavBg'
    $nav.BorderBrush = Get-Resource 'Divider'
    $nav.BorderThickness = New-Object System.Windows.Thickness(0, 0, 1, 0)
    [System.Windows.Controls.Grid]::SetColumn($nav, 0)
    [void]$body.Children.Add($nav)

    $navGrid = New-Object System.Windows.Controls.Grid
    $nr1 = New-Object System.Windows.Controls.RowDefinition
    $nr1.Height = [System.Windows.GridLength]::new(1, 'Star')
    $nr2 = New-Object System.Windows.Controls.RowDefinition
    $nr2.Height = [System.Windows.GridLength]::Auto
    [void]$navGrid.RowDefinitions.Add($nr1)
    [void]$navGrid.RowDefinitions.Add($nr2)
    $nav.Child = $navGrid

    $navList = New-Object System.Windows.Controls.ListBox
    $navList.Style = Get-Resource 'NavList'
    $navList.Margin = New-Object System.Windows.Thickness(0, 8, 0, 8)
    $navList.Add_SelectionChanged({
        param($sender, $eventArgs)
        Update-NavSelection
    })
    $script:NavList = $navList

    # nav entries: All / Active / groups
    $all = Build-NavItem -Id 'all' -Title 'All tweaks'
    $activeNav = Build-NavItem -Id 'active' -Title 'Active tweaks' -AccentCount $true
    [void]$navList.Items.Add($all.Item)
    [void]$navList.Items.Add($activeNav.Item)
    $script:NavCounts = @{}
    $script:NavCounts['all'] = $all.Count
    $script:NavCounts['active'] = $activeNav.Count

    foreach ($group in $script:GroupDefs) {
        $navItem = Build-NavItem -Id $group.Id -Title $group.Title
        [void]$navList.Items.Add($navItem.Item)
        $script:NavCounts[$group.Id] = $navItem.Count
    }
    [System.Windows.Controls.Grid]::SetRow($navList, 0)
    [void]$navGrid.Children.Add($navList)

    $navFooter = New-Object System.Windows.Controls.StackPanel
    $navFooter.Margin = New-Object System.Windows.Thickness(16, 8, 16, 14)
    $adminText = if ($script:IsAdmin) { 'Running as administrator' } else { 'Standard user - admin tweaks ask for approval' }
    $adminBlock = New-TextBlock -Text $adminText -Size 10.5 -ColorKey $(if ($script:IsAdmin) { 'SuccessText' } else { 'TextTertiary' }) -Wrap 'Wrap'
    $script:AdminStatusText = $adminBlock
    [void]$navFooter.Children.Add($adminBlock)

    $captured = if ($script:DefaultsCapturedAt) { ([datetime]$script:DefaultsCapturedAt).ToString('d MMM yyyy HH:mm') } else { 'not captured yet' }
    $defaultsBlock = New-TextBlock -Text ("Defaults captured: $captured") -Size 10.5 -ColorKey 'TextTertiary' -Wrap 'Wrap'
    $defaultsBlock.Margin = New-Object System.Windows.Thickness(0, 4, 0, 2)
    $script:DefaultsInfoText = $defaultsBlock
    [void]$navFooter.Children.Add($defaultsBlock)

    $activityLog = New-Object System.Windows.Controls.Button
    $activityLog.Style = Get-Resource 'BtnGhost'
    $activityLog.Content = 'Activity log'
    $activityLog.HorizontalAlignment = 'Left'
    $activityLog.Padding = New-Object System.Windows.Thickness(0, 2, 0, 2)
    $activityLog.ToolTip = 'See every registry write and command PowerKit recorded'
    $activityLog.Add_Click({ Show-ActivityLog })
    [void]$navFooter.Children.Add($activityLog)

    $recapture = New-Object System.Windows.Controls.Button
    $recapture.Style = Get-Resource 'BtnGhost'
    $recapture.Content = 'Re-capture defaults'
    $recapture.HorizontalAlignment = 'Left'
    $recapture.Padding = New-Object System.Windows.Thickness(0, 2, 0, 2)
    $recapture.ToolTip = 'Store the current registry state as the value Reset will restore. Use this after setting Windows up the way you like it.'
    $recapture.Add_Click({ Recapture-Defaults })
    [void]$navFooter.Children.Add($recapture)

    $exportSetup = New-Object System.Windows.Controls.Button
    $exportSetup.Style = Get-Resource 'BtnGhost'
    $exportSetup.Content = 'Export setup'
    $exportSetup.HorizontalAlignment = 'Left'
    $exportSetup.Padding = New-Object System.Windows.Thickness(0, 2, 0, 2)
    $exportSetup.ToolTip = 'Save your settings, Reset baseline, pinned cards and AI-drafted cards to one file. The API key is never exported.'
    $exportSetup.Add_Click({ Export-PowerKitSetup })
    [void]$navFooter.Children.Add($exportSetup)

    $importSetup = New-Object System.Windows.Controls.Button
    $importSetup.Style = Get-Resource 'BtnGhost'
    $importSetup.Content = 'Import setup'
    $importSetup.HorizontalAlignment = 'Left'
    $importSetup.Padding = New-Object System.Windows.Thickness(0, 2, 0, 2)
    $importSetup.ToolTip = 'Replace this PC''s settings, Reset baseline and AI-drafted cards with those in an exported file.'
    $importSetup.Add_Click({ Import-PowerKitSetup })
    [void]$navFooter.Children.Add($importSetup)

    [System.Windows.Controls.Grid]::SetRow($navFooter, 1)
    [void]$navGrid.Children.Add($navFooter)

    # content
    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $scroll.HorizontalScrollBarVisibility = 'Disabled'
    $scroll.Padding = New-Object System.Windows.Thickness(16, 16, 10, 16)
    [System.Windows.Controls.Grid]::SetColumn($scroll, 1)
    [void]$body.Children.Add($scroll)

    $contentStack = New-Object System.Windows.Controls.StackPanel
    $scroll.Content = $contentStack
    $script:ContentStack = $contentStack

    [void]$contentStack.Children.Add((Build-PendingBanner))
    [void]$contentStack.Children.Add((Build-PinnedSection))
    [void]$contentStack.Children.Add((Build-ActiveSection))

    foreach ($group in $script:GroupDefs) {
        $isCommandGroup = ($group.Id -eq 'power' -or $group.Id -eq 'tools')
        $section = New-SectionBlock -GroupId $group.Id -Title $group.Title -Subtitle $group.Subtitle -Letter $group.Letter
        [void]$contentStack.Children.Add($section.Root)

        if ($isCommandGroup) {
            foreach ($command in $script:CommandDefs) {
                if ($command.Group -ne $group.Id) { continue }
                $card = New-CommandCard -Command $command
                [void]$section.Panel.Children.Add($card)
                [void]$section.Entries.Add(@{
                    Card      = $card
                    SearchText = ($command.Title + ' ' + $command.Desc + ' ' + $group.Title).ToLowerInvariant()
                })
                if ($command.ContainsKey('Custom') -and $command.Custom) { $script:CustomCards[$command.Id] = @{ Card = $card; Section = $section } }
            }
        } else {
            foreach ($tweak in $script:TweakDefs) {
                if ($tweak.Group -ne $group.Id) { continue }
                $card = New-TweakCard -Tweak $tweak
                [void]$section.Panel.Children.Add($card)
                [void]$section.Entries.Add(@{
                    Card      = $card
                    SearchText = ($tweak.Title + ' ' + $tweak.Desc + ' ' + $group.Title + ' ' + $tweak.Warning).ToLowerInvariant()
                })
                if ($tweak.ContainsKey('Custom') -and $tweak.Custom) { $script:CustomCards[$tweak.Id] = @{ Card = $card; Section = $section } }
            }
        }
        [void]$script:Sections.Add($section)
        Set-SectionOpen -Section $section -ForceOpen $false
    }

    $noResults = New-TextBlock -Text 'Nothing matches that search.' -Size 13 -ColorKey 'TextTertiary'
    $noResults.Margin = New-Object System.Windows.Thickness(8, 20, 8, 0)
    $noResults.Visibility = 'Collapsed'
    [void]$contentStack.Children.Add($noResults)
    $script:NoResults = $noResults

    # ---------- toast ----------
    $toast = New-Object System.Windows.Controls.Border
    $toast.Background = Get-Resource 'CardBg'
    $toast.BorderBrush = Get-Resource 'BorderStrong'
    $toast.BorderThickness = New-Object System.Windows.Thickness(1)
    $toast.CornerRadius = New-Object System.Windows.CornerRadius(6)
    $toast.Padding = New-Object System.Windows.Thickness(14, 9, 14, 9)
    $toast.HorizontalAlignment = 'Center'
    $toast.VerticalAlignment = 'Bottom'
    $toast.Margin = New-Object System.Windows.Thickness(0, 0, 0, 22)
    $toast.MaxWidth = 640
    $toast.Visibility = 'Collapsed'
    $toast.IsHitTestVisible = $false
    $script:ToastBorder = $toast

    $toastText = New-TextBlock -Text '' -Size 12.5 -ColorKey 'TextPrimary' -Wrap 'Wrap'
    $toastText.TextAlignment = 'Center'
    $script:ToastText = $toastText
    $toast.Child = $toastText
    [System.Windows.Controls.Grid]::SetRow($toast, 1)
    [void]$root.Children.Add($toast)

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(4.2)
    $timer.Add_Tick({
        param($sender, $eventArgs)
        $script:ToastBorder.Visibility = 'Collapsed'
        $script:ToastTimer.Stop()
    })
    $script:ToastTimer = $timer

    $shell = New-Object System.Windows.Controls.Border
    $shell.BorderBrush = Get-Resource 'BorderSubtle'
    $shell.BorderThickness = New-Object System.Windows.Thickness(1)
    $shell.Child = $root
    $window.Content = $shell

    $window.Add_SizeChanged({
        param($sender, $eventArgs)
        $script:Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
            Update-GridColumns
            Update-NavPaneForWidth
            Update-ResponsiveChrome
        }) | Out-Null
    })

    $window.Add_StateChanged({
        param($sender, $eventArgs)
        Update-ChromeState
    })

    $window.Add_Closing({
        param($sender, $eventArgs)
        Close-ElevatedHelper
    })

    $window.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::F5) {
            Refresh-AllVisuals -Notify 'Settings reloaded from the registry'
            $eventArgs.Handled = $true
        } elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            if ($script:SearchBox.Text.Length -gt 0) {
                $script:SearchBox.Text = ''
                $eventArgs.Handled = $true
            }
        } elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::F -and
                  ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
            $script:SearchBox.Focus() | Out-Null
            $eventArgs.Handled = $true
        }
    })

    $navList.SelectedIndex = 0
    return $window
}
