# FindClearAndPowerPc

Programma PowerShell completo per manutenzione Windows: pulizia sicura, riparazione del sistema,
aggiornamento applicazioni, ricerca online dei driver, ottimizzazioni conservative e sezione
**Perfect Display** per applicare la migliore modalità schermo/GPU rilevabile dal sistema.

## Avvio rapido con menu

Apri **PowerShell come Amministratore** nella cartella del progetto ed esegui:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\ClearAndPowerPC.ps1 -Menu
```

Se lo script viene avviato senza opzioni, apre automaticamente lo stesso menu interattivo.

## Menu disponibile

1. Pulizia PC impeccabile e sicura.
2. Riparazione stabilità Windows con `DISM` e `SFC`.
3. Aggiornamento applicazioni tramite `winget`.
4. Driver online automatici tramite Windows Update/Microsoft Update e utility NVIDIA/AMD/Intel quando rilevate.
5. Ottimizzazione potenza/prestazioni conservative.
6. **Perfect Display** per schermo e scheda video.
7. Esecuzione completa di tutte le operazioni.
8. Report hardware rilevato.

## Esecuzione diretta senza menu

```powershell
.\ClearAndPowerPC.ps1 -All
.\ClearAndPowerPC.ps1 -Clean
.\ClearAndPowerPC.ps1 -UpdateApps
.\ClearAndPowerPC.ps1 -WindowsUpdate
.\ClearAndPowerPC.ps1 -Drivers
.\ClearAndPowerPC.ps1 -RepairSystem
.\ClearAndPowerPC.ps1 -Optimize
.\ClearAndPowerPC.ps1 -PerfectDisplay
.\ClearAndPowerPC.ps1 -All -NoReboot
.\ClearAndPowerPC.ps1 -All -SkipRestorePoint
```

Per vedere cosa farebbe senza applicare modifiche:

```powershell
.\ClearAndPowerPC.ps1 -All -WhatIf
```

## Cosa fa

- Crea un punto di ripristino prima delle modifiche, quando Windows lo consente.
- Elimina file temporanei, cache comuni e svuota il cestino.
- Esegue `DISM /RestoreHealth` e `sfc /scannow` per stabilità e integrità.
- Aggiorna le applicazioni installate tramite `winget`.
- Cerca online driver importanti usando Microsoft Update/Windows Update.
- Installa o aggiorna utility driver affidabili in base alla GPU rilevata:
  - NVIDIA App per schede NVIDIA.
  - AMD Software: Adrenalin Edition per schede AMD/Radeon.
  - Intel Driver & Support Assistant per hardware Intel supportato.
- Esegue una scansione Plug and Play con `pnputil /scan-devices` dopo gli update driver.
- Attiva il piano energia “Prestazioni elevate” se già disponibile.
- Esegue ottimizzazione/trim dei volumi con gli strumenti integrati di Windows.
- Applica Perfect Display scegliendo la risoluzione e frequenza più alte esposte dal monitor/driver, abilita ClearType e richiede Hardware Accelerated GPU Scheduling quando supportato.

## Note importanti sui driver e Perfect Display

Lo script usa canali affidabili e automatizzabili: Windows Update/Microsoft Update, `winget` e utility ufficiali NVIDIA/AMD/Intel. Non scarica driver da siti casuali o database non verificati, perché questo può rendere instabile il PC.

Perfect Display applica impostazioni conservative basate sulle modalità dichiarate da Windows, monitor e driver video. HDR, VRR, G-SYNC, FreeSync e profili colore professionali possono richiedere conferma manuale nei pannelli NVIDIA/AMD/Intel o nelle impostazioni Windows, perché dipendono da cavo, porta, monitor e driver installati.
