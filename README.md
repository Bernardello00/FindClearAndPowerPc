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
7. Analisi eventi Windows e correzioni automatiche conservative.
8. Monitor salute PC con percentuale prestazioni e info utili.
9. Controllo processi attivi ed elementi sospetti.
10. Esecuzione completa di tutte le operazioni.
11. Report hardware rilevato.

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
.\ClearAndPowerPC.ps1 -EventAnalysis
.\ClearAndPowerPC.ps1 -HealthMonitor
.\ClearAndPowerPC.ps1 -SecurityScan
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
- Analizza eventi critici/errori recenti in `System` e `Application`, raggruppa le cause ricorrenti e applica correzioni conservative per Windows Update, disco/file system, servizi essenziali e driver/display quando il tipo di errore lo suggerisce.
- Mostra un monitor salute PC con percentuale stimata di prestazioni/salute, carico CPU, uso RAM, spazio disco, stato dischi fisici, driver GPU, batteria ed eventi critici/errori delle ultime 24 ore.
- Controlla processi attivi, percorsi insoliti, firme digitali, elementi di avvio, attività pianificate non Microsoft e avvia una scansione rapida Microsoft Defender quando disponibile.

## Note importanti sui driver e Perfect Display

Lo script usa canali affidabili e automatizzabili: Windows Update/Microsoft Update, `winget` e utility ufficiali NVIDIA/AMD/Intel. Non scarica driver da siti casuali o database non verificati, perché questo può rendere instabile il PC.

Perfect Display applica impostazioni conservative basate sulle modalità dichiarate da Windows, monitor e driver video. HDR, VRR, G-SYNC, FreeSync e profili colore professionali possono richiedere conferma manuale nei pannelli NVIDIA/AMD/Intel o nelle impostazioni Windows, perché dipendono da cavo, porta, monitor e driver installati.


## Analisi eventi e monitor salute

La voce **Analisi eventi** legge gli errori e gli eventi critici recenti dai registri Windows principali e prova solo correzioni conservative: `DISM`/`SFC`, Windows Update, `chkdsk /scan`, ottimizzazione volumi, riavvio di servizi essenziali e aggiornamento driver/display se sono presenti errori grafici.

La voce **Monitor salute PC** calcola una percentuale indicativa combinando CPU, RAM, spazio disco, stato dei dischi fisici ed eventi recenti. Il valore è una stima pratica per capire rapidamente se il PC è in buone condizioni o se conviene eseguire pulizia, riparazione, driver o analisi eventi.


## Controllo processi ed elementi sospetti

La voce **Controllo processi ed elementi sospetti** non cancella file automaticamente: segnala processi con percorso insolito o non disponibile, firma digitale non valida/non verificabile, uso elevato di CPU/RAM, chiavi di avvio sospette e attività pianificate non Microsoft che richiamano shell/script o percorsi rischiosi. Se Microsoft Defender è disponibile, avvia anche una scansione rapida.

Gli elementi segnalati sono indicatori euristici: vanno verificati prima di terminare processi o rimuovere file, perché anche strumenti legittimi possono risultare non firmati o usare molta memoria.


## Log dettagliati

Ogni esecuzione crea due file in `%ProgramData%\ClearAndPowerPC`: un log sintetico `run-*.log` e un transcript PowerShell `transcript-*.log`. Le operazioni lunghe, come Windows Update, DISM, SFC, winget, pnputil, chkdsk e Pulizia disco, ora scrivono messaggi passo-passo così puoi capire se il programma sta cercando online, installando, scansionando dispositivi o aspettando un comando Windows.

## Nota su riparazione stabilità e multithread

Durante `DISM /Online /Cleanup-Image /RestoreHealth` è normale che la percentuale sembri bloccata per diversi minuti, spesso intorno al 62-64%. Lo script ora lo segnala nel log e misura il tempo di esecuzione di DISM e SFC.

Quando scegli **Esegui tutto**, le attività invasive o potenzialmente concorrenti restano sequenziali per evitare conflitti su Windows Update, DISM/SFC, driver e disco. Le attività di sola lettura/non concorrenti, come monitor salute e controllo sicurezza senza scansione Defender, vengono invece avviate in job paralleli e raccolte a fine esecuzione.
