"use strict";
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// src/preload/preload.ts
var preload_exports = {};
module.exports = __toCommonJS(preload_exports);
var import_electron = require("electron");
import_electron.contextBridge.exposeInMainWorld("awbEditorBridge", {
  listFiles: (root) => import_electron.ipcRenderer.invoke("awb:editor-list-files", root),
  readFile: (root, rel) => import_electron.ipcRenderer.invoke("awb:editor-read-file", root, rel),
  writeFile: (root, rel, content) => import_electron.ipcRenderer.invoke("awb:editor-write-file", root, rel, content),
  sendSelection: (paneId, text) => import_electron.ipcRenderer.invoke("awb:editor-send-selection", paneId, text),
  // V15/V18 (Schritt 9): Inhalt, Diff und Auftragskontext eines
  // Aktivitaets-Eintrags -- alle drei landen "in der Mitte", deshalb dieselbe
  // Bruecke wie die projektbezogenen Dateien oben.
  aktivitaetRead: (pfad) => import_electron.ipcRenderer.invoke("awb:aktivitaet-read", pfad),
  aktivitaetDiff: (pfad) => import_electron.ipcRenderer.invoke("awb:aktivitaet-diff", pfad),
  aktivitaetAuftrag: (pfad) => import_electron.ipcRenderer.invoke("awb:aktivitaet-auftrag", pfad),
  // V16: die konfigurierte Protokoll-Liste, und eine ihrer Dateien lesen.
  protokolleList: () => import_electron.ipcRenderer.invoke("awb:protokolle-list"),
  protokolleRead: (pfad) => import_electron.ipcRenderer.invoke("awb:protokolle-read", pfad),
  // SPEC-V4 Abschnitt 6: der Gespraechsstand eines Panes. Nur lesen -- die
  // Eingabe bleibt am Pane, und dieser Weg fuehrt in keine Richtung zurueck.
  chatStand: (paneId) => import_electron.ipcRenderer.invoke("awb:chat-stand", paneId),
  // Der Griff und die Ansicht setzen die Sitzungs-Uebersteuerung selbst, statt
  // sich nur lokal zu zeigen -- derselbe Schreibweg wie der Rechtsklick auf
  // die Sitzung (main.ts, Menuepunkt 'chat-ansicht').
  chatAnsichtSetzen: (paneId, an) => import_electron.ipcRenderer.invoke("awb:chat-ansicht-setzen", paneId, an),
  // PFADE IM CHAT, ANKLICKBAR (chatdatei, 05.09.2026): je Nachricht EINE Liste von
  // Kandidaten pruefen, und einen gemeldeten Treffer oeffnen (main/chatpfade.ts).
  chatPfade: (paneId, kandidaten) => import_electron.ipcRenderer.invoke("awb:chat-pfade", paneId, kandidaten),
  chatPfadOeffnen: (abs) => import_electron.ipcRenderer.invoke("awb:chat-pfad-oeffnen", abs),
  // Die Sprache der Oberflaeche -- derselbe geteilte Kanal wie bei der Verbrauchsseite
  // (main.ts, `awb:sprache`), hier fuer den Dokumenttitel und `<html lang>` des Hauptfensters.
  sprache: () => import_electron.ipcRenderer.invoke("awb:sprache")
});
import_electron.contextBridge.exposeInMainWorld("awbBridge", {
  // Ein einzelner, feststehender Wert (kein IPC-Umweg): der Renderer braucht
  // ihn nur, um auf dem Mac Platz fuer die drei Fensterknoepfe freizuhalten
  // (`titleBarStyle: 'hiddenInset'`, siehe main.ts). `process.platform` gibt
  // es im Renderer selbst nicht -- er laeuft mit `nodeIntegration: false`.
  plattform: process.platform,
  // Das Home dieses Laufs fuer die Pfadkuerzung `~` (renderer/kurzpfad.ts).
  heim: process.env.HOME ?? "",
  // AWB_TESTHAKEN=1: die schreibenden Testhaken des Tabs Agents sind da
  // (Reviewer-Befund M4, 11.09.2026). Ohne die Variable gibt es sie nicht.
  testhaken: process.env.AWB_TESTHAKEN === "1",
  ready: () => import_electron.ipcRenderer.send("awb:ready"),
  onSession: (fn) => import_electron.ipcRenderer.on("awb:session", (_e, p) => fn(p)),
  onOutput: (fn) => import_electron.ipcRenderer.on("awb:output", (_e, d) => fn(d)),
  // Eine Ansicht kann MEHRERE Panes haben: die Aufteilung kommt mit.
  onLayout: (fn) => import_electron.ipcRenderer.on("awb:layout", (_e, p) => fn(p)),
  onModel: (fn) => import_electron.ipcRenderer.on("awb:model", (_e, p) => fn(p)),
  // V20: die Freigabe-Ansicht -- Antraege und angehaltene Worker.
  onFreigaben: (fn) => import_electron.ipcRenderer.on("awb:freigaben", (_e, p) => fn(p)),
  // Der Tab „Agents" (main/aufgaben.ts, main/welten.ts): der Stand im Takt,
  // einmal auf Zuruf, und eine Handlung `welt:<handlung> <JSON>`.
  // `opt.bestaetigt` ist die zweite Stufe nach einer Rueckfrage; `echt` kommt
  // wie beim Sitzungsmenue aus `isTrusted` und wird hier nur weitergereicht.
  onAufgaben: (fn) => import_electron.ipcRenderer.on("awb:aufgaben", (_e, p) => fn(p)),
  aufgabenDaten: () => import_electron.ipcRenderer.invoke("awb:aufgaben-daten"),
  aufgabe: (befehl, opt = {}) => import_electron.ipcRenderer.invoke("awb:aufgabe", String(befehl), { echt: opt.echt === true, bestaetigt: opt.bestaetigt === true }),
  // Zeigt die Oberflaeche die Ansicht? Verborgen taktet der Kern mit 30 statt 2 s.
  aufgabenSichtbar: (an) => import_electron.ipcRenderer.send("awb:aufgaben-sichtbar", an === true),
  // Auftrag agentsform: der Ordnerdialog fuer eine neue Welt; `echt` aus `isTrusted`, sonst kein Dialog.
  weltOrdnerWaehlen: (echt) => import_electron.ipcRenderer.invoke("awb:welt-ordner", echt === true),
  // Schritt 7: das HTML einer uebernommenen Seite, fertig gerendert.
  onSeite: (fn) => import_electron.ipcRenderer.on("awb:seite", (_e, p) => fn(p)),
  // Reste-Auftrag Punkt 3: die Datei hinter einer Seite hat sich von aussen
  // geaendert -- nur die Meldung, welche; ob neu gezeichnet wird, entscheidet
  // der Renderer selbst (seiten-view.ts: aufDateiAendern).
  onDateiGeaendert: (fn) => import_electron.ipcRenderer.on("awb:datei-geaendert", (_e, p) => fn(p)),
  // Vor einer Handlung mit Nebenwirkung: was geschehen wird. Und danach: was es tat.
  onPlan: (fn) => import_electron.ipcRenderer.on("awb:plan", (_e, p) => fn(p)),
  onPlanErgebnis: (fn) => import_electron.ipcRenderer.on("awb:plan-ergebnis", (_e, p) => fn(p)),
  // V2: eine Ergebnisdatei ist entstanden. Kommt einzeln, sobald sie da ist.
  onErgebnis: (fn) => import_electron.ipcRenderer.on("awb:ergebnis", (_e, p) => fn(p)),
  // 4c: Ordneransicht, Aktivitaetsliste, Inhaltssuche -- je eine Antwort auf Zuruf.
  onOrdner: (fn) => import_electron.ipcRenderer.on("awb:ordner", (_e, p) => fn(p)),
  // Ob die Anwendung in einem Pane die Maus verfolgt -- nachgefuehrt im Takt.
  onMaus: (fn) => import_electron.ipcRenderer.on("awb:maus", (_e, p) => fn(p)),
  onAktivitaet: (fn) => import_electron.ipcRenderer.on("awb:aktivitaet", (_e, p) => fn(p)),
  onSuche: (fn) => import_electron.ipcRenderer.on("awb:suche", (_e, p) => fn(p)),
  // Ob ein Steuerkanal da ist. Faellt er aus, steht das Fenster trotzdem --
  // und sagt es sichtbar, statt still ohne Verbindung dazustehen.
  onKanal: (fn) => import_electron.ipcRenderer.on("awb:kanal", (_e, p) => fn(p)),
  // Eingabe geht an einen bestimmten Pane, nicht an "den einen".
  input: (paneId, base64) => import_electron.ipcRenderer.send("awb:input", { paneId, base64 }),
  bedienung: (aktion, wert) => import_electron.ipcRenderer.send("awb:bedienung", { aktion, wert }),
  // Ein gezeichnetes Terminal steht ohne Rueckblick da. Nur der Renderer sieht
  // das (der Puffer liegt bei ihm), nur der Hauptprozess kann ihn holen.
  rueckblickFehlt: (paneId) => import_electron.ipcRenderer.send("awb:rueckblick-fehlt", { paneId }),
  // Das Kontextmenue der Sessionleiste. `echt` kommt aus `isTrusted` und wird
  // im Hauptprozess entschieden, nicht hier: diese Bruecke reicht es weiter.
  sitzungsMenue: (id, echt) => import_electron.ipcRenderer.send("awb:sitzung-menue", { id, echt: echt === true }),
  onUmbenennen: (fn) => import_electron.ipcRenderer.on("awb:umbenennen", (_e, p) => fn(p)),
  // Was ein Griff im Hauptprozess ergeben hat, in einem Satz. Dieselbe Zeile,
  // die auch das Umbenennen zeigt -- ein Menuepunkt, der nicht mehr grau ist,
  // muss sagen koennen, warum er nicht durchging.
  onMeldung: (fn) => import_electron.ipcRenderer.on("awb:meldung", (_e, p) => fn(p)),
  // Die Chat-Ansicht EINES Panes umschalten (12.08., Rechtsklick auf die
  // Sitzung). Sie wirkt sofort: der Renderer haelt je Pane eine Ansicht, die
  // sich ein- und ausblenden laesst -- kein neues Fenster, keine angefasste
  // Sitzung. Entschieden hat der Hauptprozess, hier kommt nur das Ergebnis an.
  onChatAnsicht: (fn) => import_electron.ipcRenderer.on("awb:chat-ansicht", (_e, p) => fn(p)),
  umbenennen: (id, name) => import_electron.ipcRenderer.invoke("awb:sitzung-umbenennen", id, name),
  // Farben durchreichen (11.08.): Thema und Zustandsfarben, aus derselben
  // gemeinsamen Stelle wie in den drei anderen Fenstern (main/thema.ts).
  thema: () => import_electron.ipcRenderer.invoke("awb:thema-daten"),
  onThema: (fn) => import_electron.ipcRenderer.on("awb:thema-neu", (_e, p) => fn(p)),
  // Die System-Zwischenablage (SSH-clipfix): das Terminal zeichnet auf einen
  // Canvas, nicht in eine editierbare DOM-Flaeche -- deshalb hilft ihm weder
  // ein Menuepunkt noch die eingebaute Tastaturbehandlung von Chromium, und
  // Strg+Umschalt+C/V muss selbst lesen und schreiben. Der Weg fuehrt ueber
  // Electrons `clipboard`-Modul im Hauptprozess, nicht ueber `navigator.clipboard`
  // hier: das eine braucht keine Berechtigungsabfrage, das andere schon.
  zwischenablageLesen: () => import_electron.ipcRenderer.invoke("awb:zwischenablage-lesen"),
  zwischenablageSchreiben: (text) => import_electron.ipcRenderer.invoke("awb:zwischenablage-schreiben", String(text))
});
import_electron.contextBridge.exposeInMainWorld("awbChat", {
  // `seit` sagt, welchen Takt die Buehne schon hat -- 0 heisst „alles"
  // (Befund B1). Ohne diese Zahl ginge bei jedem Token der volle Stand hinaus.
  daten: (seit) => import_electron.ipcRenderer.invoke("awb:chat-daten", Number(seit) || 0),
  senden: (text) => import_electron.ipcRenderer.invoke("awb:chat-senden", String(text)),
  freigabe: (anfrageId, erlauben) => import_electron.ipcRenderer.invoke("awb:chat-freigabe", String(anfrageId), erlauben === true),
  // Frisch starten nach einem Fehlstart auf einer verschwundenen
  // Unterhaltung (Befund B3).
  neustart: () => import_electron.ipcRenderer.invoke("awb:chat-neustart"),
  // Den Freigabemodus zur Laufzeit umstellen (Luecke 5c) und einen laufenden
  // Zug unterbrechen (Punkt 6) -- beides gemessen am echten Protokoll, siehe
  // main/chatsitzung.ts.
  modus: (modus) => import_electron.ipcRenderer.invoke("awb:chat-modus", String(modus)),
  halt: () => import_electron.ipcRenderer.invoke("awb:chat-halt"),
  // Die Dateiliste fuer das `@` im Eingabefeld. Einmal je Sitzung geholt und
  // im Fenster gefiltert -- die Liste eines grossen Repos gehoert nicht bei
  // jedem Tastendruck durch den Kanal.
  dateien: () => import_electron.ipcRenderer.invoke("awb:chat-dateien"),
  onStand: (fn) => import_electron.ipcRenderer.on("awb:chat-stand-neu", (_e, s) => fn(s)),
  // Die Kennung reist MIT: auf sie wartet der Hauptprozess, und eine Meldung
  // aus einem ueberholten Wechsel darf das Warten nicht beenden.
  bereit: (id) => import_electron.ipcRenderer.send("awb:chat-bereit", String(id))
});
