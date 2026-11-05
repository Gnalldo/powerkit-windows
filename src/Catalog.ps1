# Catalog.ps1 - all groups, registry tweaks and one-click commands.
# Registry values are expressed as: Hive, Path, Name ('' = default value), Kind, On, Off.
# On/Off of $null means "delete the value" (or the whole key when DeleteKey is set).

$script:GroupDefs = @(
    @{ Id = 'explorer';     Title = 'File Explorer';        Subtitle = 'Browsing, context menu and folder behaviour'; Letter = 'FE' }
    @{ Id = 'taskbar';      Title = 'Taskbar and Start';    Subtitle = 'Taskbar layout, Start menu and search';       Letter = 'TB' }
    @{ Id = 'appearance';   Title = 'Appearance';           Subtitle = 'Theme, effects and window behaviour';         Letter = 'AP' }
    @{ Id = 'performance';  Title = 'Performance';          Subtitle = 'Startup, gaming and input responsiveness';    Letter = 'PF' }
    @{ Id = 'privacy';      Title = 'Privacy and Ads';      Subtitle = 'Telemetry, advertising and suggestions';      Letter = 'PV' }
    @{ Id = 'system';       Title = 'System and Updates';   Subtitle = 'Developer features, updates and policies';    Letter = 'SY' }
    @{ Id = 'power';        Title = 'Power and Session';    Subtitle = 'One click restart, sleep and power plans';    Letter = 'PW' }
    @{ Id = 'tools';        Title = 'Quick Tools';          Subtitle = 'Jump straight to Windows management tools';   Letter = 'TL' }
)

