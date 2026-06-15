<#
.SYNOPSIS
  ClearAndPowerPC - manutenzione Windows guidata da menu.

.DESCRIPTION
  Pulisce file temporanei/cache, ripara Windows, aggiorna app, cerca online driver
  tramite Windows Update/Microsoft Update e strumenti vendor affidabili, analizza
  eventi critici/errori, monitora salute/prestazioni PC, controlla processi/elementi sospetti e applica impostazioni
  display conservative per massima risoluzione/frequenza disponibile.

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
    [switch]$EventAnalysis,
    [switch]$HealthMonitor,
    [switch]$SecurityScan,
    [switch]$CreateRestorePoint = $true,
    [switch]$SkipRestorePoint,
    [switch]$NoReboot,
    [switch]$SkipDefenderScan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$LogRoot = Join-Path $env:ProgramData 'ClearAndPowerPC'
$RunStamp = '{0:yyyyMMdd-HHmmss}' -f (Get-Date)
$LogFile = Join-Path $LogRoot ("run-$RunStamp.log")
$TranscriptFile = Join-Path $LogRoot ("transcript-$RunStamp.log")

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


function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory=$true)][string]$Label,
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @()
    )
    $commandLine = if ($Arguments.Count) { "$FilePath $($Arguments -join ' ')" } else { $FilePath }
    Write-Log "Comando avviato [$Label]: $commandLine"
    $start = Get-Date
    try {
        & $FilePath @Arguments 2>&1 | ForEach-Object { Write-Log "[$Label] $_" }
        $exitCode = if ($null -ne $global:LASTEXITCODE) { $global:LASTEXITCODE } else { 0 }
        Write-Log ("Comando terminato [$Label] in {0:N1} minuti. ExitCode: {1}" -f ((Get-Date) - $start).TotalMinutes, $exitCode) 'OK'
        return $exitCode
    } catch {
        Write-Log "Errore comando [$Label]: $($_.Exception.Message)" 'ERROR'
        return 1
    }
}

function Write-OperationDetail {
    param([Parameter(Mandatory=$true)][string]$Message)
    Write-Log "  -> $Message"
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
            $item = $_
            $psPathProperty = $item.PSObject.Properties['PSPath']
            $fullNameProperty = $item.PSObject.Properties['FullName']
            $nameProperty = $item.PSObject.Properties['Name']
            $itemPath = if ($psPathProperty) { [string]$psPathProperty.Value } elseif ($fullNameProperty) { [string]$fullNameProperty.Value } else { [string]$item }
            $itemName = if ($nameProperty) { [string]$nameProperty.Value } elseif ($fullNameProperty) { Split-Path -Leaf ([string]$fullNameProperty.Value) } else { [string]$item }
            try { Remove-Item -LiteralPath $itemPath -Recurse -Force -ErrorAction Stop }
            catch { Write-Log "Non rimosso: $itemName ($itemPath) - $($_.Exception.Message)" 'WARN' }
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

    foreach ($path in $paths) { Write-OperationDetail "Pulizia percorso: $path"; Remove-PathSafe -Path $path }

    if ($PSCmdlet.ShouldProcess('Cestino', 'Svuotamento')) {
        try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Log 'Cestino svuotato.' 'OK' }
        catch { Write-Log "Cestino non svuotato: $($_.Exception.Message)" 'WARN' }
    }

    if (Get-Command cleanmgr.exe -ErrorAction SilentlyContinue) {
        Write-Log 'Avvio Pulizia disco Windows con impostazioni predefinite.'
        if ($PSCmdlet.ShouldProcess('cleanmgr.exe', 'Pulizia disco automatica')) {
            Invoke-LoggedCommand -Label 'Pulizia disco' -FilePath 'cleanmgr.exe' -Arguments @('/verylowdisk') | Out-Null
        }
    }
}

