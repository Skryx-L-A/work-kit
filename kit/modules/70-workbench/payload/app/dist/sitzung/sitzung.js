"use strict";
(() => {
  // src/sitzung/filter.ts
  function chipsAus(zeilen, schluessel, label, alleLabel) {
    const proSchluessel = /* @__PURE__ */ new Map();
    for (const z of zeilen) {
      const s = schluessel(z);
      proSchluessel.set(s, (proSchluessel.get(s) ?? 0) + 1);
    }
    if (proSchluessel.size < 2) return [];
    return [
      { wert: "alle", label: alleLabel(zeilen.length) },
      ...[...proSchluessel.entries()].sort((a, b) => b[1] - a[1]).map(([s, n]) => ({ wert: s, label: label(s, n) }))
    ];
  }
  function zeilePasstSuche(z, suche) {
    const n = suche.trim().toLowerCase();
    if (!n) return true;
    return z.name.toLowerCase().includes(n) || z.dir.toLowerCase().includes(n) || z.machine.toLowerCase().includes(n);
  }
  function zeilePasstMaschine(z, filter) {
    return filter === "alle" || z.machine === filter;
  }
  function zeilePasstZustand(z, filter) {
    return filter === "alle" || z.state === filter;
  }

  // src/sitzung/texte.ts
  var DE = {
    "fenster.titel": "Agent-Workbench \u2013 Sitzungen",
    "kopf.titel": "Sitzungen",
    "kopf.unterzeile": "Nach Projektordner gruppiert, die zuletzt benutzte oben. Jede bekannte Sitzung steht hier, auch die beendeten und die zweite und dritte desselben Ordners.",
    "platzhalter.name": "Name (optional)",
    "knopf.neu": "Neue Sitzung \u2026",
    // Der zweite Weg (12.08.): eine Chat-Sitzung als Prozess dieser App, ohne tmux.
    "knopf.neuChat": "Neue Chat-Sitzung \u2026",
    // Der dritte Weg (19.08.): eine Wahl, die nur für diese eine Sitzung gilt.
    "knopf.neuWahl": "Modell f\xFCr diese Sitzung w\xE4hlen \u2026",
    "knopf.neuWahlZu": "Wahl schlie\xDFen",
    "knopf.neuWahlStart": "Mit dieser Wahl starten \u2026",
    "wahl.titel": "Nur f\xFCr diese Sitzung",
    "wahl.unterzeile": "Vorbelegt ist \xFCberall, was in den Einstellungen steht \u2013 wer nur eine Sache anders will, \xE4ndert eine Sache. Die Einstellungsdatei bleibt dabei unber\xFChrt; die Wahl endet mit dieser Sitzung.",
    "wahl.harness": "Programm",
    "wahl.modell": "Modell",
    "wahl.effort": "Wie tief die Sitzung denkt",
    "wahl.kontext": "Kontextfenster",
    "wahl.platzhalterSuche": "Nach Name oder Kennung filtern \u2026",
    "wahl.keinModell": "F\xFCr dieses Programm ist kein Modell mit der Rolle \u201EOrchestrator\u201C bekannt.",
    "wahl.keinTreffer": "Kein Modell passt zu dieser Suche.",
    "wahl.keineStufen": "Dieses Programm kennt keine Denkstufen \u2013 es wird keine mitgegeben.",
    "wahl.kontextNurLokal": "Nur bei einem Modell, das hier auf der Maschine l\xE4uft \u2013 bei einem Modell aus der Cloud geh\xF6rt diese Zahl dem Anbieter.",
    "wahl.kontextWirdErmittelt": "Die Stufen werden ermittelt \u2026",
    "wahl.kontextNichtErmittelt": "Die Stufen lie\xDFen sich nicht ermitteln: {grund}. Es geht dann kein Kontextfenster mit, und es gilt, was f\xFCr dieses Modell eingetragen ist.",
    "wahl.kontextEmpfohlen": "empfohlen",
    "wahl.kontextToken": "{tokens} Token",
    "wahl.kontextBedarf": "Braucht {bedarf} GiB.",
    "wahl.nichtStartbar": "Programm fehlt auf dieser Maschine",
    "wahl.flaggenLeer": "Ohne eigene Angabe \u2013 es gilt, was in den Einstellungen steht.",
    "wahl.laedt": "Hole, was zur Wahl steht \u2026",
    "wahl.ladefehler": "Was zur Wahl steht, lie\xDF sich nicht holen: {grund}",
    "platzhalter.fernpfadVorgabe": "Absoluter Pfad auf der gew\xE4hlten Maschine \u2026",
    "platzhalter.fernpfad": "Absoluter Pfad auf '{maschine}' \u2026",
    "knopf.pruefen": "Pr\xFCfen",
    "platzhalter.suche": "Suche nach Name, Ordner oder Maschine \u2026",
    "zustand.laeuft": "l\xE4uft",
    "zustand.wartet": "wartet",
    "zustand.fern": "fern",
    "zustand.beendet": "beendet",
    "zustand.startet": "startet\u2026",
    "zustand.startFehler": "Start gescheitert",
    "satz.ohneOrdner": "(ohne Ordner)",
    "zeit.nieAktiv": "nie aktiv",
    "satz.dieseMaschine": "{maschine} (diese Maschine)",
    "wort.alle": "Alle {n}",
    "wort.sitzungenAnzahl": "{n} Sitzungen",
    "satz.keineSitzungBekannt": "Es ist keine Sitzung bekannt.",
    "satz.waehleSitzung": "Eine Sitzung w\xE4hlen \u2013 was mit ihrer Unterhaltung geschieht, steht dann hier.",
    "satz.erstOrdnerEintragen": "Erst einen Ordner auf '{maschine}' eintragen.",
    "satz.erstPfadEintragen": "Erst einen Pfad eintragen.",
    "satz.pruefeGerade": "Pr\xFCfe \u2026",
    "satz.holeZurueck": "Hole die Sitzung zur\xFCck \u2026",
    "knopf.beenden": "Beenden",
    "knopf.fortsetzen": "Fortsetzen",
    // Der Mantel (Mac, Auftrag 2.7, 06.09.) zeichnet das Fenster als Formular
    // mit Gruppen und einer Rollenwahl; die Woerter dafuer stehen HIER, damit
    // es weiter nur eine Tabelle gibt (`awb:sitz-texte`).
    "gruppe.ordner": "Ordner",
    "gruppe.maschine": "Maschine",
    "gruppe.harness": "Programm",
    "gruppe.modell": "Modell",
    "gruppe.effort": "Denkstufe",
    "gruppe.rolle": "Rolle",
    "gruppe.sitzungen": "Bekannte Sitzungen",
    "rolle.orchestrator": "Orchestrator im Terminal",
    "rolle.chat": "Chat-Sitzung",
    "rolle.chatHinweis": "Eine Chat-Sitzung l\xE4uft als Prozess dieser App, mit dem Modell aus den Einstellungen \u2013 ohne tmux und ohne Fernmaschine.",
    "satz.ordnerImDialog": "Der Ordner wird beim Start im Dialog gew\xE4hlt.",
    "wahl.deckel": "Deckel dieses Modells: {deckel} ({quelle})",
    "wahl.deckelHinweis": "Ein Deckel bindet den Orchestrator, nicht Dich. Die Stufen dar\xFCber bleiben w\xE4hlbar.",
    "wahl.keinDeckel": "Kein Deckel bekannt f\xFCr dieses Modell.",
    "knopf.start": "Sitzung starten \u2026",
    "satz.abgebrochenNichtsBeendet": "Abgebrochen \u2013 nichts beendet.",
    "frage.beenden": "\u201E{name}\u201C beenden?",
    "frage.beendenText": "Der Pane schlie\xDFt; die Zustandsdatei bleibt, die Sitzung l\xE4sst sich danach fortsetzen.",
    "knopf.abbrechen": "Abbrechen",
    "satz.startetGerade": "Die Sitzung wird gestartet \u2026"
  };
  var EN = {
    "fenster.titel": "Agent Workbench \u2014 Sessions",
    "kopf.titel": "Sessions",
    "kopf.unterzeile": "Grouped by project folder, most recently used on top. Every known session is listed here, including the stopped ones and a second or third one in the same folder.",
    "platzhalter.name": "Name (optional)",
    "knopf.neu": "New Session \u2026",
    "knopf.neuChat": "New Chat Session \u2026",
    "knopf.neuWahl": "Pick a model for this session \u2026",
    "knopf.neuWahlZu": "Close the picker",
    "knopf.neuWahlStart": "Start with this choice \u2026",
    "wahl.titel": "For this session only",
    "wahl.unterzeile": "Everything is prefilled from Settings \u2014 change one thing if only one thing should differ. The settings file stays untouched; the choice ends with this session.",
    "wahl.harness": "Program",
    "wahl.modell": "Model",
    "wahl.effort": "How deep the session thinks",
    "wahl.kontext": "Context window",
    "wahl.platzhalterSuche": "Filter by name or id \u2026",
    "wahl.keinModell": 'No model with the role "orchestrator" is known for this program.',
    "wahl.keinTreffer": "No model matches this search.",
    "wahl.keineStufen": "This program knows no thinking levels \u2014 none will be passed.",
    "wahl.kontextNurLokal": "Only for a model that runs here on this machine \u2014 for a model in the cloud that number belongs to the provider.",
    "wahl.kontextWirdErmittelt": "Determining the levels \u2026",
    "wahl.kontextNichtErmittelt": "The levels could not be determined: {grund}. No context window will be passed, and whatever is registered for this model applies.",
    "wahl.kontextEmpfohlen": "recommended",
    "wahl.kontextToken": "{tokens} tokens",
    "wahl.kontextBedarf": "Needs {bedarf} GiB.",
    "wahl.nichtStartbar": "Program missing on this machine",
    "wahl.flaggenLeer": "Nothing of its own \u2014 whatever is in Settings applies.",
    "wahl.laedt": "Fetching what there is to choose from \u2026",
    "wahl.ladefehler": "What there is to choose from could not be fetched: {grund}",
    "platzhalter.fernpfadVorgabe": "Absolute path on the chosen machine \u2026",
    "platzhalter.fernpfad": "Absolute path on '{maschine}' \u2026",
    "knopf.pruefen": "Check",
    "platzhalter.suche": "Search by name, folder, or machine \u2026",
    "zustand.laeuft": "running",
    "zustand.wartet": "waiting",
    "zustand.fern": "remote",
    "zustand.beendet": "stopped",
    "zustand.startet": "starting\u2026",
    "zustand.startFehler": "start failed",
    "satz.ohneOrdner": "(no folder)",
    "zeit.nieAktiv": "never active",
    "satz.dieseMaschine": "{maschine} (this machine)",
    "wort.alle": "All {n}",
    "wort.sitzungenAnzahl": "{n} sessions",
    "satz.keineSitzungBekannt": "No session is known.",
    "satz.waehleSitzung": "Pick a session \u2014 what happens to its conversation shows up here.",
    "satz.erstOrdnerEintragen": "Enter a folder on '{maschine}' first.",
    "satz.erstPfadEintragen": "Enter a path first.",
    "satz.pruefeGerade": "Checking \u2026",
    "satz.holeZurueck": "Bringing the session back \u2026",
    "knopf.beenden": "Stop",
    "knopf.fortsetzen": "Resume",
    "gruppe.ordner": "Folder",
    "gruppe.maschine": "Machine",
    "gruppe.harness": "Program",
    "gruppe.modell": "Model",
    "gruppe.effort": "Thinking level",
    "gruppe.rolle": "Role",
    "gruppe.sitzungen": "Known sessions",
    "rolle.orchestrator": "Orchestrator in the terminal",
    "rolle.chat": "Chat session",
    "rolle.chatHinweis": "A chat session runs as a process of this app, with the model from Settings \u2014 no tmux, no remote machine.",
    "satz.ordnerImDialog": "The folder is chosen in the dialog when you start.",
    "wahl.deckel": "Cap of this model: {deckel} ({quelle})",
    "wahl.deckelHinweis": "A cap binds the orchestrator, not you. The levels above it stay selectable.",
    "wahl.keinDeckel": "No cap known for this model.",
    "knopf.start": "Start session \u2026",
    "satz.abgebrochenNichtsBeendet": "Cancelled \u2014 nothing stopped.",
    "frage.beenden": "Stop \u201C{name}\u201D?",
    "frage.beendenText": "The pane closes; the state file stays, and the session can be resumed afterwards.",
    "knopf.abbrechen": "Cancel",
    "satz.startetGerade": "Starting the session \u2026"
  };
  var TABELLEN = { de: DE, en: EN };
  var aktuelleSprache = "en";
  function setzeSprache(s) {
    aktuelleSprache = s === "de" ? "de" : "en";
  }
  function sprache() {
    return aktuelleSprache;
  }
  function t(schluessel, werte) {
    const tabelle = TABELLEN[aktuelleSprache] ?? DE;
    const roh = tabelle[schluessel] ?? DE[schluessel];
    if (roh === void 0) return `[fehlender Text: ${schluessel}]`;
    if (!werte) return roh;
    return roh.replace(/\{([A-Za-z][A-Za-z0-9]*)\}/g, (ganz, name) => {
      const w = werte[name];
      return w === void 0 ? ganz : String(w);
    });
  }

  // src/sitzung/sitzung.ts
  var daten = null;
  var gewaehlteSitzung = "";
  var nameWert = "";
  var beschaeftigt = false;
  var maschineWert = "";
  var fernPfadWert = "";
  var fernStatus = "";
  var fernStatusArt = "";
  var fernPrueftGerade = false;
  var sucheWert = "";
  var maschineFilter = "alle";
  var zustandFilter = "alle";
  var wahlOffen = false;
  var wahlDaten = null;
  var wahlFehler = "";
  var wahlLaedt = false;
  var wahlVersucht = false;
  var wahl = { harness: "", model: "", effort: "", kontext: 0 };
  var wahlSuche = "";
  var wechselModell = "";
  var kontextStand = {};
  var kontextLaeuft = /* @__PURE__ */ new Set();
  var gruppenEl = document.getElementById("gruppen");
  var statusEl = document.getElementById("statuszeile");
  var grundEl = document.getElementById("fort-grund");
  var fortKnopf = document.getElementById("fort-start");
  var beendenKnopf = document.getElementById("beenden-start");
  var wechselZeile = document.getElementById("modell-wechsel-zeile");
  var wechselAuswahl = document.getElementById("modell-wechsel");
  var wechselKnopf = document.getElementById("modell-wechsel-start");
  var neuKnopf = document.getElementById("neu-start");
  var neuChatKnopf = document.getElementById("neu-chat");
  var neuWahlKnopf = document.getElementById("neu-wahl");
  var wahlBlockEl = document.getElementById("neu-wahl-block");
  var nameFeld = document.getElementById("neu-name");
  var kopfStartEl = document.getElementById("kopf-start");
  var fernEl = document.getElementById("neu-fern");
  var fernPfadFeld = document.getElementById("neu-fern-pfad");
  var fernOrdnerListe = document.getElementById("neu-fern-ordner");
  var fernPruefenKnopf = document.getElementById("neu-fern-pruefen");
  var fernStatusEl = document.getElementById("neu-fern-status");
  var maschineChipsEl = document.getElementById("maschine-chips");
  var zustandChipsEl = document.getElementById("zustand-chips");
  var suchFeld = document.getElementById("such-feld");
  var titelEl = document.getElementById("kopf-titel");
  var unterzeileEl = document.getElementById("kopf-unterzeile");
  function beschriften() {
    document.documentElement.lang = sprache();
    document.title = t("fenster.titel");
    titelEl.textContent = t("kopf.titel");
    unterzeileEl.textContent = t("kopf.unterzeile");
    nameFeld.placeholder = t("platzhalter.name");
    neuKnopf.textContent = t("knopf.neu");
    neuChatKnopf.textContent = t("knopf.neuChat");
    fernPfadFeld.placeholder = t("platzhalter.fernpfadVorgabe");
    fernPruefenKnopf.textContent = t("knopf.pruefen");
    suchFeld.placeholder = t("platzhalter.suche");
    beendenKnopf.textContent = t("knopf.beenden");
    fortKnopf.textContent = t("knopf.fortsetzen");
  }
  function el(tag, klasse, text) {
    const e = document.createElement(tag);
    if (klasse) e.className = klasse;
    if (text !== void 0) e.textContent = text;
    return e;
  }
  function melde(text, art = "") {
    statusEl.textContent = text;
    statusEl.className = art;
  }
  function wann(iso) {
    if (!iso) return t("zeit.nieAktiv");
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return iso;
    const p = (n) => String(n).padStart(2, "0");
    return `${p(d.getDate())}.${p(d.getMonth() + 1)}. ${p(d.getHours())}:${p(d.getMinutes())}`;
  }
  function zustandMarke(state, startet = false, startFehler = false) {
    if (startet) return { text: t("zustand.startet"), klasse: "marke wartet" };
    if (startFehler) return { text: t("zustand.startFehler"), klasse: "marke" };
    if (state === "running") return { text: t("zustand.laeuft"), klasse: "marke laeuft" };
    if (state === "attention") return { text: t("zustand.wartet"), klasse: "marke wartet" };
    if (state === "unreachable") return { text: t("zustand.fern"), klasse: "marke fern" };
    return { text: t("zustand.beendet"), klasse: "marke" };
  }
  function ordnerName(dir) {
    const teile = dir.split("/").filter(Boolean);
    return teile.length ? teile[teile.length - 1] : dir || t("satz.ohneOrdner");
  }
  function gruppiere(zeilen) {
    const map = /* @__PURE__ */ new Map();
    for (const z of zeilen) {
      const schluessel = `${z.machine} ${z.dir}`;
      const da = map.get(schluessel);
      if (da) da.zeilen.push(z);
      else map.set(schluessel, { schluessel, dir: z.dir, machine: z.machine, zeilen: [z] });
    }
    return [...map.values()];
  }
  function zeileBauen(z) {
    const klassen = ["listenzeile"];
    if (!z.fortsetzbar) klassen.push("tot");
    if (z.id === gewaehlteSitzung) klassen.push("gewaehlt");
    const zeile = el("button", klassen.join(" "));
    zeile.type = "button";
    zeile.dataset.sitzung = z.id;
    zeile.dataset.fortsetzbar = z.fortsetzbar ? "1" : "0";
    const z1 = el("div", "zeile1");
    z1.appendChild(el("span", void 0, z.name));
    const marke = zustandMarke(z.state, z.startet, z.startFehler);
    z1.appendChild(el("span", marke.klasse, marke.text));
    zeile.appendChild(z1);
    const womit = z.model ? `${z.harness} \xB7 ${z.model}` : z.harness || "claude";
    zeile.appendChild(el("div", "zeile2", `${womit} \u2014 ${wann(z.lastActive)}`));
    zeile.addEventListener("click", () => {
      gewaehlteSitzung = z.id;
      zeichne();
    });
    return zeile;
  }
  function zeichneMaschinenwahl() {
    if (!daten || daten.remoteMachines.length === 0) {
      document.getElementById("neu-maschine")?.remove();
      maschineWert = daten?.machine ?? "";
      return;
    }
    const optionen = [daten.machine, ...daten.remoteMachines];
    if (!optionen.includes(maschineWert)) maschineWert = daten.machine;
    let sel = document.getElementById("neu-maschine");
    if (!sel) {
      sel = el("select");
      sel.id = "neu-maschine";
      sel.addEventListener("change", () => {
        maschineWert = sel.value;
        fernStatus = "";
        fernStatusArt = "";
        zeichne();
      });
      kopfStartEl.insertBefore(sel, neuKnopf);
    }
    sel.textContent = "";
    for (const m of optionen) {
      const o = el("option");
      o.value = m;
      o.textContent = m === daten.machine ? t("satz.dieseMaschine", { maschine: m }) : m;
      sel.appendChild(o);
    }
    sel.value = maschineWert;
    sel.disabled = beschaeftigt;
  }
  function zeichneFernZeile() {
    const zeigen = !!daten && maschineWert !== daten.machine;
    fernEl.style.display = zeigen ? "flex" : "none";
    if (!zeigen) return;
    fernPfadFeld.placeholder = t("platzhalter.fernpfad", { maschine: maschineWert });
    if (fernPfadFeld.value !== fernPfadWert) fernPfadFeld.value = fernPfadWert;
    fernPruefenKnopf.disabled = beschaeftigt || fernPrueftGerade;
    fernStatusEl.textContent = fernStatus;
    fernStatusEl.style.color = fernStatusArt === "fehler" ? "var(--aus)" : fernStatusArt === "gut" ? "var(--laeuft)" : "";
    const bekannt = [...new Set(
      (daten?.sitzungen ?? []).filter((z) => z.machine === maschineWert).map((z) => z.dir)
    )];
    fernOrdnerListe.textContent = "";
    for (const dir of bekannt) {
      const o = el("option");
      o.value = dir;
      fernOrdnerListe.appendChild(o);
    }
  }
  function zeichneChipZeile(el2, chips, gewaehlt, auf) {
    el2.textContent = "";
    for (const c of chips) {
      const b = el("button");
      b.type = "button";
      b.textContent = c.label;
      b.dataset.filter = c.wert;
      if (c.wert === gewaehlt) b.classList.add("gewaehlt");
      b.addEventListener("click", () => auf(c.wert));
      el2.appendChild(b);
    }
  }
  function wahlHolen() {
    if (wahlLaedt || wahlVersucht) return;
    wahlLaedt = true;
    wahlVersucht = true;
    wahlFehler = "";
    void window.awbSitzung.wahlDaten().then((d) => {
      wahlDaten = d;
      if (!wahl.harness) wahl.harness = d.einstellung.harness;
      if (!wahl.model) wahl.model = d.einstellung.model;
      if (!wahl.effort) wahl.effort = d.einstellung.effort;
      if (!wahl.kontext) wahl.kontext = d.einstellung.kontext;
    }).catch((e) => {
      wahlFehler = String(e?.message ?? e);
    }).then(() => {
      wahlLaedt = false;
      zeichne();
    });
  }
  function kontextHolen(modellId) {
    if (!modellId || kontextLaeuft.has(modellId) || kontextStand[modellId]) return;
    kontextLaeuft.add(modellId);
    void window.awbSitzung.kontextStufen(modellId).then((a) => {
      kontextStand[modellId] = a;
    }).catch((e) => {
      kontextStand[modellId] = { ok: false, fehler: String(e) };
    }).then(() => {
      kontextLaeuft.delete(modellId);
      zeichne();
    });
  }
  function wahlZeile(name, steuer, hinweis) {
    const z = el("div", "wahlzeile");
    z.dataset.wahl = name;
    z.appendChild(el("div", "wahlname", name));
    z.appendChild(steuer);
    if (hinweis) z.appendChild(el("div", "wahlhinweis", hinweis));
    return z;
  }
  function wahlEintrag(zeile1, zeile2, gewaehlt, auf) {
    const b = el("button", gewaehlt ? "wahleintrag gewaehlt" : "wahleintrag");
    b.type = "button";
    b.appendChild(zeile1);
    if (zeile2) b.appendChild(zeile2);
    b.addEventListener("click", auf);
    return b;
  }
  function wahlFlaggen(modell, stufen) {
    const f = [];
    if (wahl.harness) f.push("--harness", wahl.harness);
    if (wahl.model) f.push("--model", wahl.model);
    if (wahl.effort && stufen.includes(wahl.effort)) f.push("--effort", wahl.effort);
    if (modell?.lokal && wahl.kontext > 0) f.push("--kontext", String(wahl.kontext));
    return f;
  }
  function zeichneWahlblock() {
    neuWahlKnopf.textContent = wahlOffen ? t("knopf.neuWahlZu") : t("knopf.neuWahl");
    neuWahlKnopf.disabled = beschaeftigt;
    wahlBlockEl.style.display = wahlOffen ? "block" : "none";
    document.body.classList.toggle("wahl-offen", wahlOffen);
    if (!wahlOffen) return;
    wahlBlockEl.textContent = "";
    if (!wahlDaten) {
      wahlHolen();
      wahlBlockEl.appendChild(el(
        "div",
        "wahlhinweis",
        wahlFehler ? t("wahl.ladefehler", { grund: wahlFehler }) : t("wahl.laedt")
      ));
      return;
    }
    const d = wahlDaten;
    wahlBlockEl.appendChild(el("div", "wahlname", t("wahl.titel")));
    wahlBlockEl.appendChild(el("div", "wahlhinweis", t("wahl.unterzeile")));
    const harnessReihe = el("div", "filterzeile");
    for (const h of d.harnesses) {
      const b = el("button");
      b.type = "button";
      b.textContent = h.binaer ? h.label : `${h.label} \xB7 ${t("wahl.nichtStartbar")}`;
      b.dataset.wahlHarness = h.id;
      if (h.id === wahl.harness) b.classList.add("gewaehlt");
      b.addEventListener("click", () => {
        if (wahl.harness === h.id) return;
        wahl.harness = h.id;
        const passend = d.modelle.filter((m) => m.harness === h.id);
        wahl.model = passend.some((m) => m.id === wahl.model) ? wahl.model : passend[0]?.id ?? "";
        const stufen2 = d.harnessStufen[h.id] ?? [];
        if (!stufen2.includes(wahl.effort)) wahl.effort = stufen2[stufen2.length - 1] ?? "";
        wahl.kontext = 0;
        wahlSuche = "";
        zeichne();
      });
      harnessReihe.appendChild(b);
    }
    wahlBlockEl.appendChild(wahlZeile(t("wahl.harness"), harnessReihe));
    const eigene = d.modelle.filter((m) => m.harness === wahl.harness);
    const modellKasten = el("div");
    if (eigene.length === 0) {
      modellKasten.appendChild(el("div", "wahlhinweis", t("wahl.keinModell")));
    } else {
      const suchfeld = el("input", "modellsuche");
      suchfeld.type = "text";
      suchfeld.placeholder = t("wahl.platzhalterSuche");
      suchfeld.value = wahlSuche;
      suchfeld.dataset.wahlSuche = "1";
      suchfeld.spellcheck = false;
      suchfeld.addEventListener("input", () => {
        wahlSuche = suchfeld.value;
        zeichne();
        const neu = wahlBlockEl.querySelector('input[data-wahl-suche="1"]');
        if (neu) {
          neu.focus();
          neu.setSelectionRange(neu.value.length, neu.value.length);
        }
      });
      modellKasten.appendChild(suchfeld);
      const suche = wahlSuche.trim().toLowerCase();
      const passt = (m) => !suche || m.label.toLowerCase().includes(suche) || m.id.toLowerCase().includes(suche);
      const dasGewaehlte = eigene.find((m) => m.id === wahl.model);
      const zeigen = [
        ...dasGewaehlte ? [dasGewaehlte] : [],
        ...eigene.filter((m) => m.id !== wahl.model && passt(m))
      ];
      const liste = el("div", "wahlliste");
      if (zeigen.length === 0) liste.appendChild(el("div", "wahlhinweis", t("wahl.keinTreffer")));
      for (const m of zeigen) {
        const z1 = el("div", "zeile1");
        z1.appendChild(el("span", void 0, `${m.id === wahl.model ? "\u25CF " : "\u25CB "}${m.label}`));
        z1.appendChild(el("span", "kennung", m.id));
        const z2 = el("div", "zeile2", m.startbar ? m.harnessLabel : `${m.harnessLabel} \xB7 ${t("wahl.nichtStartbar")}`);
        const b = wahlEintrag(z1, z2, m.id === wahl.model, () => {
          if (wahl.model === m.id) return;
          wahl.model = m.id;
          wahl.kontext = 0;
          zeichne();
        });
        b.dataset.wahlModell = m.id;
        liste.appendChild(b);
      }
      modellKasten.appendChild(liste);
    }
    wahlBlockEl.appendChild(wahlZeile(t("wahl.modell"), modellKasten));
    const stufen = d.harnessStufen[wahl.harness] ?? [];
    if (stufen.length === 0) {
      wahlBlockEl.appendChild(wahlZeile(t("wahl.effort"), el("div", "wahlhinweis", t("wahl.keineStufen"))));
    } else {
      const stufenReihe = el("div", "filterzeile");
      for (const s of stufen) {
        const b = el("button");
        b.type = "button";
        b.textContent = s;
        b.dataset.wahlEffort = s;
        if (s === wahl.effort) b.classList.add("gewaehlt");
        b.addEventListener("click", () => {
          wahl.effort = s;
          zeichne();
        });
        stufenReihe.appendChild(b);
      }
      wahlBlockEl.appendChild(wahlZeile(t("wahl.effort"), stufenReihe));
    }
    const modell = d.modelle.find((m) => m.id === wahl.model);
    if (modell?.lokal) {
      const antwort = kontextStand[modell.id];
      if (!antwort) {
        kontextHolen(modell.id);
        wahlBlockEl.appendChild(wahlZeile(
          t("wahl.kontext"),
          el("div", "wahlhinweis", t("wahl.kontextWirdErmittelt"))
        ));
      } else if (!antwort.ok) {
        wahlBlockEl.appendChild(wahlZeile(
          t("wahl.kontext"),
          el("div", "wahlhinweis", t("wahl.kontextNichtErmittelt", { grund: antwort.fehler }))
        ));
      } else {
        const s = antwort.sicht;
        if (!wahl.kontext) wahl.kontext = s.vorgabe;
        const liste = el("div", "wahlliste");
        for (const stufe of s.stufen) {
          const z1 = el("div", "zeile1");
          z1.appendChild(el(
            "span",
            void 0,
            `${stufe.tokens === wahl.kontext ? "\u25CF " : "\u25CB "}${stufe.label}`
          ));
          if (stufe.tokens === s.empfehlung) {
            z1.appendChild(el("span", "marke", t("wahl.kontextEmpfohlen")));
          }
          z1.appendChild(el("span", "kennung", t("wahl.kontextToken", { tokens: stufe.tokens })));
          const eng = !stufe.passt && !!stufe.hinweis;
          const z2 = el(
            "div",
            eng ? "zeile2 knapp" : "zeile2",
            eng ? String(stufe.hinweis) : t("wahl.kontextBedarf", { bedarf: stufe.bedarfGib.toFixed(1) })
          );
          const b = wahlEintrag(z1, z2, stufe.tokens === wahl.kontext, () => {
            wahl.kontext = stufe.tokens;
            zeichne();
          });
          b.dataset.wahlKontext = String(stufe.tokens);
          b.dataset.passt = stufe.passt ? "ja" : "nein";
          liste.appendChild(b);
        }
        wahlBlockEl.appendChild(wahlZeile(t("wahl.kontext"), liste));
      }
    } else {
      wahlBlockEl.appendChild(wahlZeile(
        t("wahl.kontext"),
        el("div", "wahlhinweis", t("wahl.kontextNurLokal"))
      ));
    }
    const flaggen = wahlFlaggen(modell, stufen);
    const startzeile = el("div", "startzeile");
    const flaggenEl = el("div", "flaggen", flaggen.length ? flaggen.join(" ") : t("wahl.flaggenLeer"));
    flaggenEl.id = "neu-wahl-flaggen";
    startzeile.appendChild(flaggenEl);
    const startKnopf = el("button", "knopf haupt", t("knopf.neuWahlStart"));
    startKnopf.type = "button";
    startKnopf.id = "neu-wahl-start";
    startKnopf.disabled = beschaeftigt || !wahl.model;
    startKnopf.addEventListener("click", (ereignis) => void neueSitzungMitWahl(ereignis.isTrusted));
    startzeile.appendChild(startKnopf);
    wahlBlockEl.appendChild(startzeile);
  }
  function zeichne() {
    if (!daten) return;
    zeichneMaschinenwahl();
    zeichneFernZeile();
    zeichneWahlblock();
    const maschinenChips = chipsAus(
      daten.sitzungen,
      (z) => z.machine,
      (m, n) => `${m} ${n}`,
      (gesamt) => t("wort.alle", { n: gesamt })
    );
    if (!maschinenChips.some((c) => c.wert === maschineFilter)) maschineFilter = "alle";
    zeichneChipZeile(maschineChipsEl, maschinenChips, maschineFilter, (wert) => {
      maschineFilter = wert;
      zeichne();
    });
    const zustandChips = chipsAus(
      daten.sitzungen,
      (z) => z.state,
      (state, n) => `${zustandMarke(state).text} ${n}`,
      (gesamt) => t("wort.alle", { n: gesamt })
    );
    if (!zustandChips.some((c) => c.wert === zustandFilter)) zustandFilter = "alle";
    zeichneChipZeile(zustandChipsEl, zustandChips, zustandFilter, (wert) => {
      zustandFilter = wert;
      zeichne();
    });
    if (suchFeld.value !== sucheWert) suchFeld.value = sucheWert;
    const sichtbareSitzungen = daten.sitzungen.filter(
      (z) => zeilePasstSuche(z, sucheWert) && zeilePasstMaschine(z, maschineFilter) && zeilePasstZustand(z, zustandFilter)
    );
    gruppenEl.textContent = "";
    const gruppen = gruppiere(sichtbareSitzungen);
    for (const g of gruppen) {
      const kasten = el("div", "gruppe");
      kasten.dataset.gruppe = g.schluessel;
      const kopf = el("div", "gruppenkopf");
      kopf.appendChild(el("span", "ordner", ordnerName(g.dir)));
      const pfad = g.machine && g.machine !== daten.machine ? `${g.machine}:${g.dir}` : g.dir;
      kopf.appendChild(el("span", "pfad", pfad));
      if (g.zeilen.length > 1) kopf.appendChild(el("span", "anzahl", t("wort.sitzungenAnzahl", { n: g.zeilen.length })));
      kasten.appendChild(kopf);
      g.zeilen.forEach((z) => kasten.appendChild(zeileBauen(z)));
      gruppenEl.appendChild(kasten);
    }
    if (gruppen.length === 0) {
      gruppenEl.appendChild(el("div", "leerhinweis", t("satz.keineSitzungBekannt")));
    }
    const gewaehlt = daten.sitzungen.find((s) => s.id === gewaehlteSitzung);
    grundEl.textContent = gewaehlt ? gewaehlt.grund : t("satz.waehleSitzung");
    fortKnopf.disabled = beschaeftigt || !gewaehlt || !gewaehlt.fortsetzbar;
    const laeuftGerade = !!gewaehlt && (gewaehlt.state === "running" || gewaehlt.state === "attention");
    beendenKnopf.disabled = beschaeftigt || !laeuftGerade;
    const wechselbar = !!gewaehlt && laeuftGerade && gewaehlt.machine === daten.machine;
    wechselZeile.style.display = wechselbar ? "flex" : "none";
    if (wechselbar && !wahlDaten) wahlHolen();
    const modelle = wechselbar && wahlDaten ? wahlDaten.modelle.filter((m) => m.harness === gewaehlt.harness && m.startbar && m.wechselbar) : [];
    if (!modelle.some((m) => m.id === wechselModell)) {
      wechselModell = modelle.some((m) => m.id === gewaehlt?.model) ? gewaehlt?.model ?? "" : modelle[0]?.id ?? "";
    }
    wechselAuswahl.textContent = "";
    for (const m of modelle) {
      const o = document.createElement("option");
      o.value = m.id;
      o.textContent = `${m.label} \xB7 ${m.id}`;
      o.selected = m.id === wechselModell;
      wechselAuswahl.appendChild(o);
    }
    wechselKnopf.disabled = beschaeftigt || !wechselModell || wechselModell === gewaehlt?.model;
    neuKnopf.disabled = beschaeftigt;
    neuChatKnopf.disabled = beschaeftigt;
    if (nameFeld.value !== nameWert) nameFeld.value = nameWert;
  }
  async function neueSitzung(echt) {
    if (beschaeftigt) return;
    if (daten && maschineWert !== daten.machine && !fernPfadWert.trim()) {
      melde(t("satz.erstOrdnerEintragen", { maschine: maschineWert }), "fehler");
      return;
    }
    beschaeftigt = true;
    zeichne();
    try {
      const a = await window.awbSitzung.neu(nameWert, maschineWert, fernPfadWert, echt);
      melde(a.command ? `${a.meldung}
${a.command}` : a.meldung, a.ok ? "gut" : "fehler");
      if (a.ok) {
        nameWert = "";
        fernPfadWert = "";
      }
    } catch (e) {
      melde(String(e.message ?? e), "fehler");
    } finally {
      beschaeftigt = false;
      zeichne();
    }
  }
  async function neueSitzungMitWahl(echt) {
    if (beschaeftigt) return;
    if (daten && maschineWert !== daten.machine && !fernPfadWert.trim()) {
      melde(t("satz.erstOrdnerEintragen", { maschine: maschineWert }), "fehler");
      return;
    }
    const modell = wahlDaten?.modelle.find((m) => m.id === wahl.model);
    const stufen = wahlDaten?.harnessStufen[wahl.harness] ?? [];
    const mit = {
      harness: wahl.harness,
      model: wahl.model,
      effort: stufen.includes(wahl.effort) ? wahl.effort : "",
      kontext: modell?.lokal ? wahl.kontext : 0
    };
    beschaeftigt = true;
    zeichne();
    try {
      const a = await window.awbSitzung.neuMitWahl(nameWert, maschineWert, fernPfadWert, mit, echt);
      melde(a.command ? `${a.meldung}
${a.command}` : a.meldung, a.ok ? "gut" : "fehler");
      if (a.ok) {
        nameWert = "";
        fernPfadWert = "";
        wahlOffen = false;
        wahlDaten = null;
        wahlVersucht = false;
        wahl.harness = "";
        wahl.model = "";
        wahl.effort = "";
        wahl.kontext = 0;
        wahlSuche = "";
      }
    } catch (e) {
      melde(String(e.message ?? e), "fehler");
    } finally {
      beschaeftigt = false;
      zeichne();
    }
  }
  async function neueChatSitzung(echt) {
    if (beschaeftigt) return;
    beschaeftigt = true;
    zeichne();
    try {
      const a = await window.awbSitzung.neuChat(nameWert, echt);
      melde(a.meldung, a.ok ? "gut" : "fehler");
      if (a.ok) nameWert = "";
    } catch (e) {
      melde(String(e.message ?? e), "fehler");
    } finally {
      beschaeftigt = false;
      zeichne();
    }
  }
  async function fernPruefen() {
    if (fernPrueftGerade || !daten || maschineWert === daten.machine) return;
    const pfad = fernPfadWert.trim();
    if (!pfad) {
      fernStatus = t("satz.erstPfadEintragen");
      fernStatusArt = "fehler";
      zeichne();
      return;
    }
    fernPrueftGerade = true;
    fernStatus = t("satz.pruefeGerade");
    fernStatusArt = "";
    zeichne();
    try {
      const a = await window.awbSitzung.fernPruefen(maschineWert, pfad);
      fernStatus = a.meldung;
      fernStatusArt = a.ok ? "gut" : "fehler";
    } catch (e) {
      fernStatus = String(e.message ?? e);
      fernStatusArt = "fehler";
    } finally {
      fernPrueftGerade = false;
      zeichne();
    }
  }
  async function setzeFort(id, echt) {
    if (beschaeftigt || !id) return;
    beschaeftigt = true;
    zeichne();
    melde(t("satz.holeZurueck"));
    try {
      const a = await window.awbSitzung.fortsetzen(id, echt);
      melde(a.command ? `${a.meldung}
${a.command}` : a.meldung, a.ok ? "gut" : "fehler");
    } catch (e) {
      melde(String(e.message ?? e), "fehler");
    } finally {
      beschaeftigt = false;
      zeichne();
    }
  }
  async function sitzungBeenden(id, echt) {
    if (beschaeftigt || !id) return;
    beschaeftigt = true;
    zeichne();
    try {
      const a = await window.awbSitzung.beenden(id, echt);
      melde(a.command ? `${a.meldung}
${a.command}` : a.meldung, a.ok ? "gut" : "fehler");
    } catch (e) {
      melde(String(e.message ?? e), "fehler");
    } finally {
      beschaeftigt = false;
      zeichne();
    }
  }
  async function modellWechseln(id, echt) {
    if (beschaeftigt || !id || !wechselModell) return;
    beschaeftigt = true;
    zeichne();
    try {
      const a = await window.awbSitzung.modellWechseln(id, wechselModell, "", echt);
      melde(a.command ? `${a.meldung}
${a.command}` : a.meldung, a.ok ? "gut" : "fehler");
    } catch (e) {
      melde(String(e.message ?? e), "fehler");
    } finally {
      beschaeftigt = false;
      zeichne();
    }
  }
  nameFeld.addEventListener("input", () => {
    nameWert = nameFeld.value;
  });
  fernPfadFeld.addEventListener("input", () => {
    fernPfadWert = fernPfadFeld.value;
  });
  var sucheZeichnenUhr;
  suchFeld.addEventListener("input", () => {
    sucheWert = suchFeld.value;
    if (sucheZeichnenUhr !== void 0) clearTimeout(sucheZeichnenUhr);
    sucheZeichnenUhr = setTimeout(() => {
      sucheZeichnenUhr = void 0;
      zeichne();
    }, 150);
  });
  neuKnopf.addEventListener("click", (ereignis) => void neueSitzung(ereignis.isTrusted));
  neuChatKnopf.addEventListener("click", (ereignis) => void neueChatSitzung(ereignis.isTrusted));
  neuWahlKnopf.addEventListener("click", () => {
    if (beschaeftigt) return;
    wahlOffen = !wahlOffen;
    zeichne();
  });
  fernPruefenKnopf.addEventListener("click", () => void fernPruefen());
  fortKnopf.addEventListener("click", (ereignis) => void setzeFort(gewaehlteSitzung, ereignis.isTrusted));
  beendenKnopf.addEventListener("click", (ereignis) => void sitzungBeenden(gewaehlteSitzung, ereignis.isTrusted));
  wechselAuswahl.addEventListener("change", () => {
    wechselModell = wechselAuswahl.value;
    zeichne();
  });
  wechselKnopf.addEventListener("click", (ereignis) => void modellWechseln(gewaehlteSitzung, ereignis.isTrusted));
  window.__awbSitzung = {
    text: () => document.body.innerText,
    status: () => statusEl.textContent ?? "",
    klick: (auswahl) => {
      const e = document.querySelector(auswahl);
      if (!e) return false;
      e.click();
      return true;
    },
    // Lesen statt klicken. Ohne diesen Haken liesse sich "der Knopf ist gesperrt"
    // nur pruefen, indem man ihn drueckt -- und damit ausloest.
    zustand: (auswahl) => {
      const e = document.querySelector(auswahl);
      if (!e) return { da: false, gesperrt: false, wert: "", text: "", optionen: [], angezeigt: false };
      const i = e;
      const mitOptionen = e;
      const optionen = mitOptionen.options ? [...mitOptionen.options].map((o) => o.value) : [];
      const angezeigt = getComputedStyle(e).display !== "none" && e.getBoundingClientRect().height > 0;
      return {
        da: true,
        gesperrt: i.disabled === true,
        wert: typeof i.value === "string" ? i.value : "",
        text: (e.innerText ?? "").replace(/\s+/g, " ").trim(),
        optionen,
        angezeigt
      };
    },
    gruppen: () => [...gruppenEl.querySelectorAll(".gruppe")].map((g) => {
      const schluessel = g.dataset.gruppe ?? "";
      const sichtbar = [...g.querySelectorAll(".listenzeile")].map((z) => z.dataset.sitzung ?? "");
      const alle = daten?.sitzungen.filter((s) => `${s.machine} ${s.dir}` === schluessel).length ?? sichtbar.length;
      return {
        schluessel,
        kopf: (g.querySelector(".gruppenkopf")?.innerText ?? "").replace(/\s+/g, " ").trim(),
        sichtbar,
        // Bekannt minus gezeichnet. Steht hier etwas anderes als 0, verschweigt
        // das Fenster eine Sitzung -- genau der Fehler vom 11.08.
        verborgen: alle - sichtbar.length
      };
    }),
    sitzungen: () => [...gruppenEl.querySelectorAll(".listenzeile")].map((b) => ({
      id: b.dataset.sitzung ?? "",
      text: b.innerText.replace(/\s+/g, " ").trim(),
      gewaehlt: b.classList.contains("gewaehlt"),
      fortsetzbar: b.dataset.fortsetzbar === "1"
    }))
  };
  window.awbSitzung.onStartfehler((p) => {
    const zeilen = [p.kurz || "Die Sitzung ist nicht gestartet.", p.grund, `Protokoll: ${p.protokoll}`];
    melde(zeilen.filter(Boolean).join("\n"), "fehler");
  });
  window.awbSitzung.onDaten((d) => {
    daten = d;
    setzeSprache(d.sprache);
    beschriften();
    if (gewaehlteSitzung && !d.sitzungen.some((s) => s.id === gewaehlteSitzung)) gewaehlteSitzung = "";
    zeichne();
  });
  window.awbSitzung.onWahl((d) => {
    wahlDaten = d;
    wahlFehler = "";
    wahlVersucht = true;
    if (!wahl.harness) wahl.harness = d.einstellung.harness;
    if (!wahl.model) wahl.model = d.einstellung.model;
    if (!wahl.effort) wahl.effort = d.einstellung.effort;
    if (!wahl.kontext) wahl.kontext = d.einstellung.kontext;
    zeichne();
  });
  void (async () => {
    daten = await window.awbSitzung.daten();
    setzeSprache(daten.sprache);
    beschriften();
    zeichne();
    window.awbSitzung.bereit();
  })();
})();
