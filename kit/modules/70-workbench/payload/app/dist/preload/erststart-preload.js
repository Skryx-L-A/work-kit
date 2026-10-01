"use strict";

// src/preload/erststart-preload.ts
var import_electron = require("electron");
import_electron.contextBridge.exposeInMainWorld("awbErststart", {
  daten: () => import_electron.ipcRenderer.invoke("awb:erststart-daten"),
  setzen: (key, value) => import_electron.ipcRenderer.invoke("awb:erststart-setzen", key, value),
  bereit: () => import_electron.ipcRenderer.send("awb:erststart-bereit"),
  kontextStufen: (modellId) => import_electron.ipcRenderer.invoke("awb:kontext-stufen", modellId),
  // Farben durchreichen (11.08.): derselbe Kanal wie in den anderen Fenstern
  // (main/thema.ts).
  thema: () => import_electron.ipcRenderer.invoke("awb:thema-daten"),
  onThema: (fn) => import_electron.ipcRenderer.on("awb:thema-neu", (_e, p) => fn(p))
});