function Invoke-AppUpdates {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { Write-Log 'winget non trovato: aggiornamento app saltato.' 'WARN'; return }
    if ($PSCmdlet.ShouldProcess('winget', 'Aggiornamento di tutte le applicazioni disponibili')) {
        Invoke-LoggedCommand -Label 'winget source update' -FilePath $winget.Source -Arguments @('source','update') | Out-Null
        Invoke-LoggedCommand -Label 'winget upgrade all' -FilePath $winget.Source -Arguments @('upgrade','--all','--include-unknown','--accept-package-agreements','--accept-source-agreements') | Out-Null
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
        Invoke-LoggedCommand -Label "winget install $Name" -FilePath $winget.Source -Arguments @('install','--id',$Id,'--exact','--silent','--accept-package-agreements','--accept-source-agreements') | Out-Null
        Invoke-LoggedCommand -Label "winget upgrade $Name" -FilePath $winget.Source -Arguments @('upgrade','--id',$Id,'--exact','--silent','--accept-package-agreements','--accept-source-agreements') | Out-Null
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
                Write-OperationDetail 'Imposto PSGallery come repository attendibile se necessario.'
                Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
                Write-OperationDetail 'Installo modulo PSWindowsUpdate per interrogare Windows Update da PowerShell.'
                Install-Module $moduleName -Force -Scope CurrentUser -AllowClobber -Verbose -ErrorAction Stop 4>&1 | ForEach-Object { Write-Log "[Install-Module] $_" }
            } catch {
                Write-Log "Modulo PSWindowsUpdate non installato: $($_.Exception.Message)" 'WARN'
                Write-Log 'Alternativa manuale: apri Impostazioni > Windows Update > Opzioni avanzate > Aggiornamenti facoltativi.' 'WARN'
                return
            }
        }
    }
    Write-OperationDetail 'Importo modulo PSWindowsUpdate.'
    Import-Module $moduleName -Verbose -ErrorAction SilentlyContinue 4>&1 | ForEach-Object { Write-Log "[Import-Module] $_" }
    if ($IncludeDrivers) {
        Write-Log 'Cerco online aggiornamenti Windows Update e driver Microsoft/OEM pubblicati su Microsoft Update.'
        if ($PSCmdlet.ShouldProcess('Windows Update', 'Installazione aggiornamenti inclusi driver')) {
            Write-OperationDetail 'Fase 1/3: ricerca online aggiornamenti e driver. Può sembrare fermo per diversi minuti.'
            Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -IgnoreReboot -Category 'Drivers','Updates','Critical Updates','Security Updates' -Verbose 4>&1 | ForEach-Object { Write-Log "[Windows Update] $_" }
            Write-OperationDetail 'Fase 2/3: scansione dispositivi Plug and Play dopo aggiornamenti driver.'
        }
        if ($PSCmdlet.ShouldProcess('Dispositivi Plug and Play', 'Scansione nuove versioni driver installate')) {
            Invoke-LoggedCommand -Label 'pnputil scan-devices' -FilePath 'pnputil.exe' -Arguments @('/scan-devices') | Out-Null
        }
        Write-OperationDetail 'Fase 3/3: verifica utility ufficiali NVIDIA/AMD/Intel se applicabili.'
        Invoke-VendorDriverAssistants
    } else {
        Write-Log 'Cerco aggiornamenti Windows Update di sicurezza/stabilità.'
        if ($PSCmdlet.ShouldProcess('Windows Update', 'Installazione aggiornamenti sicurezza/stabilità')) {
            Write-OperationDetail 'Ricerca online aggiornamenti Windows. Può richiedere diversi minuti senza percentuale visibile.'
            Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -IgnoreReboot -Verbose 4>&1 | ForEach-Object { Write-Log "[Windows Update] $_" }
        }
    }
}

function Invoke-SystemRepair {
    Write-Log 'DISM può sembrare fermo per diversi minuti (spesso intorno al 62-64%): è normale mentre verifica component store e payload.' 'WARN'
    if ($PSCmdlet.ShouldProcess('Windows Image', 'DISM RestoreHealth')) {
        $dismStart = Get-Date
        Write-Log 'Avvio DISM /Online /Cleanup-Image /RestoreHealth. Non chiudere la finestra se la percentuale resta ferma.'
        Invoke-LoggedCommand -Label 'DISM RestoreHealth' -FilePath 'DISM.exe' -Arguments @('/Online','/Cleanup-Image','/RestoreHealth') | Out-Null
        Write-Log ("DISM terminato in {0:N1} minuti." -f ((Get-Date) - $dismStart).TotalMinutes) 'OK'
    }
    if ($PSCmdlet.ShouldProcess('File di sistema', 'SFC scannow')) {
        $sfcStart = Get-Date
        Write-Log 'Avvio SFC /scannow dopo DISM.'
        Invoke-LoggedCommand -Label 'SFC scannow' -FilePath 'sfc.exe' -Arguments @('/scannow') | Out-Null
        Write-Log ("SFC terminato in {0:N1} minuti." -f ((Get-Date) - $sfcStart).TotalMinutes) 'OK'
    }
}

