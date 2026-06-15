<#
.SYNOPSIS
  ClearAndPowerPC - manutenzione Windows guidata da menu.

.DESCRIPTION
  Pulisce file temporanei/cache, ripara Windows, aggiorna app, cerca online driver
  tramite Windows Update/Microsoft Update e strumenti vendor affidabili, e applica
  impostazioni display conservative per massima risoluzione/frequenza disponibile.

  Eseguire da PowerShell come Amministratore:
    Set-ExecutionPolicy -Scope Process Bypass -Force
    .\ClearAndPowerPC.ps1 -Menu

  Esecuzione completa senza menu:
    .\ClearAndPowerPC.ps1 -All

  Simulazione senza modifiche:
    .\ClearAndPowerPC.ps1 -All -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch]$Menu,
    [switch]$All,
    [switch]$Clean,
    [switch]$UpdateApps,
    [switch]$WindowsUpdate,
    [switch]$Drivers,
    [switch]$RepairSystem,
    [switch]$Optimize,
    [switch]$PerfectDisplay,
    [switch]$CreateRestorePoint = $true,
    [switch]$SkipRestorePoint,
    [switch]$NoReboot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$LogRoot = Join-Path $env:ProgramData 'ClearAndPowerPC'
$LogFile = Join-Path $LogRoot ('run-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR')][string]$Level = 'INFO'
    )
    $line = '[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}' -f (Get-Date), $Level, $Message
    $color = switch ($Level) { 'OK' {'Green'} 'WARN' {'Yellow'} 'ERROR' {'Red'} default {'Cyan'} }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Step {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$Action
    )
    Write-Log "Avvio: $Name"
    try {
        & $Action
        Write-Log "Completato: $Name" 'OK'
    } catch {
        Write-Log "Errore in '$Name': $($_.Exception.Message)" 'ERROR'
    }
}

function Remove-PathSafe {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($PSCmdlet.ShouldProcess($Path, 'Rimozione contenuti temporanei')) {
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop }
            catch { Write-Log "Non rimosso: $($_.FullName) - $($_.Exception.Message)" 'WARN' }
        }
    }
}

function New-SafeRestorePoint {
    if ($SkipRestorePoint) { Write-Log 'Punto di ripristino saltato su richiesta.' 'WARN'; return }
    if (-not $CreateRestorePoint) { return }
    if ($PSCmdlet.ShouldProcess('Sistema', 'Creazione punto di ripristino')) {
        try {
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description 'Prima di ClearAndPowerPC' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
            Write-Log 'Punto di ripristino creato.' 'OK'
        } catch {
            Write-Log "Punto di ripristino non creato: $($_.Exception.Message)" 'WARN'
        }
    }
}

