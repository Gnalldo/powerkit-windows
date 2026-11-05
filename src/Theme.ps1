# Theme.ps1 - Windows 11 style palette, live theme switching and the system accent colour.

$script:ThemeMode = 'light'
$script:ThemeBrushes = @{}
$script:ThemeOverridden = $false
$script:ThemeWindows = New-Object System.Collections.ArrayList
$script:AppearanceTimer = $null
$script:AppearanceHooked = $false

function ConvertFrom-HexColor {
    param([string]$Hex)
    return [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
}

function Get-ColorLuminance {
    param([System.Windows.Media.Color]$Color)
    return ((0.299 * $Color.R) + (0.587 * $Color.G) + (0.114 * $Color.B)) / 255
}

function Get-BlendColor {
    param([System.Windows.Media.Color]$Foreground, [System.Windows.Media.Color]$Background, [double]$Amount)
    return [System.Windows.Media.Color]::FromRgb(
        [int][Math]::Round($Background.R + ($Foreground.R - $Background.R) * $Amount),
        [int][Math]::Round($Background.G + ($Foreground.G - $Background.G) * $Amount),
        [int][Math]::Round($Background.B + ($Foreground.B - $Background.B) * $Amount)
    )
}

function Get-LightenedColor {
    param([System.Windows.Media.Color]$Color, [double]$Amount)
    return Get-BlendColor -Foreground ([System.Windows.Media.Colors]::White) -Background $Color -Amount $Amount
}

function Get-SystemThemeMode {
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', $false)
        if ($null -ne $key) {
            $useLight = $key.GetValue('AppsUseLightTheme', 1)
            $key.Close()
            if ([int]$useLight -eq 0) { return 'dark' }
        }
    } catch { }
    return 'light'
}

function Get-SystemAccentColor {
    $fallback = if ($script:ThemeMode -eq 'dark') { '#4CC2FF' } else { '#0067C0' }
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\DWM', $false)
        if ($null -ne $key) {
            $raw = $key.GetValue('AccentColor', $null)
            $key.Close()
            if ($null -ne $raw) {
                # AccentColor is stored as AABBGGRR.
                $value = [int64]$raw
                $r = [int]($value -band 0xFF)
                $g = [int](($value -shr 8) -band 0xFF)
                $b = [int](($value -shr 16) -band 0xFF)
                if (($r + $g + $b) -gt 30) {
                    return [System.Windows.Media.Color]::FromRgb($r, $g, $b)
                }
            }
        }
    } catch { }
    return ConvertFrom-HexColor $fallback
}