function Get-RecentProblemEvents {
    param([int]$Days = 7, [int]$MaxEvents = 120)
    $start = (Get-Date).AddDays(-$Days)
    $logs = @('System','Application')
    foreach ($log in $logs) {
        try {
            Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 1,2; StartTime = $start } -MaxEvents $MaxEvents -ErrorAction Stop |
                Select-Object TimeCreated, LogName, ProviderName, Id, LevelDisplayName, Message
        } catch {
            Write-Log "Impossibile leggere registro eventi ${log}: $($_.Exception.Message)" 'WARN'
        }
    }
}

function Invoke-EventAnalysis {
    Write-Log 'Analizzo eventi critici/errori degli ultimi 7 giorni in System e Application.'
    $events = @(Get-RecentProblemEvents -Days 7 -MaxEvents 150)
    if (-not $events -or $events.Count -eq 0) {
        Write-Log 'Nessun errore critico recente trovato nei registri principali.' 'OK'
        return
    }

    $summary = $events | Group-Object LogName, ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 12
    Write-Log 'Eventi più ricorrenti rilevati:'
    foreach ($item in $summary) { Write-Log (' - {0} occorrenze | {1}' -f $item.Count, $item.Name) }

    $providerText = ($events.ProviderName -join ' ')
    $messageText = ($events.Message -join ' ')

    if ($providerText -match 'WindowsUpdateClient|Servicing|CBS' -or $messageText -match 'Windows Update|0x800') {
        Write-Log 'Trovati errori Windows Update/servicing: applico riparazione component store e ricerca aggiornamenti.' 'WARN'
        Invoke-SystemRepair
        Invoke-WindowsAndDriverUpdates
    }

    if ($providerText -match 'Disk|Ntfs|storahci|stornvme' -or $messageText -match 'bad block|file system|disk|ntfs') {
        Write-Log 'Trovati possibili errori disco/file system: avvio controlli conservativi.' 'WARN'
        if ($PSCmdlet.ShouldProcess('Disco di sistema', 'chkdsk /scan')) { Invoke-LoggedCommand -Label 'chkdsk scan' -FilePath 'chkdsk.exe' -Arguments @($env:SystemDrive, '/scan') | Out-Null }
        if ($PSCmdlet.ShouldProcess('Volumi', 'Optimize-Volume dopo errori disco')) {
            Get-Volume | Where-Object DriveLetter | ForEach-Object { Optimize-Volume -DriveLetter $_.DriveLetter -Verbose -ErrorAction SilentlyContinue }
        }
    }

    if ($providerText -match 'Service Control Manager') {
        Write-Log 'Trovati errori Service Control Manager: provo a riavviare servizi Windows essenziali se presenti.' 'WARN'
        foreach ($serviceName in @('wuauserv','bits','cryptsvc','Winmgmt')) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service -and $PSCmdlet.ShouldProcess($serviceName, 'Riavvio servizio')) {
                try { Restart-Service -Name $serviceName -Force -ErrorAction Stop; Write-Log "Servizio riavviato: $serviceName" 'OK' }
                catch { Write-Log "Servizio non riavviato ${serviceName}: $($_.Exception.Message)" 'WARN' }
            }
        }
    }

    if ($providerText -match 'Display|nvlddmkm|amdkmdag|igfx|igfxn') {
        Write-Log 'Trovati errori grafici/display: avvio aggiornamento driver e Perfect Display.' 'WARN'
        Invoke-WindowsAndDriverUpdates -IncludeDrivers
        Invoke-PerfectDisplay
    }

    Write-Log 'Analisi eventi completata. Controlla il log per gli eventi ricorrenti e le correzioni applicate.' 'OK'
}

