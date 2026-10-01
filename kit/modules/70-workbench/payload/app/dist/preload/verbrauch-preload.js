"use strict";

// src/preload/verbrauch-preload.ts
var import_electron = require("electron");
import_electron.contextBridge.exposeInMainWorld("awbVerbrauch", {
  daten: (frage) => import_electron.ipcRenderer.invoke("awb:verbrauch-daten", frage),
  sprache: () => import_electron.ipcRenderer.invoke("awb:sprache"),
  bereit: () => import_electron.ipcRenderer.send("awb:verbrauch-bereit"),
  // Farben durchreichen (11.08.): derselbe Kanal wie in den anderen Fenstern
  // (main/thema.ts).
  thema: () => import_electron.ipcRenderer.invoke("awb:thema-daten"),
  onThema: (fn) => import_electron.ipcRenderer.on("awb:thema-neu", (_e, p) => fn(p))
});