function Get-ThemePalette {
    param([string]$Mode)

    $accent = Get-SystemAccentColor
    if ($Mode -eq 'dark' -and (Get-ColorLuminance $accent) -lt 0.35) {
        $accent = Get-LightenedColor -Color $accent -Amount 0.42
    }
    if ($Mode -eq 'light' -and (Get-ColorLuminance $accent) -gt 0.82) {
        $accent = Get-BlendColor -Foreground ([System.Windows.Media.Colors]::Black) -Background $accent -Amount 0.55
    }

    $accentHex = '#{0:X2}{1:X2}{2:X2}' -f $accent.R, $accent.G, $accent.B
    $luminance = Get-ColorLuminance $accent
    $onAccent = if ($luminance -gt 0.62) { '#0B0B0B' } else { '#FFFFFF' }

    if ($Mode -eq 'dark') {
        $card = ConvertFrom-HexColor '#2C2C2C'
        return [ordered]@{
            WindowBg         = '#202020'
            NavBg            = '#1C1C1C'
            HeaderBg         = '#202020'
            CardBg           = '#2C2C2C'
            CardHoverBg      = '#333333'
            InputBg          = '#2D2D2D'
            TextPrimary      = '#FFFFFF'
            TextSecondary    = '#C6C6C6'
            TextTertiary     = '#9A9A9A'
            Accent           = $accentHex
            AccentHover      = ('#{0:X2}{1:X2}{2:X2}' -f (Get-LightenedColor $accent 0.14).R, (Get-LightenedColor $accent 0.14).G, (Get-LightenedColor $accent 0.14).B)
            AccentText       = $onAccent
            AccentSoft       = ('#{0:X2}{1:X2}{2:X2}' -f (Get-BlendColor -Foreground $accent -Background $card -Amount 0.18).R, (Get-BlendColor -Foreground $accent -Background $card -Amount 0.18).G, (Get-BlendColor -Foreground $accent -Background $card -Amount 0.18).B)
            AccentBorderSoft = ('#{0:X2}{1:X2}{2:X2}' -f (Get-BlendColor -Foreground $accent -Background $card -Amount 0.45).R, (Get-BlendColor -Foreground $accent -Background $card -Amount 0.45).G, (Get-BlendColor -Foreground $accent -Background $card -Amount 0.45).B)
            Divider          = '#2F2F2F'
            BorderSubtle     = '#3D3D3D'
            BorderStrong     = '#565656'
            ToggleTrackOff   = '#5C5C5C'
            ToggleTrackEdge  = '#7A7A7A'
            ToggleKnob       = '#FFFFFF'
            AccentKnob       = '#FFFFFF'
            WarnBg           = '#3F3315'
            WarnBorder       = '#6B5620'
            WarnText         = '#FCE9A8'
            WarnGlyph        = '#F5C542'
            PillBg           = '#383838'
            PillText         = '#D2D2D2'
            NavHover         = '#282828'
            NavSelected      = '#343434'
            ScrollThumb      = '#5A5A5A'
            ScrollThumbHover = '#838383'
            SuccessText      = '#6CCB5F'
            DangerText       = '#FF99A4'
            DangerBg         = '#3A2224'
            RowHoverBg       = '#333333'
        }
    }

    $card = ConvertFrom-HexColor '#FFFFFF'
    return [ordered]@{
        WindowBg         = '#F3F3F3'
        NavBg            = '#ECECEC'
        HeaderBg         = '#F3F3F3'
        CardBg           = '#FFFFFF'
        CardHoverBg      = '#FAFAFA'
        InputBg          = '#FFFFFF'
        TextPrimary      = '#1B1B1B'
        TextSecondary    = '#5F5F5F'
        TextTertiary     = '#8A8A8A'
        Accent           = $accentHex
        AccentHover      = ('#{0:X2}{1:X2}{2:X2}' -f (Get-BlendColor -Foreground ([System.Windows.Media.Colors]::Black) -Background $accent -Amount 0.12).R, (Get-BlendColor -Foreground ([System.Windows.Media.Colors]::Black) -Background $accent -Amount 0.12).G, (Get-BlendColor -Foreground ([System.Windows.Media.Colors]::Black) -Background $accent -Amount 0.12).B)
        AccentText       = $onAccent
        AccentSoft       = ('#{0:X2}{1:X2}{2:X2}' -f (Get-BlendColor -Foreground $accent -Background $card -Amount 0.09).R, (Get-BlendColor -Foreground $accent -Background $card -Amount 0.09).G, (Get-BlendColor -Foreground $accent -Background $card -Amount 0.09).B)
        AccentBorderSoft = ('#{0:X2}{1:X2}{2:X2}' -f (Get-BlendColor -Foreground $accent -Background $card -Amount 0.38).R, (Get-BlendColor -Foreground $accent -Background $card -Amount 0.38).G, (Get-BlendColor -Foreground $accent -Background $card -Amount 0.38).B)
        Divider          = '#E4E4E4'
        BorderSubtle     = '#E2E2E2'
        BorderStrong     = '#CBCBCB'
        ToggleTrackOff   = '#9E9E9E'
        ToggleTrackEdge  = '#8E8E8E'
        ToggleKnob       = '#FFFFFF'
        AccentKnob       = '#FFFFFF'
        WarnBg           = '#FFF4CE'
        WarnBorder       = '#E8CE8A'
        WarnText         = '#5C4700'
        WarnGlyph        = '#9D5D00'
        PillBg           = '#EFEFEF'
        PillText         = '#5A5A5A'
        NavHover         = '#E3E3E3'
        NavSelected      = '#DCDCDC'
        ScrollThumb      = '#C6C6C6'
        ScrollThumbHover = '#A5A5A5'
        SuccessText      = '#0F7B0F'
        DangerText       = '#C42B1C'
        DangerBg         = '#FDE7E9'
        RowHoverBg       = '#FAFAFA'
    }
}

function Set-ThemeResources {
    param($Resources, [string]$Mode)

    $script:ThemeMode = $Mode
    $palette = Get-ThemePalette -Mode $Mode

    foreach ($key in $palette.Keys) {
        $color = ConvertFrom-HexColor $palette[$key]

        if ($script:ThemeBrushes.ContainsKey($key)) {
            # The master brush is what PowerShell-built elements hold, and nothing
            # seals it, so recolouring it repaints those elements in place.
            $script:ThemeBrushes[$key].Color = $color
        } else {
            # Command output is wrapped in a PSObject, and WPF casts the stored value
            # straight to Brush, so keep the bare object.
            $script:ThemeBrushes[$key] = (New-Object System.Windows.Media.SolidColorBrush($color)).psobject.BaseObject
        }

        # Styles resolve their {DynamicResource} against the dictionary, and sealing a
        # style freezes whatever it finds there, so park a fresh copy every time
        # instead of trying to recolour a frozen brush.
        if ($null -ne $Resources) {
            $Resources[$key] = (New-Object System.Windows.Media.SolidColorBrush($color)).psobject.BaseObject
        }
    }
}

function Register-ThemeWindow {
    param($Window)

    if ($null -eq $Window) { return }
    if ($script:ThemeWindows.Contains($Window)) { return }

    [void]$script:ThemeWindows.Add($Window)
    $Window.Add_Closed({
        param($sender, $eventArgs)
        [void]$script:ThemeWindows.Remove($sender)
    })
}