function Get-HealthPercent {
    param(
        [double]$CpuLoad,
        [double]$MemoryUsedPercent,
        [double]$SystemDiskUsedPercent,
        [int]$CriticalErrorCount,
        [int]$DiskProblems
    )
    $score = 100
    $score -= [math]::Min(30, [math]::Max(0, ($CpuLoad - 40) * 0.5))
    $score -= [math]::Min(25, [math]::Max(0, ($MemoryUsedPercent - 60) * 0.6))
    $score -= [math]::Min(20, [math]::Max(0, ($SystemDiskUsedPercent - 75) * 0.8))
    $score -= [math]::Min(15, $CriticalErrorCount * 2)
    $score -= [math]::Min(20, $DiskProblems * 10)
    return [math]::Max(0, [math]::Min(100, [math]::Round($score)))
}

function Show-HealthMonitor {
    Write-Log 'Raccolgo stato salute PC e prestazioni correnti.'
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    $systemDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue
    $physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    $events = @(Get-RecentProblemEvents -Days 1 -MaxEvents 80)

    $cpuLoad = if ($cpu) { [double]$cpu.LoadPercentage } else { 0 }
    $totalMem = if ($os) { [double]$os.TotalVisibleMemorySize } else { 1 }
    $freeMem = if ($os) { [double]$os.FreePhysicalMemory } else { 0 }
    $memoryUsedPercent = [math]::Round((($totalMem - $freeMem) / $totalMem) * 100, 1)
    $diskUsedPercent = if ($systemDrive -and $systemDrive.Size -gt 0) { [math]::Round((($systemDrive.Size - $systemDrive.FreeSpace) / $systemDrive.Size) * 100, 1) } else { 0 }
    $diskProblems = @($physicalDisks | Where-Object { $_.HealthStatus -ne 'Healthy' -or $_.OperationalStatus -notcontains 'OK' }).Count
    $criticalErrors = @($events | Where-Object { $_.LevelDisplayName -eq 'Critical' -or $_.LevelDisplayName -eq 'Error' }).Count
    $score = Get-HealthPercent -CpuLoad $cpuLoad -MemoryUsedPercent $memoryUsedPercent -SystemDiskUsedPercent $diskUsedPercent -CriticalErrorCount $criticalErrors -DiskProblems $diskProblems

    Write-Host ''
    Write-Host '========== Monitor Salute PC ==========' -ForegroundColor Cyan
    $scoreColor = if ($score -ge 85) { 'Green' } elseif ($score -ge 65) { 'Yellow' } else { 'Red' }
    Write-Host ("Salute/prestazioni stimate: {0}%" -f $score) -ForegroundColor $scoreColor
    $cpuName = if ($cpu) { $cpu.Name } else { 'CPU non rilevata' }
    Write-Host ("CPU: {0} | Carico attuale: {1}%" -f $cpuName, $cpuLoad)
    Write-Host ("RAM usata: {0}% | Libera: {1:N1} GB / Totale: {2:N1} GB" -f $memoryUsedPercent, ($freeMem / 1MB), ($totalMem / 1MB))
    if ($systemDrive) { Write-Host ("Disco sistema {0}: usato {1}% | libero {2:N1} GB / totale {3:N1} GB" -f $env:SystemDrive, $diskUsedPercent, ($systemDrive.FreeSpace / 1GB), ($systemDrive.Size / 1GB)) }
    foreach ($disk in $physicalDisks) { Write-Host ("Disco fisico: {0} | Salute: {1} | Stato: {2} | Tipo: {3}" -f $disk.FriendlyName, $disk.HealthStatus, ($disk.OperationalStatus -join ','), $disk.MediaType) }
    foreach ($item in $gpu) { Write-Host ("GPU: {0} | Driver: {1}" -f $item.Name, $item.DriverVersion) }
    if ($battery) { foreach ($b in $battery) { Write-Host ("Batteria: {0}% | Stato: {1}" -f $b.EstimatedChargeRemaining, $b.BatteryStatus) } }
    Write-Host ("Eventi critici/errori ultime 24h: {0}" -f $criticalErrors)

    if ($score -lt 85) {
        Write-Log 'Suggerimenti automatici: esegui Analisi Eventi, Pulizia, Riparazione Windows e Driver online dal menu.' 'WARN'
    } else {
        Write-Log 'Stato generale buono secondo le metriche disponibili.' 'OK'
    }
}


