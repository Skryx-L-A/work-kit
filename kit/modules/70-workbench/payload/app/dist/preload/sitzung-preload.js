"use strict";

// src/preload/sitzung-preload.ts
var import_electron = require("electron");
import_electron.contextBridge.exposeInMainWorld("awbSitzung", {
  daten: () => import_electron.ipcRenderer.invoke("awb:sitz-daten"),
  // Die Echtheit kommt aus `isTrusted` im Fenster und wird im Hauptprozess
  // entschieden, nicht hier: diese Bruecke reicht sie nur weiter.
  neu: (name, machine, fernPfad, echt) => import_electron.ipcRenderer.invoke("awb:sitz-neu", name, machine, fernPfad, echt === true),
  // Der zweite Weg (12.08.): eine Chat-Sitzung. Kein `machine`, kein
  // `fernPfad` -- sie ist ein Prozess DIESER App und laeuft dort, wo die App
  // laeuft. Die Echtheit des Klicks reist mit, wie beim ersten Weg: ohne sie
  // gibt es keinen Ordnerdialog.
  neuChat: (name, echt) => import_electron.ipcRenderer.invoke("awb:sitz-neu-chat", String(name), echt === true),
  wahlDaten: () => import_electron.ipcRenderer.invoke("awb:sitz-wahl-daten"),
  kontextStufen: (modellId) => import_electron.ipcRenderer.invoke("awb:kontext-stufen", modellId),
  neuMitWahl: (name, machine, fernPfad, wahl, echt) => import_electron.ipcRenderer.invoke("awb:sitz-neu-wahl", name, machine, fernPfad, wahl, echt === true),
  fernPruefen: (machine, pfad) => import_electron.ipcRenderer.invoke("awb:sitz-fern-pruefen", machine, pfad),
  fortsetzen: (id, echt) => import_electron.ipcRenderer.invoke("awb:sitz-fortsetzen", id, echt === true),
  modellWechseln: (id, modell, effort, echt) => import_electron.ipcRenderer.invoke("awb:sitz-modell-wechsel", id, modell, effort, echt === true),
  beenden: (id, echt) => import_electron.ipcRenderer.invoke("awb:sitz-beenden", id, echt === true),
  onDaten: (fn) => import_electron.ipcRenderer.on("awb:sitz-daten-neu", (_e, d) => fn(d)),
  onWahl: (fn) => import_electron.ipcRenderer.on("awb:sitz-wahl-neu", (_e, d) => fn(d)),
  // Ein Start, der SPAETER scheitert (21.08.2026): `neu`/`neuMitWahl` antworten,
  // sobald `wb-code` abgeschickt ist -- der Grund fuer einen Fehlschlag entsteht
  // erst Sekunden danach und braucht deshalb einen eigenen Weg zurueck. Ohne ihn
  // bleibt im Fenster "wird gestartet" stehen, waehrend nichts mehr kommt.
  onStartfehler: (fn) => import_electron.ipcRenderer.on("awb:sitz-startfehler", (_e, p) => fn(p)),
  bereit: () => import_electron.ipcRenderer.send("awb:sitz-bereit"),
  // Farben durchreichen (11.08.): derselbe Kanal wie in den drei anderen
  // Fenstern (main/thema.ts) -- sitzung.ts fasst diese Bruecke nicht an, die
  // Anwendung steht als eigenes Skript in index.html.
  thema: () => import_electron.ipcRenderer.invoke("awb:thema-daten"),
  onThema: (fn) => import_electron.ipcRenderer.on("awb:thema-neu", (_e, p) => fn(p))
});