function Set-ThemeEverywhere {
    param([string]$Mode)

    # Every window keeps its own resource dictionary, so each one has to be rewritten
    # for the new palette; {DynamicResource} does not reach across window boundaries.
    $windows = @($script:ThemeWindows)
    if ($null -ne $script:Window -and -not ($windows -contains $script:Window)) { $windows += $script:Window }

    if ($windows.Count -eq 0) {
        Set-ThemeResources -Resources $null -Mode $Mode
        return
    }

    foreach ($window in $windows) {
        try {
            Set-ThemeResources -Resources $window.Resources -Mode $Mode
            Set-WindowDarkTitleBar -Window $window -Dark ($Mode -eq 'dark')
        } catch { }
    }
}

function Sync-Appearance {
    # Windows gives a WPF app no dependable theme-change callback, so compare the live
    # system palette with the one on screen instead of waiting to be told.
    $mode = if ($script:ThemeOverridden) { $script:ThemeMode } else { Get-SystemThemeMode }
    $palette = Get-ThemePalette -Mode $mode

    $changed = ($mode -ne $script:ThemeMode)
    if (-not $changed) {
        foreach ($key in $palette.Keys) {
            if (-not $script:ThemeBrushes.ContainsKey($key)) { $changed = $true; break }
            $color = $script:ThemeBrushes[$key].Color
            $current = '#{0:X2}{1:X2}{2:X2}' -f $color.R, $color.G, $color.B
            if ($current -ne $palette[$key]) { $changed = $true; break }
        }
    }

    if ($changed) {
        Set-ThemeEverywhere -Mode $mode
        # Following Windows can flip the sun/moon glyph without anyone clicking.
        Update-ThemeButton
    }
}

function Set-ThemeChoice {
    param([string]$Choice)

    if ($Choice -eq 'system') {
        $script:ThemeOverridden = $false
        $mode = Get-SystemThemeMode
    } else {
        $script:ThemeOverridden = $true
        $mode = $Choice
    }

    Set-ThemeEverywhere -Mode $mode

    # Remembered so a deliberate choice survives a restart.
    $script:Settings['theme'] = $Choice
    Save-AppSettings
    return $mode
}

function Get-ThemeChoiceLabel {
    param([string]$Choice)
    switch ($Choice) {
        'light' { return 'Light theme - kept until you switch back' }
        'dark'  { return 'Dark theme - kept until you switch back' }
        default { return 'Theme now follows Windows' }
    }
}

function Start-AppearanceWatch {
    if ($null -ne $script:AppearanceTimer -or $null -eq $script:Window) { return }

    # Windows notifies WinForms-style watchers immediately; marshal that onto the UI
    # thread so the repaint lands at once instead of at the next poll.
    try {
        if (-not ('PowerKitAppearance.Watcher' -as [type])) {
            # Assembly names alone are not enough here: Add-Type needs resolved paths.
            $references = @(
                [System.Uri].Assembly.Location,
                [Microsoft.Win32.SystemEvents].Assembly.Location,
                [System.Windows.Threading.Dispatcher].Assembly.Location
            )
            Add-Type -Namespace PowerKitAppearance -Name Watcher -ReferencedAssemblies $references -MemberDefinition @'
public static void Watch(System.Windows.Threading.Dispatcher dispatcher, System.Action callback) {
    Microsoft.Win32.SystemEvents.UserPreferenceChanged += delegate(object sender, Microsoft.Win32.UserPreferenceChangedEventArgs args) {
        if (args.Category == Microsoft.Win32.UserPreferenceCategory.General ||
            args.Category == Microsoft.Win32.UserPreferenceCategory.Color ||
            args.Category == Microsoft.Win32.UserPreferenceCategory.VisualStyle) {
            dispatcher.BeginInvoke(callback, System.Windows.Threading.DispatcherPriority.Background);
        }
    };
}
'@ -ErrorAction Stop
        }
        [PowerKitAppearance.Watcher]::Watch($script:Window.Dispatcher, [Action]{ Sync-Appearance })
        $script:AppearanceHooked = $true
    } catch {
        $script:AppearanceHooked = $false
    }

    # The poll remains as a safety net for changes that raise no notification.
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds($(if ($script:AppearanceHooked) { 20 } else { 3 }))
    $timer.Add_Tick({
        param($sender, $eventArgs)
        Sync-Appearance
    })
    $script:AppearanceTimer = $timer
    $timer.Start()
}

function Set-WindowDarkTitleBar {
    param($Window, [bool]$Dark)

    if (-not ('PowerKit.Native' -as [type])) {
        try {
            Add-Type -Namespace PowerKit -Name Native -MemberDefinition @'
[DllImport("dwmapi.dll", SetLastError = true)]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
'@ -ErrorAction Stop
        } catch {
            return
        }
    }

    try {
        $handle = (New-Object System.Windows.Interop.WindowInteropHelper($Window)).Handle
        $flag = if ($Dark) { 1 } else { 0 }
        [PowerKit.Native]::DwmSetWindowAttribute($handle, 20, [ref]$flag, 4) | Out-Null
        [PowerKit.Native]::DwmSetWindowAttribute($handle, 19, [ref]$flag, 4) | Out-Null
    } catch { }
}