function Get-ProcessExecutablePath {
    param([Parameter(Mandatory=$true)]$Process)
    try {
        return (Get-CimInstance Win32_Process -Filter "ProcessId=$($Process.Id)" -ErrorAction Stop).ExecutablePath
    } catch {
        return $null
    }
}

function Test-IsSuspiciousPath {
    param([string]$Path)
    if (-not $Path) { return $true }
    $normalized = $Path.ToLowerInvariant()
    $suspiciousRoots = @(
        $env:TEMP,
        $env:TMP,
        "$env:LOCALAPPDATA\Temp",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
        "$env:PUBLIC",
        "$env:USERPROFILE\Downloads"
    ) | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() }
    foreach ($root in $suspiciousRoots) {
        if ($normalized.StartsWith($root)) { return $true }
    }
    return $false
}

function Get-SignatureStatus {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 'Percorso non disponibile' }
    try { return (Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop).Status.ToString() }
    catch { return 'Firma non verificabile' }
}

function Invoke-SecurityScan {
    Write-Log 'Controllo processi attivi, percorsi sospetti, firme digitali, startup e attività pianificate.'
    $processFindings = @()
    $processes = Get-Process -ErrorAction SilentlyContinue | Sort-Object CPU -Descending
    foreach ($process in $processes) {
        $path = Get-ProcessExecutablePath -Process $process
        $signature = Get-SignatureStatus -Path $path
        $isPathSuspicious = Test-IsSuspiciousPath -Path $path
        $highCpu = ($process.CPU -and $process.CPU -gt 300)
        $highMemory = ($process.WorkingSet64 -gt 750MB)
        $unsigned = $signature -ne 'Valid'
        if ($isPathSuspicious -or $unsigned -or $highCpu -or $highMemory) {
            $processFindings += [pscustomobject]@{
                Name = $process.ProcessName
                Id = $process.Id
                Path = if ($path) { $path } else { 'N/D' }
                Signature = $signature
                CpuSeconds = [math]::Round([double]($process.CPU), 1)
                MemoryMB = [math]::Round($process.WorkingSet64 / 1MB, 1)
                Reason = (@(
                    if ($isPathSuspicious) { 'percorso insolito/non disponibile' }
                    if ($unsigned) { 'firma non valida/non verificabile/non firmata' }
                    if ($highCpu) { 'CPU elevata' }
                    if ($highMemory) { 'RAM elevata' }
                ) -join ', ')
            }
        }
    }

    if ($processFindings.Count -eq 0) {
        Write-Log 'Nessun processo attivo sospetto rilevato dai controlli euristici.' 'OK'
    } else {
        Write-Log 'Processi da verificare rilevati:' 'WARN'
        foreach ($finding in ($processFindings | Select-Object -First 20)) {
            Write-Log (' - {0} PID {1} | {2} MB | CPU {3}s | Firma {4} | {5} | {6}' -f $finding.Name, $finding.Id, $finding.MemoryMB, $finding.CpuSeconds, $finding.Signature, $finding.Reason, $finding.Path) 'WARN'
        }
    }

    $startupFindings = @()
    $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($key in $runKeys) {
        if (Test-Path $key) {
            $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            foreach ($prop in $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }) {
                $value = [string]$prop.Value
                if ($value -match '\\Temp\\|AppData\\Roaming|Downloads|powershell|wscript|cscript|cmd\.exe|rundll32') {
                    $startupFindings += [pscustomobject]@{ Source = $key; Name = $prop.Name; Command = $value }
                }
            }
        }
    }

    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        ($_.TaskPath -notlike '\Microsoft\*') -and (($_.Actions.Execute -match 'powershell|wscript|cscript|cmd\.exe|rundll32') -or ($_.Actions.Arguments -match 'AppData|Temp|Downloads|http'))
    }

    if ($startupFindings.Count -or $tasks.Count) {
        Write-Log 'Elementi di avvio/attività pianificate da verificare:' 'WARN'
        foreach ($item in $startupFindings) { Write-Log (' - Startup {0}\{1}: {2}' -f $item.Source, $item.Name, $item.Command) 'WARN' }
        foreach ($task in $tasks) { Write-Log (' - Task {0}{1}: {2} {3}' -f $task.TaskPath, $task.TaskName, $task.Actions.Execute, $task.Actions.Arguments) 'WARN' }
    } else {
        Write-Log 'Nessun elemento sospetto evidente in Run keys e attività pianificate non Microsoft.' 'OK'
    }

    if ($SkipDefenderScan) {
        Write-Log 'Scansione Defender saltata: controllo sicurezza avviato in modalità parallela/read-only.' 'WARN'
    } elseif (Get-Command Start-MpScan -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess('Microsoft Defender', 'Avvio scansione rapida antivirus')) {
            try { Start-MpScan -ScanType QuickScan; Write-Log 'Scansione rapida Microsoft Defender avviata.' 'OK' }
            catch { Write-Log "Scansione Defender non avviata: $($_.Exception.Message)" 'WARN' }
        }
    } else {
        Write-Log 'Microsoft Defender PowerShell non disponibile: scansione antivirus automatica saltata.' 'WARN'
    }

    Write-Log 'Controllo sicurezza completato: gli elementi segnalati sono sospetti euristici, non una diagnosi malware certa.' 'WARN'
}

