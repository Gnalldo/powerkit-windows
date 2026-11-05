# PowerKit - Windows 11 power tools.
# Run PowerKit.cmd (or this file with powershell -STA) to open the app.
# -Focus <card id> opens straight at that card, which is how a pinned desktop-menu
# entry jumps to its tweak or command.

param(
    [string]$Focus = ''
)

$ErrorActionPreference = 'Stop'

$script:AppRoot = $PSScriptRoot
$script:ScriptPath = $PSCommandPath

function Show-FatalError {
    param([string]$Message)

    try {
        $logDir = Join-Path $env:LOCALAPPDATA 'PowerKit'
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Add-Content -LiteralPath (Join-Path $logDir 'app.log') -Value ('{0}  FATAL  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    } catch { }

    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show($Message, 'PowerKit could not start', 'OK', 'Error') | Out-Null
    } catch { }
}

try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        $exe = (Get-Process -Id $PID).Path
        $relaunch = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
        if ($Focus) { $relaunch += @('-Focus', "`"$Focus`"") }
        Start-Process -FilePath $exe -ArgumentList $relaunch | Out-Null
        exit
    }

    . (Join-Path $script:AppRoot 'src\Theme.ps1')
    . (Join-Path $script:AppRoot 'src\RegistryTools.ps1')
    . (Join-Path $script:AppRoot 'src\Catalog.ps1')
    . (Join-Path $script:AppRoot 'src\Commands.ps1')
    . (Join-Path $script:AppRoot 'src\AiBuilder.ps1')
    . (Join-Path $script:AppRoot 'src\Interactions.ps1')
    . (Join-Path $script:AppRoot 'src\Elevation.ps1')
    . (Join-Path $script:AppRoot 'src\Ui.ps1')
    . (Join-Path $script:AppRoot 'src\LogViewer.ps1')
    . (Join-Path $script:AppRoot 'src\DesktopMenu.ps1')

    Start-PowerKit -Focus $Focus
} catch {
    Show-FatalError -Message ($_.Exception.Message + "`n`n" + $_.ScriptStackTrace)
}