$script:TweakDefs = @(

    # ---------------- File Explorer ----------------
    @{
        Id = 'show-ext'; Group = 'explorer'; Title = 'Show file extensions'
        Desc = 'Makes Explorer display the real extension of every file, so invoice.pdf.exe is visible as what it is.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideFileExt'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'show-hidden'; Group = 'explorer'; Title = 'Show hidden files'
        Desc = 'Reveals files and folders that carry the hidden attribute, including AppData and program settings folders.'
        Risk = 'safe'; Restart = 'explorer'
        Warning = 'Hidden files are often system-critical. Deleting the wrong one can break apps or your profile.'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Hidden'; Kind = 'DWord'; On = 1; Off = 2 })
    }
    @{
        Id = 'show-os-files'; Group = 'explorer'; Title = 'Show protected operating system files'
        Desc = 'Also shows files marked as protected system files, such as desktop.ini, bootmgr and pagefile.sys.'
        Risk = 'advanced'; Restart = 'explorer'
        Warning = 'These files are hidden for a reason. Editing or removing them can make Windows unbootable.'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSuperHidden'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'seconds-clock'; Group = 'explorer'; Title = 'Show seconds in the taskbar clock'
        Desc = 'Adds a seconds field to the clock in the notification area, so the time reads 14:32:07 instead of 14:32.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSecondsInSystemClock'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'classic-menu'; Group = 'explorer'; Title = 'Classic right-click menu'
        Desc = 'Restores the full Windows 10 style context menu instead of the shortened Windows 11 one, bringing back every shell verb at once.'
        Risk = 'caution'; Restart = 'explorer'
        Warning = 'After a feature update Windows may re-register the new menu, in which case simply toggle this off and on again.'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'; Name = ''; Kind = 'String'; On = ''; Off = $null; DeleteKey = $true })
    }
    @{
        Id = 'this-pc'; Group = 'explorer'; Title = 'Open Explorer to This PC'
        Desc = 'File Explorer starts on This PC with your drives, rather than the Home / Quick access view.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'LaunchTo'; Kind = 'DWord'; On = 1; Off = $null })
    }
    @{
        Id = 'full-path'; Group = 'explorer'; Title = 'Full path in the title bar'
        Desc = 'Shows the complete folder path in the Explorer window title instead of only the folder name.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState'; Name = 'FullPath'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'checkboxes'; Group = 'explorer'; Title = 'Item check boxes'
        Desc = 'Adds a checkbox to every file and folder so you can select several without holding Ctrl.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'AutoCheckSelect'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'nav-all-folders'; Group = 'explorer'; Title = 'All folders in the navigation pane'
        Desc = 'Lists every shell folder in the left navigation pane, including Control Panel and Recycle Bin.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'NavPaneShowAllFolders'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'compact-view'; Group = 'explorer'; Title = 'Compact view for files and folders'
        Desc = 'Tightens row spacing in Explorer so more files fit on screen at once.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'UseCompactMode'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'no-recent-files'; Group = 'explorer'; Title = 'Stop tracking recent files'
        Desc = 'Stops Windows from recording recently opened documents and showing them in Quick access and jump lists.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackDocs'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'hide-desktop-icons'; Group = 'explorer'; Title = 'Hide desktop icons'
        Desc = 'Hides every icon on the desktop while keeping the files where they are, for a clean wallpaper view.'
        Risk = 'caution'; Restart = 'explorer'
        Warning = 'Files are not deleted, only hidden. Turn the tweak off again to bring the icons back.'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideIcons'; Kind = 'DWord'; On = 1; Off = 0 })
    }

    # ---------------- Taskbar and Start ----------------
    @{
        Id = 'taskbar-left'; Group = 'taskbar'; Title = 'Left-align the taskbar'
        Desc = 'Moves the Start button and taskbar icons to the left edge, the classic Windows layout.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAl'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'hide-widgets'; Group = 'taskbar'; Title = 'Hide the Widgets button'
        Desc = 'Removes the weather and widgets button from the taskbar, freeing space next to the Start button.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarDa'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'hide-chat'; Group = 'taskbar'; Title = 'Hide the Chat / Teams button'
        Desc = 'Removes the Chat (or Teams) consumer icon from the taskbar.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarMn'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'hide-search'; Group = 'taskbar'; Title = 'Hide the taskbar search box'
        Desc = 'Collapses the search box entirely. Pressing the Windows key and typing still searches.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'SearchboxTaskbarMode'; Kind = 'DWord'; On = 0; Off = 2 })
    }
    @{
        Id = 'hide-taskview'; Group = 'taskbar'; Title = 'Hide the Task View button'
        Desc = 'Removes the Task View button from the taskbar. Win+Tab still opens the same view.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTaskViewButton'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'hide-copilot'; Group = 'taskbar'; Title = 'Hide the Copilot button'
        Desc = 'Removes the Copilot icon from the taskbar on builds that ship it.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCopilotButton'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'end-task'; Group = 'taskbar'; Title = 'End task in the taskbar menu'
        Desc = 'Adds End task to the taskbar right-click menu, so a hung app can be killed in two clicks.'
        Risk = 'caution'; Restart = 'explorer'
        Warning = 'Using End task on a system process can close the desktop or sign you out without warning.'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarEndTask'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'small-taskbar'; Group = 'taskbar'; Title = 'Small taskbar buttons'
        Desc = 'Shrinks taskbar icons so more apps fit before they start collapsing into a scroll list.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarSmallIcons'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'tray-all-icons'; Group = 'taskbar'; Title = 'Show all system tray icons'
        Desc = 'Stops Windows from hiding background app icons behind the overflow chevron.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer'; Name = 'EnableAutoTray'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'no-start-recs'; Group = 'taskbar'; Title = 'Hide Start menu recommendations'
        Desc = 'Removes the Recommended section content from Start, leaving a tighter pinned app list.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_IrisRecommendations'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'no-track-apps'; Group = 'taskbar'; Title = 'Stop tracking app launches'
        Desc = 'Stops Windows recording which programs you start, which feeds Start suggestions and jump lists.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackProgs'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'no-web-search'; Group = 'taskbar'; Title = 'No web results in Start search'
        Desc = 'Keeps Start menu search local to your PC and stops Bing answers being injected into the results.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Kind = 'DWord'; On = 0; Off = 1 })
    }

    # ---------------- Appearance ----------------
    @{
        Id = 'dark-apps'; Group = 'appearance'; Title = 'Dark mode for apps'
        Desc = 'Switches apps and settings surfaces to the dark colour scheme.'
        Risk = 'safe'; Restart = $null
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'AppsUseLightTheme'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'dark-system'; Group = 'appearance'; Title = 'Dark mode for taskbar and Start'
        Desc = 'Applies the dark colour scheme to the taskbar, Start menu, notification centre and Action Centre.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'SystemUsesLightTheme'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'transparency'; Group = 'appearance'; Title = 'Transparency effects'
        Desc = 'Enables the translucent, blurred surfaces used by the Start menu, taskbar and flyouts.'
        Risk = 'safe'; Restart = $null
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'EnableTransparency'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'accent-titlebars'; Group = 'appearance'; Title = 'Accent colour on title bars'
        Desc = 'Paints window title bars and borders with your Windows accent colour instead of the plain neutral tone.'
        Risk = 'safe'; Restart = 'explorer'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\DWM'; Name = 'ColorPrevalence'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'no-animations'; Group = 'appearance'; Title = 'Disable window animations'
        Desc = 'Turns off the minimise and maximise animation, making window changes feel instant.'
        Risk = 'caution'; Restart = 'signout'
        Values = @(@{ Hive = 'HKCU'; Path = 'Control Panel\Desktop\WindowMetrics'; Name = 'MinAnimate'; Kind = 'String'; On = '0'; Off = '1' })
    }
    @{
        Id = 'instant-menus'; Group = 'appearance'; Title = 'Instant menu response'
        Desc = 'Removes the 400 ms delay before menus and the Start menu appear on hover.'
        Risk = 'caution'; Restart = 'signout'
        Warning = 'Some menu hover behaviour can feel twitchy with no delay at all. Reset restores the 400 ms default.'
        Values = @(@{ Hive = 'HKCU'; Path = 'Control Panel\Desktop'; Name = 'MenuShowDelay'; Kind = 'String'; On = '0'; Off = '400' })
    }
    @{
        Id = 'no-aero-shake'; Group = 'appearance'; Title = 'Disable Aero Shake'
        Desc = 'Stops shaking a window with the mouse from minimising every other window.'
        Risk = 'safe'; Restart = $null
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'DisallowShaking'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'no-snap-assist'; Group = 'appearance'; Title = 'Disable Snap Assist suggestions'
        Desc = 'When you snap one window, stops Windows offering the rest of your windows to fill the other half.'
        Risk = 'safe'; Restart = $null
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'SnapAssist'; Kind = 'DWord'; On = 0; Off = 1 })
    }

    # ---------------- Performance ----------------
    @{
        Id = 'fast-startup'; Group = 'performance'; Title = 'Disable Fast Startup'
        Desc = 'Forces a real shutdown every time, so drivers and hardware re-initialise cleanly on boot.'
        Risk = 'caution'; Restart = 'reboot'; Admin = $true
        Warning = 'Boot may be a few seconds slower. Worth doing if you dual-boot, use BitLocker or see odd driver behaviour after shutdown.'
        Values = @(@{ Hive = 'HKLM'; Path = 'SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'HiberbootEnabled'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'startup-delay'; Group = 'performance'; Title = 'Remove startup app delay'
        Desc = 'Cuts the artificial 10 second delay Windows adds before launching your startup apps.'
        Risk = 'safe'; Restart = 'signout'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; Name = 'StartupDelayInMSec'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'gamedvr'; Group = 'performance'; Title = 'Disable Xbox Game Bar capture'
        Desc = 'Turns off background game recording and the capture overlay, which costs frames in some games.'
        Risk = 'safe'; Restart = 'signout'
        Values = @(
            @{ Hive = 'HKCU'; Path = 'System\GameConfigStore'; Name = 'GameDVR_Enabled'; Kind = 'DWord'; On = 0; Off = 1 }
            @{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'AppCaptureEnabled'; Kind = 'DWord'; On = 0; Off = 1 }
        )
    }
    @{
        Id = 'mouse-accel'; Group = 'performance'; Title = 'Disable mouse acceleration'
        Desc = 'Removes Enhance pointer precision so cursor distance maps linearly to how far you move the mouse.'
        Risk = 'caution'; Restart = 'signout'
        Warning = 'The cursor will feel different until you adjust to it. Most competitive players prefer it off.'
        Values = @(
            @{ Hive = 'HKCU'; Path = 'Control Panel\Mouse'; Name = 'MouseSpeed'; Kind = 'String'; On = '0'; Off = '1' }
            @{ Hive = 'HKCU'; Path = 'Control Panel\Mouse'; Name = 'MouseThreshold1'; Kind = 'String'; On = '0'; Off = '6' }
            @{ Hive = 'HKCU'; Path = 'Control Panel\Mouse'; Name = 'MouseThreshold2'; Kind = 'String'; On = '0'; Off = '10' }
        )
    }
    @{
        Id = 'power-throttle'; Group = 'performance'; Title = 'Disable power throttling'
        Desc = 'Stops Windows parking background work in a low power state, keeping CPU-heavy background tasks responsive.'
        Risk = 'advanced'; Restart = 'reboot'; Admin = $true
        Warning = 'Noticeably worse battery life on laptops and higher idle power draw on desktops.'
        Values = @(@{ Hive = 'HKLM'; Path = 'SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'; Name = 'PowerThrottlingOff'; Kind = 'DWord'; On = 1; Off = 0 })
    }

    # ---------------- Privacy and Ads ----------------
    @{
        Id = 'no-ad-id'; Group = 'privacy'; Title = 'Disable the advertising ID'
        Desc = 'Stops apps assigning you a per-user advertising identifier and using it to personalise ads.'
        Risk = 'safe'; Restart = 'signout'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'no-activity'; Group = 'privacy'; Title = 'Disable activity history'
        Desc = 'Stops Windows publishing and uploading your app and document activity to your Microsoft account timeline.'
        Risk = 'safe'; Restart = 'signout'
        Values = @(
            @{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'PublishUserActivities'; Kind = 'DWord'; On = 0; Off = 1 }
            @{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'UploadUserActivities'; Kind = 'DWord'; On = 0; Off = 1 }
        )
    }
    @{
        Id = 'no-feedback'; Group = 'privacy'; Title = 'Stop feedback requests'
        Desc = 'Stops Windows periodically asking you for feedback about the operating system.'
        Risk = 'safe'; Restart = 'signout'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Siuf\Rules'; Name = 'NumberOfSIUFInPeriod'; Kind = 'DWord'; On = 0; Off = $null })
    }
    @{
        Id = 'no-suggestions'; Group = 'privacy'; Title = 'Disable tips and suggestions'
        Desc = 'Turns off the app suggestions, tips and promoted content Windows shows in Start and Settings.'
        Risk = 'safe'; Restart = 'signout'
        Values = @(
            @{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; Kind = 'DWord'; On = 0; Off = 1 }
            @{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338393Enabled'; Kind = 'DWord'; On = 0; Off = 1 }
            @{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353694Enabled'; Kind = 'DWord'; On = 0; Off = 1 }
            @{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353696Enabled'; Kind = 'DWord'; On = 0; Off = 1 }
            @{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled'; Kind = 'DWord'; On = 0; Off = 1 }
            @{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Kind = 'DWord'; On = 0; Off = 1 }
        )
    }
    @{
        Id = 'min-telemetry'; Group = 'privacy'; Title = 'Minimum diagnostic data'
        Desc = 'Applies the policy that asks Windows to send only the required diagnostic data instead of optional data.'
        Risk = 'advanced'; Restart = 'reboot'; Admin = $true
        Warning = 'This policy is only fully honoured on Windows Pro, Enterprise and Education. Home edition largely ignores it.'
        Values = @(@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'no-location'; Group = 'privacy'; Title = 'Deny location access'
        Desc = 'Blocks location access for all apps at the system consent store, overriding per-app settings.'
        Risk = 'caution'; Restart = 'signout'; Admin = $true
        Warning = 'Maps, weather, Find my device and automatic time zone all stop working until you reset this.'
        Values = @(@{ Hive = 'HKLM'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'; Name = 'Value'; Kind = 'String'; On = 'Deny'; Off = 'Allow' })
    }
    @{
        Id = 'no-clipboard-sync'; Group = 'privacy'; Title = 'Disable clipboard cloud sync'
        Desc = 'Stops clipboard history syncing between this PC and your other devices signed in to the same account.'
        Risk = 'safe'; Restart = 'signout'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Clipboard'; Name = 'AllowCrossDeviceClipboard'; Kind = 'DWord'; On = 0; Off = 1 })
    }
    @{
        Id = 'no-bg-apps'; Group = 'privacy'; Title = 'Disable background apps'
        Desc = 'Forces every packaged app to stop running in the background when it is not in use.'
        Risk = 'caution'; Restart = 'signout'; Admin = $true
        Warning = 'Mail, chat and other apps will no longer receive updates or notifications while closed.'
        Values = @(@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; Name = 'LetAppsRunInBackground'; Kind = 'DWord'; On = 2; Off = 0 })
    }
    @{
        Id = 'tailored-exp'; Group = 'privacy'; Title = 'Disable tailored experiences'
        Desc = 'Stops Windows using your diagnostic data to tailor tips, ads and recommendations to you.'
        Risk = 'safe'; Restart = 'signout'
        Values = @(@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Kind = 'DWord'; On = 0; Off = 1 })
    }

    # ---------------- System and Updates ----------------
    @{
        Id = 'long-paths'; Group = 'system'; Title = 'Enable long file path support'
        Desc = 'Lifts the 260 character path limit for tools and apps that opt in, common with node_modules and deep build trees.'
        Risk = 'advanced'; Restart = 'reboot'; Admin = $true
        Warning = 'Very old installers and backup utilities can misbehave with paths over 260 characters.'
        Values = @(@{ Hive = 'HKLM'; Path = 'SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'LongPathsEnabled'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'dev-mode'; Group = 'system'; Title = 'Developer Mode'
        Desc = 'Allows sideloading apps, device portal access and package deployment without a developer account.'
        Risk = 'caution'; Restart = 'signout'; Admin = $true
        Values = @(@{ Hive = 'HKLM'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'; Name = 'AllowDevelopmentWithoutDevLicense'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'verbose-status'; Group = 'system'; Title = 'Verbose startup and shutdown'
        Desc = 'Shows detailed status messages instead of a spinner during startup, shutdown and sign-in, useful when diagnosing hangs.'
        Risk = 'safe'; Restart = 'reboot'; Admin = $true
        Values = @(@{ Hive = 'HKLM'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'VerboseStatus'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'no-update-autoreboot'; Group = 'system'; Title = 'Block update auto-restart'
        Desc = 'Stops Windows restarting on its own to finish installing updates while you are signed in.'
        Risk = 'caution'; Restart = $null; Admin = $true
        Warning = 'Updates still install, they just stop forcing a restart at an inconvenient moment.'
        Values = @(@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'NoAutoRebootWithLoggedOnUsers'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'no-auto-update'; Group = 'system'; Title = 'Disable automatic updates'
        Desc = 'Applies the policy that stops Windows Update downloading and installing updates automatically.'
        Risk = 'advanced'; Restart = 'reboot'; Admin = $true
        Warning = 'You will stop receiving security fixes automatically. Only enable this if you patch on your own schedule.'
        Values = @(@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'NoAutoUpdate'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'no-lockscreen'; Group = 'system'; Title = 'Skip the lock screen'
        Desc = 'Goes straight to the sign-in prompt instead of the lock screen wallpaper and clock.'
        Risk = 'caution'; Restart = 'signout'; Admin = $true
        Warning = 'This policy is not honoured on Windows Home in most builds.'
        Values = @(@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\Personalization'; Name = 'NoLockScreen'; Kind = 'DWord'; On = 1; Off = 0 })
    }
    @{
        Id = 'numlock'; Group = 'system'; Title = 'Num Lock on at sign-in'
        Desc = 'Turns Num Lock on by default when the sign-in screen appears.'
        Risk = 'caution'; Restart = 'signout'
        Values = @(@{ Hive = 'HKCU'; Path = 'Control Panel\Keyboard'; Name = 'InitialKeyboardIndicators'; Kind = 'String'; On = '2'; Off = '2147483648' })
    }
    @{
        Id = 'bsod-details'; Group = 'system'; Title = 'Detailed blue screen information'
        Desc = 'Adds the bug check parameters and driver names to the stop error screen for easier diagnosis.'
        Risk = 'safe'; Restart = 'reboot'; Admin = $true
        Values = @(@{ Hive = 'HKLM'; Path = 'SYSTEM\CurrentControlSet\Control\CrashControl'; Name = 'DisplayParameters'; Kind = 'DWord'; On = 1; Off = 0 })
    }
)

$script:CommandDefs = @(

    # ---------------- Power and session ----------------
    @{
        Id = 'restart'; Group = 'power'; Title = 'Restart now'
        Desc = 'Reboots the PC immediately. Windows closes apps without asking, so save your work first.'
        Risk = 'caution'; Handler = 'Restart'; Confirm = 'Restart this PC now? Unsaved work in open apps will be lost.'; ConfirmLabel = 'Restart'
    }
    @{
        Id = 'shutdown'; Group = 'power'; Title = 'Shut down'
        Desc = 'Powers the PC off immediately. Unsaved work in open apps will be lost.'
        Risk = 'caution'; Handler = 'Shutdown'; Confirm = 'Shut down this PC now? Unsaved work in open apps will be lost.'; ConfirmLabel = 'Shut down'
    }
    @{
        Id = 'signout'; Group = 'power'; Title = 'Sign out'
        Desc = 'Ends your session and closes every app, returning to the sign-in screen.'
        Risk = 'caution'; Handler = 'SignOut'; Confirm = 'Sign out now? All apps will be closed.'; ConfirmLabel = 'Sign out'
    }
    @{
        Id = 'sleep'; Group = 'power'; Title = 'Sleep'
        Desc = 'Puts the PC into low power sleep and wakes on keyboard or mouse.'
        Risk = 'safe'; Handler = 'Sleep'
    }
    @{
        Id = 'hibernate'; Group = 'power'; Title = 'Hibernate'
        Desc = 'Writes the session to disk and powers off completely, resuming where you left off.'
        Risk = 'safe'; Handler = 'Hibernate'
    }
    @{
        Id = 'lock'; Group = 'power'; Title = 'Lock this PC'
        Desc = 'Locks the session without closing anything. Unlock with your password or PIN.'
        Risk = 'safe'; Handler = 'Lock'
    }
    @{
        Id = 'firmware'; Group = 'power'; Title = 'Restart to firmware settings'
        Desc = 'Reboots straight into the UEFI / BIOS setup screen without needing to catch the boot key.'
        Risk = 'advanced'; Handler = 'Firmware'; Admin = $true
        Warning = 'The PC must support UEFI firmware settings; on older BIOS systems this is ignored.'
        Confirm = 'Restart into UEFI firmware settings now?'; ConfirmLabel = 'Restart to UEFI'
    }
    @{
        Id = 'cancel-shutdown'; Group = 'power'; Title = 'Cancel pending shutdown'
        Desc = 'Aborts a shutdown, restart or logoff that is currently counting down.'
        Risk = 'safe'; Handler = 'CancelShutdown'
    }
    @{
        Id = 'restart-explorer'; Group = 'power'; Title = 'Restart Explorer'
        Desc = 'Restarts the shell process. Applies tweaks that need Explorer reloaded and fixes a frozen taskbar.'
        Risk = 'caution'; Handler = 'RestartExplorer'
        Warning = 'Open File Explorer windows close and the taskbar disappears for a second.'
    }
    @{
        Id = 'plan-high'; Group = 'power'; Title = 'High performance power plan'
        Desc = 'Switches to the High performance plan, keeping CPU clocks high at the cost of power draw.'
        Risk = 'safe'; Handler = 'PlanHigh'
    }
    @{
        Id = 'plan-balanced'; Group = 'power'; Title = 'Balanced power plan'
        Desc = 'Restores the default Balanced plan, which scales clocks with load and saves power.'
        Risk = 'safe'; Handler = 'PlanBalanced'
    }
    @{
        Id = 'plan-ultimate'; Group = 'power'; Title = 'Ultimate performance plan'
        Desc = 'Creates the hidden Ultimate Performance plan if needed and activates it for maximum responsiveness.'
        Risk = 'caution'; Handler = 'PlanUltimate'; Admin = $true
        Warning = 'Adds latency to battery life and idle power. Intended for desktops and workstations.'
    }
    @{
        Id = 'hibernate-off'; Group = 'power'; Title = 'Disable hibernation and Fast Startup'
        Desc = 'Turns the hibernation file off, freeing several GB of disk and removing Fast Startup.'
        Risk = 'caution'; Handler = 'HibernateOff'; Admin = $true
        Warning = 'Hibernate and the Fast Startup boot path stop working until you re-enable it.'
        Confirm = 'Disable hibernation? The hiberfil.sys file will be removed and Fast Startup disabled.'; ConfirmLabel = 'Disable'
    }
    @{
        Id = 'hibernate-on'; Group = 'power'; Title = 'Enable hibernation'
        Desc = 'Turns the hibernation file back on so Hibernate and Fast Startup work again.'
        Risk = 'safe'; Handler = 'HibernateOn'; Admin = $true
    }

    # ---------------- Quick tools ----------------
    @{
        Id = 'tool-cmd'; Group = 'tools'; Title = 'Command Prompt'
        Desc = 'Opens a standard command prompt window in your user profile.'
        Risk = 'safe'; Handler = 'OpenCmd'
    }
    @{
        Id = 'tool-pwsh'; Group = 'tools'; Title = 'PowerShell'
        Desc = 'Opens a PowerShell window, already in your user profile.'
        Risk = 'caution'; Handler = 'OpenPwsh'
        Warning = 'Anything you type here runs with your permissions. Close the window when you are done.'
    }
    @{
        Id = 'tool-terminal'; Group = 'tools'; Title = 'Windows Terminal'
        Desc = 'Opens Windows Terminal when it is installed, and Command Prompt otherwise.'
        Risk = 'safe'; Handler = 'OpenWindowsTerminal'
    }
    @{
        Id = 'tool-taskmgr'; Group = 'tools'; Title = 'Task Manager'
        Desc = 'Processes, startup impact, performance graphs and services in one window.'
        Risk = 'safe'; Handler = 'OpenTaskmgr'
    }
    @{
        Id = 'tool-settings'; Group = 'tools'; Title = 'Windows Settings'
        Desc = 'Opens the Settings app at its home page.'
        Risk = 'safe'; Handler = 'OpenSettings'
    }
    @{
        Id = 'tool-services'; Group = 'tools'; Title = 'Services'
        Desc = 'Start, stop and change the startup type of every Windows service.'
        Risk = 'caution'; Handler = 'OpenServices'
        Warning = 'Setting a critical service to Disabled can prevent Windows from starting.'
    }
    @{
        Id = 'tool-devmgmt'; Group = 'tools'; Title = 'Device Manager'
        Desc = 'Inspect hardware, drivers and devices reporting problems.'
        Risk = 'safe'; Handler = 'OpenDevMgmt'
    }
    @{
        Id = 'tool-cleanmgr'; Group = 'tools'; Title = 'Disk Cleanup'
        Desc = 'Removes Windows update leftovers, old logs and temporary files.'
        Risk = 'safe'; Handler = 'OpenCleanmgr'
    }
    @{
        Id = 'tool-sysdm'; Group = 'tools'; Title = 'System Properties'
        Desc = 'Computer name, performance options, virtual memory and system protection.'
        Risk = 'safe'; Handler = 'OpenSysdm'
    }
    @{
        Id = 'tool-powercfg'; Group = 'tools'; Title = 'Power Options'
        Desc = 'Manage power plans, sleep timers and what the power buttons do.'
        Risk = 'safe'; Handler = 'OpenPowerOptions'
    }
    @{
        Id = 'tool-regedit'; Group = 'tools'; Title = 'Registry Editor'
        Desc = 'The raw registry editor for anything this app does not cover.'
        Risk = 'advanced'; Handler = 'OpenRegedit'
        Warning = 'Editing the registry by hand can make Windows unbootable. Back up the key first.'
    }
    @{
        Id = 'tool-control'; Group = 'tools'; Title = 'Control Panel'
        Desc = 'The classic Control Panel, still home to many advanced settings.'
        Risk = 'safe'; Handler = 'OpenControl'
    }
    @{
        Id = 'tool-ncpa'; Group = 'tools'; Title = 'Network connections'
        Desc = 'Adapter list for IP settings, DNS servers and disabling interfaces.'
        Risk = 'safe'; Handler = 'OpenNetwork'
    }
    @{
        Id = 'tool-wu'; Group = 'tools'; Title = 'Windows Update'
        Desc = 'Opens the update page in Settings to check for and install updates.'
        Risk = 'safe'; Handler = 'OpenWindowsUpdate'
    }
    @{
        Id = 'tool-startup'; Group = 'tools'; Title = 'Startup apps'
        Desc = 'Opens the Startup page so you can disable apps that slow the sign-in.'
        Risk = 'safe'; Handler = 'OpenStartupApps'
    }
    @{
        Id = 'tool-msinfo'; Group = 'tools'; Title = 'System Information'
        Desc = 'Full hardware, BIOS and component report for this machine.'
        Risk = 'safe'; Handler = 'OpenMsinfo'
    }
    @{
        Id = 'tool-godmode'; Group = 'tools'; Title = 'Create God Mode folder'
        Desc = 'Adds a desktop folder that exposes every Windows control panel applet in one place.'
        Risk = 'safe'; Handler = 'CreateGodMode'
    }
    @{
        Id = 'tool-flushdns'; Group = 'tools'; Title = 'Flush DNS cache'
        Desc = 'Clears resolved hostnames so stale or wrong DNS answers are looked up again.'
        Risk = 'safe'; Handler = 'FlushDns'; Admin = $true
    }
    @{
        Id = 'tool-temp'; Group = 'tools'; Title = 'Clear temporary files'
        Desc = 'Deletes the contents of your user temp folder and reports how much was freed.'
        Risk = 'caution'; Handler = 'ClearTemp'
        Warning = 'Locked files are skipped. Close installers and editors first so nothing is recreated mid-cleanup.'
        Confirm = 'Delete everything inside your temp folder? Files in use will be skipped.'; ConfirmLabel = 'Clear temp'
    }
)
