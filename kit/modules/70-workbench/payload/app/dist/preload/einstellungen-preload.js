"use strict";

// src/preload/einstellungen-preload.ts
var import_electron = require("electron");
import_electron.contextBridge.exposeInMainWorld("awbEinstellungen", {
  daten: () => import_electron.ipcRenderer.invoke("awb:ein-daten"),
  setzen: (key, value) => import_electron.ipcRenderer.invoke("awb:ein-setzen", key, value),
  ui: (key, value) => import_electron.ipcRenderer.invoke("awb:ein-ui", key, value),
  // Die Echtheit des Klicks reist mit. Sie kommt aus `isTrusted` und wird im
  // Hauptprozess entschieden, nicht hier: diese Bruecke reicht sie nur weiter.
  werkzeug: (nachricht, echt) => import_electron.ipcRenderer.invoke("awb:ein-werkzeug", nachricht, echt === true),
  maschinePruefen: (name) => import_electron.ipcRenderer.invoke("awb:ein-maschine-pruefen", name),
  onDaten: (fn) => import_electron.ipcRenderer.on("awb:ein-daten-neu", (_e, d) => fn(d)),
  bereit: () => import_electron.ipcRenderer.send("awb:ein-bereit"),
  schluesselStatus: () => import_electron.ipcRenderer.invoke("awb:ein-schluessel-status"),
  schluesselSetzen: (providerId, wert) => import_electron.ipcRenderer.invoke("awb:ein-schluessel-setzen", providerId, wert),
  meldungTesten: () => import_electron.ipcRenderer.invoke("awb:ein-meldung-testen"),
  kontextStufen: (modellId) => import_electron.ipcRenderer.invoke("awb:kontext-stufen", modellId),
  erststartZeigen: (echt) => import_electron.ipcRenderer.send("awb:bedienung", { aktion: echt ? "erststart-zeigen" : "erststart-bauen", wert: null }),
  // ZEHNTER BIS ZWOELFTER WEG (Paket 10, mobile Werkbank), wieder bewusst SCHMAL:
  //   mobilStand()        Lesen: laeuft der Server, welche Geraete sind gekoppelt. Nie ein Code.
  //   mobilKoppeln()      Kopplung starten; die Echtheit des Klicks reist mit, der
  //                       Hauptprozess prueft sie und zusaetzlich `wb-mensch`.
  //   mobilWiderrufen()   ein Geraet widerrufen; dieselben zwei Bedingungen.
  // Der Steuerkanal hat fuer die beiden Handlungen keinen Befehl.
  mobilStand: () => import_electron.ipcRenderer.invoke("awb:mobil-stand"),
  mobilKoppeln: (echt) => import_electron.ipcRenderer.invoke("awb:mobil-koppeln", echt === true),
  mobilWiderrufen: (deviceId, echt) => import_electron.ipcRenderer.invoke("awb:mobil-widerrufen", deviceId, echt === true)
});