function Get-HardwareProfile {
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue | ForEach-Object {
        $name = ($_.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ''
        $serial = ($_.SerialNumberID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ''
        [pscustomobject]@{ Name = if ($name) { $name } else { 'Monitor generico' }; Serial = $serial }
    }
    [pscustomobject]@{ Gpus = $gpus; Monitors = $monitors }
}

function Show-HardwareProfile {
    $profile = Get-HardwareProfile
    Write-Log 'Schede video rilevate:'
    foreach ($gpu in $profile.Gpus) { Write-Log (' - {0} | Driver {1} | {2} MB' -f $gpu.Name, $gpu.DriverVersion, [math]::Round($gpu.AdapterRAM / 1MB)) }
    Write-Log 'Schermi rilevati:'
    foreach ($monitor in $profile.Monitors) { Write-Log (' - {0} {1}' -f $monitor.Name, $monitor.Serial) }
}

function Invoke-Cleaning {
    $paths = @(
        $env:TEMP,
        "$env:WINDIR\Temp",
        "$env:LOCALAPPDATA\Temp",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    foreach ($path in $paths) { Remove-PathSafe -Path $path }

    if ($PSCmdlet.ShouldProcess('Cestino', 'Svuotamento')) {
        try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Log 'Cestino svuotato.' 'OK' }
        catch { Write-Log "Cestino non svuotato: $($_.Exception.Message)" 'WARN' }
    }

    if (Get-Command cleanmgr.exe -ErrorAction SilentlyContinue) {
        Write-Log 'Avvio Pulizia disco Windows con impostazioni predefinite.'
        if ($PSCmdlet.ShouldProcess('cleanmgr.exe', 'Pulizia disco automatica')) {
            Start-Process cleanmgr.exe -ArgumentList '/verylowdisk' -Wait -WindowStyle Hidden
        }
    }
}

function Invoke-AppUpdates {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { Write-Log 'winget non trovato: aggiornamento app saltato.' 'WARN'; return }
    if ($PSCmdlet.ShouldProcess('winget', 'Aggiornamento di tutte le applicazioni disponibili')) {
        & $winget.Source update
        & $winget upgrade --all --include-unknown --accept-package-agreements --accept-source-agreements
    }
}

function Install-OrUpdateWingetPackage {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { return }
    Write-Log "Verifico utility driver online: $Name"
    if ($PSCmdlet.ShouldProcess($Name, 'Installazione/aggiornamento tramite winget')) {
        & $winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
        & $winget upgrade --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
    }
}

function Invoke-VendorDriverAssistants {
    $profile = Get-HardwareProfile
    $gpuNames = ($profile.Gpus | ForEach-Object { $_.Name }) -join ' '

    if ($gpuNames -match 'NVIDIA') {
        Install-OrUpdateWingetPackage -Id 'Nvidia.NVIDIAApp' -Name 'NVIDIA App'
        Write-Log 'NVIDIA rilevata: NVIDIA App consente il download automatico degli ultimi driver Game Ready/Studio.' 'OK'
    }
    if ($gpuNames -match 'AMD|Radeon') {
        Install-OrUpdateWingetPackage -Id 'AdvancedMicroDevices.AMDSoftware' -Name 'AMD Software: Adrenalin Edition'
        Write-Log 'AMD/Radeon rilevata: AMD Software gestisce gli ultimi driver GPU disponibili online.' 'OK'
    }
    if ($gpuNames -match 'Intel') {
        Install-OrUpdateWingetPackage -Id 'Intel.IntelDriverAndSupportAssistant' -Name 'Intel Driver & Support Assistant'
        Write-Log 'Intel rilevata: Intel Driver & Support Assistant verifica online driver chipset/grafica/rete supportati.' 'OK'
    }
}

function Invoke-WindowsAndDriverUpdates {
    param([switch]$IncludeDrivers)
    $moduleName = 'PSWindowsUpdate'
    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        Write-Log 'Modulo PSWindowsUpdate assente: provo installazione da PowerShell Gallery.'
        if ($PSCmdlet.ShouldProcess($moduleName, 'Installazione modulo')) {
            try {
                Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
                Install-Module $moduleName -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
            } catch {
                Write-Log "Modulo PSWindowsUpdate non installato: $($_.Exception.Message)" 'WARN'
                Write-Log 'Alternativa manuale: apri Impostazioni > Windows Update > Opzioni avanzate > Aggiornamenti facoltativi.' 'WARN'
                return
            }
        }
    }
    Import-Module $moduleName -ErrorAction SilentlyContinue
    if ($IncludeDrivers) {
        Write-Log 'Cerco online aggiornamenti Windows Update e driver Microsoft/OEM pubblicati su Microsoft Update.'
        if ($PSCmdlet.ShouldProcess('Windows Update', 'Installazione aggiornamenti inclusi driver')) {
            Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -IgnoreReboot -Category 'Drivers','Updates','Critical Updates','Security Updates'
        }
        if ($PSCmdlet.ShouldProcess('Dispositivi Plug and Play', 'Scansione nuove versioni driver installate')) {
            pnputil.exe /scan-devices
        }
        Invoke-VendorDriverAssistants
    } else {
        Write-Log 'Cerco aggiornamenti Windows Update di sicurezza/stabilità.'
        if ($PSCmdlet.ShouldProcess('Windows Update', 'Installazione aggiornamenti sicurezza/stabilità')) {
            Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -IgnoreReboot
        }
    }
}

function Invoke-SystemRepair {
    if ($PSCmdlet.ShouldProcess('Windows Image', 'DISM RestoreHealth')) {
        & DISM.exe /Online /Cleanup-Image /RestoreHealth
    }
    if ($PSCmdlet.ShouldProcess('File di sistema', 'SFC scannow')) {
        & sfc.exe /scannow
    }
}

function Invoke-Optimization {
    if ($PSCmdlet.ShouldProcess('Piano energia', 'Abilitazione piano prestazioni elevate se disponibile')) {
        try {
            $plans = powercfg /L
            $match = $plans | Select-String -Pattern '([a-f0-9-]{36}).*(Prestazioni elevate|High performance)' | Select-Object -First 1
            if ($match) { powercfg /S $match.Matches[0].Groups[1].Value; Write-Log 'Piano Prestazioni elevate attivato.' 'OK' }
            else { Write-Log 'Piano Prestazioni elevate non trovato: nessuna modifica.' 'WARN' }
        } catch { Write-Log "Piano energia non modificato: $($_.Exception.Message)" 'WARN' }
    }

    if ($PSCmdlet.ShouldProcess('Unità disco', 'Ottimizzazione/trim')) {
        try { Get-Volume | Where-Object DriveLetter | ForEach-Object { Optimize-Volume -DriveLetter $_.DriveLetter -Verbose -ErrorAction SilentlyContinue } }
        catch { Write-Log "Ottimizzazione unità parziale/non riuscita: $($_.Exception.Message)" 'WARN' }
    }

    if ($PSCmdlet.ShouldProcess('Servizio SysMain', 'Impostazione automatica per reattività sistema')) {
        try { Set-Service -Name SysMain -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service -Name SysMain -ErrorAction SilentlyContinue }
        catch { Write-Log "SysMain non modificato: $($_.Exception.Message)" 'WARN' }
    }
}

function Add-DisplayApi {
    if ('DisplayApi.NativeMethods' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace DisplayApi {
  public class NativeMethods {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
    public struct DEVMODE {
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
      public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
      public int dmFields; public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
      public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
      public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
      public int dmDisplayFlags; public int dmDisplayFrequency; public int dmICMMethod; public int dmICMIntent; public int dmMediaType;
      public int dmDitherType; public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
    public struct DISPLAY_DEVICE {
      public int cb;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
      public int StateFlags;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
    }
    [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
    [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
    [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);
  }
}
'@
}

function Set-BestDisplayModes {
    Add-DisplayApi
    $enumCurrentSettings = -1
    $ccsUpdateRegistry = 0x00000001
    $displayIndex = 0
    while ($true) {
        $device = New-Object DisplayApi.NativeMethods+DISPLAY_DEVICE
        $device.cb = [Runtime.InteropServices.Marshal]::SizeOf($device)
        if (-not [DisplayApi.NativeMethods]::EnumDisplayDevices($null, $displayIndex, [ref]$device, 0)) { break }
        if (($device.StateFlags -band 0x1) -eq 0) { $displayIndex++; continue }

        $best = $null
        $modeIndex = 0
        while ($true) {
            $mode = New-Object DisplayApi.NativeMethods+DEVMODE
            $mode.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($mode)
            if (-not [DisplayApi.NativeMethods]::EnumDisplaySettings($device.DeviceName, $modeIndex, [ref]$mode)) { break }
            if (-not $best -or ($mode.dmPelsWidth * $mode.dmPelsHeight) -gt ($best.dmPelsWidth * $best.dmPelsHeight) -or (($mode.dmPelsWidth * $mode.dmPelsHeight) -eq ($best.dmPelsWidth * $best.dmPelsHeight) -and $mode.dmDisplayFrequency -gt $best.dmDisplayFrequency)) {
                $best = $mode
            }
            $modeIndex++
        }

        if ($best) {
            Write-Log ('Display {0}: migliore modalità rilevata {1}x{2} @ {3}Hz, {4} bit.' -f $device.DeviceString, $best.dmPelsWidth, $best.dmPelsHeight, $best.dmDisplayFrequency, $best.dmBitsPerPel)
            if ($PSCmdlet.ShouldProcess($device.DeviceString, 'Applicazione migliore risoluzione/frequenza rilevata')) {
                $result = [DisplayApi.NativeMethods]::ChangeDisplaySettingsEx($device.DeviceName, [ref]$best, [IntPtr]::Zero, $ccsUpdateRegistry, [IntPtr]::Zero)
                if ($result -eq 0) { Write-Log ('Modalità display applicata a {0}.' -f $device.DeviceString) 'OK' }
                else { Write-Log ('Modalità display non applicata a {0}. Codice: {1}' -f $device.DeviceString, $result) 'WARN' }
            }
        }
        $displayIndex++
    }
    [DisplayApi.NativeMethods+DEVMODE]$current = New-Object DisplayApi.NativeMethods+DEVMODE
    $current.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($current)
    [void][DisplayApi.NativeMethods]::EnumDisplaySettings($null, $enumCurrentSettings, [ref]$current)
}

function Invoke-PerfectDisplay {
    Show-HardwareProfile
    Set-BestDisplayModes

    if ($PSCmdlet.ShouldProcess('ClearType', 'Abilitazione e ottimizzazione leggibilità testo')) {
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name FontSmoothing -Value '2' -ErrorAction SilentlyContinue
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name FontSmoothingType -Value 2 -ErrorAction SilentlyContinue
        Write-Log 'ClearType abilitato per migliorare la resa del testo.' 'OK'
    }

    if ($PSCmdlet.ShouldProcess('GPU Scheduling', 'Abilitazione pianificazione GPU con accelerazione hardware se supportata')) {
        New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -PropertyType DWord -Value 2 -Force | Out-Null
        Write-Log 'Hardware-accelerated GPU scheduling richiesto: richiede riavvio e hardware/driver compatibili.' 'OK'
    }

    Write-Log 'Perfect Display completato: per HDR/VRR/G-SYNC/FreeSync usa anche il pannello NVIDIA/AMD/Intel se presente.' 'WARN'
}

function Show-MainMenu {
    while ($true) {
        Write-Host ''
        Write-Host '========== ClearAndPowerPC - Menu ==========' -ForegroundColor Cyan
        Write-Host '1) Pulizia PC impeccabile e sicura'
        Write-Host '2) Riparazione stabilità Windows (DISM + SFC)'
        Write-Host '3) Aggiornamento applicazioni (winget)'
        Write-Host '4) Driver online automatici (Windows Update + utility NVIDIA/AMD/Intel)'
        Write-Host '5) Ottimizzazione potenza/prestazioni conservative'
        Write-Host '6) Perfect Display (schermo + GPU)'
        Write-Host '7) Esegui tutto'
        Write-Host '8) Mostra hardware rilevato'
        Write-Host '0) Esci'
        $choice = Read-Host 'Scegli cosa fare'
        switch ($choice) {
            '1' { Invoke-Step 'Pulizia file temporanei e cache' { Invoke-Cleaning } }
            '2' { Invoke-Step 'Riparazione immagine e file di sistema' { Invoke-SystemRepair } }
            '3' { Invoke-Step 'Aggiornamento applicazioni con winget' { Invoke-AppUpdates } }
            '4' { Invoke-Step 'Driver online automatici' { Invoke-WindowsAndDriverUpdates -IncludeDrivers } }
            '5' { Invoke-Step 'Configurazioni conservative di prestazioni' { Invoke-Optimization } }
            '6' { Invoke-Step 'Perfect Display' { Invoke-PerfectDisplay } }
            '7' { Invoke-AllTasks }
            '8' { Show-HardwareProfile }
            '0' { return }
            default { Write-Log 'Scelta non valida.' 'WARN' }
        }
    }
}

function Invoke-AllTasks {
    Invoke-Step 'Pulizia file temporanei e cache' { Invoke-Cleaning }
    Invoke-Step 'Riparazione immagine e file di sistema' { Invoke-SystemRepair }
    Invoke-Step 'Aggiornamento applicazioni con winget' { Invoke-AppUpdates }
    Invoke-Step 'Aggiornamenti Windows e driver online' { Invoke-WindowsAndDriverUpdates -IncludeDrivers }
    Invoke-Step 'Configurazioni conservative di prestazioni' { Invoke-Optimization }
    Invoke-Step 'Perfect Display' { Invoke-PerfectDisplay }
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
Write-Log 'ClearAndPowerPC avviato.'
if (-not (Test-IsAdmin)) { throw 'Esegui PowerShell come Amministratore.' }

$hasDirectAction = $All -or $Clean -or $UpdateApps -or $WindowsUpdate -or $Drivers -or $RepairSystem -or $Optimize -or $PerfectDisplay
if (-not $hasDirectAction) { $Menu = $true }

New-SafeRestorePoint
if ($Menu) { Show-MainMenu }
else {
    if ($All) { Invoke-AllTasks }
    else {
        if ($Clean) { Invoke-Step 'Pulizia file temporanei e cache' { Invoke-Cleaning } }
        if ($RepairSystem) { Invoke-Step 'Riparazione immagine e file di sistema' { Invoke-SystemRepair } }
        if ($UpdateApps) { Invoke-Step 'Aggiornamento applicazioni con winget' { Invoke-AppUpdates } }
        if ($WindowsUpdate -or $Drivers) { Invoke-Step 'Aggiornamenti Windows e driver' { Invoke-WindowsAndDriverUpdates -IncludeDrivers:$Drivers } }
        if ($Optimize) { Invoke-Step 'Configurazioni conservative di prestazioni' { Invoke-Optimization } }
        if ($PerfectDisplay) { Invoke-Step 'Perfect Display' { Invoke-PerfectDisplay } }
    }
}

Write-Log "Operazione terminata. Log: $LogFile" 'OK'
if (-not $NoReboot) { Write-Log 'Riavvia il PC per completare aggiornamenti, driver e impostazioni display se richiesto da Windows.' 'WARN' }