function Invoke-Optimization {
    if ($PSCmdlet.ShouldProcess('Piano energia', 'Abilitazione piano prestazioni elevate se disponibile')) {
        try {
            $plans = powercfg /L
            $match = $plans | Select-String -Pattern '([a-f0-9-]{36}).*(Prestazioni elevate|High performance)' | Select-Object -First 1
            if ($match) { Invoke-LoggedCommand -Label 'powercfg set high performance' -FilePath 'powercfg.exe' -Arguments @('/S', $match.Matches[0].Groups[1].Value) | Out-Null; Write-Log 'Piano Prestazioni elevate attivato.' 'OK' }
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
        $graphicsDriversKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
        try {
            if (-not (Test-Path -LiteralPath $graphicsDriversKey)) {
                New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'GraphicsDrivers' -ErrorAction Stop | Out-Null
            }
            $hwSchProperty = Get-ItemProperty -LiteralPath $graphicsDriversKey -Name HwSchMode -ErrorAction SilentlyContinue
            if ($hwSchProperty) {
                Set-ItemProperty -LiteralPath $graphicsDriversKey -Name HwSchMode -Value 2 -ErrorAction Stop
            } else {
                New-ItemProperty -LiteralPath $graphicsDriversKey -Name HwSchMode -PropertyType DWord -Value 2 -ErrorAction Stop | Out-Null
            }
            Write-Log 'Hardware-accelerated GPU scheduling richiesto: richiede riavvio e hardware/driver compatibili.' 'OK'
        } catch {
            Write-Log "GPU Scheduling non modificato: $($_.Exception.Message)" 'WARN'
        }
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
        Write-Host '7) Analisi eventi e correzioni automatiche'
        Write-Host '8) Monitor salute PC e prestazioni'
        Write-Host '9) Controllo processi ed elementi sospetti'
        Write-Host '10) Esegui tutto'
        Write-Host '11) Mostra hardware rilevato'
        Write-Host '0) Esci'
        $choice = Read-Host 'Scegli cosa fare'
        switch ($choice) {
            '1' { Invoke-Step 'Pulizia file temporanei e cache' { Invoke-Cleaning } }
            '2' { Invoke-Step 'Riparazione immagine e file di sistema' { Invoke-SystemRepair } }
            '3' { Invoke-Step 'Aggiornamento applicazioni con winget' { Invoke-AppUpdates } }
            '4' { Invoke-Step 'Driver online automatici' { Invoke-WindowsAndDriverUpdates -IncludeDrivers } }
            '5' { Invoke-Step 'Configurazioni conservative di prestazioni' { Invoke-Optimization } }
            '6' { Invoke-Step 'Perfect Display' { Invoke-PerfectDisplay } }
            '7' { Invoke-Step 'Analisi eventi e correzioni automatiche' { Invoke-EventAnalysis } }
            '8' { Invoke-Step 'Monitor salute PC e prestazioni' { Show-HealthMonitor } }
            '9' { Invoke-Step 'Controllo processi ed elementi sospetti' { Invoke-SecurityScan } }
            '10' { Invoke-AllTasks }
            '11' { Show-HardwareProfile }
            '0' { return }
            default { Write-Log 'Scelta non valida.' 'WARN' }
        }
    }
}

function Start-ReadOnlyParallelTask {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string[]]$Arguments
    )
    if (-not $PSCommandPath) { Write-Log "Task parallelo $Name non avviato: percorso script non disponibile." 'WARN'; return $null }
    try {
        Write-Log "Avvio task parallelo read-only: $Name"
        return Start-Job -Name $Name -ScriptBlock {
            param($ScriptPath, $TaskArguments)
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @TaskArguments
        } -ArgumentList $PSCommandPath, $Arguments
    } catch {
        Write-Log "Task parallelo $Name non avviato: $($_.Exception.Message)" 'WARN'
        return $null
    }
}

function Wait-ReadOnlyParallelTasks {
    param([object[]]$Jobs)
    foreach ($job in ($Jobs | Where-Object { $_ })) {
        try {
            Write-Log "Attendo completamento task parallelo: $($job.Name)"
            Wait-Job -Job $job | Out-Null
            Receive-Job -Job $job | ForEach-Object { Write-Log "[$($job.Name)] $_" }
            Remove-Job -Job $job -Force
        } catch {
            Write-Log "Errore task parallelo $($job.Name): $($_.Exception.Message)" 'WARN'
        }
    }
}

function Invoke-AllTasks {
    $parallelJobs = @(
        Start-ReadOnlyParallelTask -Name 'MonitorSalute' -Arguments @('-HealthMonitor','-SkipRestorePoint','-NoReboot'),
        Start-ReadOnlyParallelTask -Name 'ControlloSicurezzaReadOnly' -Arguments @('-SecurityScan','-SkipDefenderScan','-SkipRestorePoint','-NoReboot')
    )
    Invoke-Step 'Pulizia file temporanei e cache' { Invoke-Cleaning }
    Invoke-Step 'Riparazione immagine e file di sistema' { Invoke-SystemRepair }
    Invoke-Step 'Aggiornamento applicazioni con winget' { Invoke-AppUpdates }
    Invoke-Step 'Aggiornamenti Windows e driver online' { Invoke-WindowsAndDriverUpdates -IncludeDrivers }
    Invoke-Step 'Configurazioni conservative di prestazioni' { Invoke-Optimization }
    Invoke-Step 'Perfect Display' { Invoke-PerfectDisplay }
    Invoke-Step 'Analisi eventi e correzioni automatiche' { Invoke-EventAnalysis }
    Wait-ReadOnlyParallelTasks -Jobs $parallelJobs
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
try { Start-Transcript -Path $TranscriptFile -Append -ErrorAction Stop | Out-Null } catch { }
Write-Log 'ClearAndPowerPC avviato.'
Write-Log "Log dettagliato: $LogFile"
Write-Log "Transcript PowerShell: $TranscriptFile"
if (-not (Test-IsAdmin)) { throw 'Esegui PowerShell come Amministratore.' }

$hasDirectAction = $All -or $Clean -or $UpdateApps -or $WindowsUpdate -or $Drivers -or $RepairSystem -or $Optimize -or $PerfectDisplay -or $EventAnalysis -or $HealthMonitor -or $SecurityScan
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
        if ($EventAnalysis) { Invoke-Step 'Analisi eventi e correzioni automatiche' { Invoke-EventAnalysis } }
        if ($HealthMonitor) { Invoke-Step 'Monitor salute PC e prestazioni' { Show-HealthMonitor } }
        if ($SecurityScan) { Invoke-Step 'Controllo processi ed elementi sospetti' { Invoke-SecurityScan } }
    }
}

Write-Log "Operazione terminata. Log: $LogFile" 'OK'
try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
if (-not $NoReboot) { Write-Log 'Riavvia il PC per completare aggiornamenti, driver e impostazioni display se richiesto da Windows.' 'WARN' }
