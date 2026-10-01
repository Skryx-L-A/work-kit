"use strict";
(() => {
  // src/erststart/ablauf.ts
  var SCHRITTE = ["harness", "modell", "fertig"];
  var SCHLUESSEL = {
    maschine: "defaultWorkerMachine",
    harness: "orchestratorHarness",
    modell: "orchestratorModel",
    kontext: "orchestratorKontext"
  };
  var ERLEDIGT_SCHLUESSEL = "erststartErledigt";
  function anfang() {
    return { index: 0, antworten: {}, abgeschlossen: false };
  }
  function schrittName(z) {
    return SCHRITTE[Math.min(z.index, SCHRITTE.length - 1)];
  }
  function fortschritt(z, antwort) {
    if (z.abgeschlossen) return { zustand: z, schreibungen: [] };
    const name = schrittName(z);
    if (name === "fertig") {
      const schreibungen = [];
      for (const schritt of Object.keys(SCHLUESSEL)) {
        const wert = z.antworten[schritt];
        if (wert !== void 0) schreibungen.push({ key: SCHLUESSEL[schritt], value: wert });
      }
      schreibungen.push({ key: ERLEDIGT_SCHLUESSEL, value: true });
      return { zustand: { ...z, abgeschlossen: true }, schreibungen };
    }
    const antworten = antwort !== void 0 ? { ...z.antworten, [name]: antwort } : z.antworten;
    return { zustand: { index: z.index + 1, antworten, abgeschlossen: false }, schreibungen: [] };
  }
  function weiter(z, antwort) {
    return fortschritt(z, antwort);
  }
  function ueberspringen(z) {
    return fortschritt(z, void 0);
  }
  function mitKontext(z, tokens) {
    if (z.abgeschlossen) return z;
    const antworten = { ...z.antworten };
    if (tokens > 0) antworten.kontext = tokens;
    else delete antworten.kontext;
    return { ...z, antworten };
  }

  // src/erststart/texte.ts
  var DE = {
    "fenster.titel": "Agent-Workbench \u2013 Erste Schritte",
    "kopf.titel": "Erste Schritte",
    "kopf.unterzeile": "Drei kurze Schritte, jeder \xFCberspringbar. Alles andere bleibt auf Vorgabe und l\xE4sst sich sp\xE4ter in den Einstellungen \xE4ndern.",
    // --- Fortschritt ------------------------------------------------------
    "fortschritt.schritt": "Schritt {0} von {1}",
    // --- Knöpfe -------------------------------------------------------------
    "knopf.weiter": "Weiter",
    "knopf.ueberspringen": "\xDCberspringen",
    "knopf.fertig": "Fertig",
    // --- Schritt 1: Maschine -------------------------------------------------
    "maschine.titel": "Maschine",
    "maschine.unterzeile": "Auf welcher Maschine sollen Worker standardm\xE4\xDFig laufen?",
    "maschine.nurEine": "Auf diesem Rechner ist bisher keine weitere Maschine eingerichtet \u2013 es bleibt bei \u201Ediese Maschine\u201C. Weitere Maschinen lassen sich sp\xE4ter \xFCber die Seite \u201EMaschinen\u201C hinzuf\xFCgen.",
    "maschine.diese": "diese Maschine ({0})",
    // --- Schritt 2: Harness ---------------------------------------------------
    "harness.titel": "Harness anmelden",
    "harness.unterzeile": "Mit welchem Programm soll der Orchestrator arbeiten? Die Anmeldung selbst l\xE4uft au\xDFerhalb dieses Fensters, im Terminal des jeweiligen Programms.",
    "harness.stand.ja": "angemeldet",
    "harness.stand.nein": "nicht angemeldet",
    "harness.stand.unbekannt": "nicht pr\xFCfbar",
    "harness.zeichen.ja": "\u25CF",
    "harness.zeichen.nein": "\u2715",
    "harness.zeichen.unbekannt": "\u2013",
    "harness.keine": "Auf dieser Maschine ist kein startbares Programm gefunden. Dieser Schritt l\xE4sst sich sp\xE4ter \xFCber die Seite \u201EProgramme und Modelle\u201C nachholen.",
    // --- Schritt 3: Modell -----------------------------------------------------
    "modell.titel": "Modell",
    "modell.unterzeile": "Welches Modell soll der Orchestrator verwenden?",
    "modell.keine": "F\xFCr das gew\xE4hlte Programm ist noch kein Modell bekannt. Dieser Schritt l\xE4sst sich sp\xE4ter \xFCber die Seite \u201EProgramme und Modelle\u201C nachholen.",
    // --- Schritt 3, zweite Frage: das Kontextfenster ---------------------------
    // Sie steht nur da, wenn das gewählte Modell auf dieser Maschine läuft.
    "kontext.titel": "Kontextfenster",
    "kontext.unterzeile": "Wie viel Text dieses Modell gleichzeitig im Kopf beh\xE4lt. Ein gr\xF6\xDFeres Fenster h\xE4lt mehr Zusammenhang und belegt dauerhaft mehr Grafikspeicher. W\xE4hlbar ist jede Stufe \u2013 auch eine, f\xFCr die der Speicher gerade nicht reicht; sie sagt es dann dazu.",
    "kontext.empfohlen": "empfohlen",
    "kontext.token": "{0} Token",
    "kontext.bedarf": "Braucht {0} GiB.",
    "kontext.wirdErmittelt": "Die Stufen werden ermittelt \u2026",
    "kontext.nichtErmittelt": "Die Stufen lie\xDFen sich nicht ermitteln: {0}. Das Fenster bleibt dann bei dem, was f\xFCr dieses Modell eingetragen ist; \xE4ndern l\xE4sst es sich sp\xE4ter in den Einstellungen.",
    // --- Schritt 4: Fertig -----------------------------------------------------
    "fertig.titel": "Fertig",
    "fertig.unterzeile": "Das war\u2019s \u2013 alles andere bleibt auf Vorgabe.",
    "fertig.satz.gesetzt": "Gesetzt: {0}.",
    "fertig.satz.nichtsGesetzt": "Es wurde nichts ge\xE4ndert \u2013 alles bleibt auf Vorgabe.",
    "fertig.satz.aendernWo": "\xC4ndern l\xE4sst sich das jederzeit \xFCber die Einstellungen, Seiten \u201EProgramme und Modelle\u201C und \u201EMaschinen\u201C.",
    "fertig.eintrag.maschine": "Maschine \u201E{0}\u201C",
    "fertig.eintrag.harness": "Programm \u201E{0}\u201C",
    "fertig.eintrag.modell": "Modell \u201E{0}\u201C",
    "fertig.eintrag.kontext": "Kontextfenster {0} Token",
    // --- Zustandszeichen (keine Emojis) --------------------------------------
    "zeichen.gewaehlt": "\u25CF",
    "zeichen.wahl": "\u25CB"
  };
  var EN = {
    "fenster.titel": "Agent Workbench \u2014 First Steps",
    "kopf.titel": "First Steps",
    "kopf.unterzeile": "Three short steps, each skippable. Everything else stays at its default and can be changed later in Settings.",
    // --- Progress ------------------------------------------------------
    "fortschritt.schritt": "Step {0} of {1}",
    // --- Buttons -------------------------------------------------------------
    "knopf.weiter": "Next",
    "knopf.ueberspringen": "Skip",
    "knopf.fertig": "Done",
    // --- Step 1: Machine -------------------------------------------------
    "maschine.titel": "Machine",
    "maschine.unterzeile": "Which machine should workers run on by default?",
    "maschine.nurEine": 'No other machine is set up on this computer yet \u2014 it stays at "this machine". Further machines can be added later on the "Machines" page.',
    "maschine.diese": "this machine ({0})",
    // --- Step 2: Harness ---------------------------------------------------
    "harness.titel": "Sign in a harness",
    "harness.unterzeile": "Which program should the orchestrator work with? Signing in itself happens outside this window, in that program's own terminal.",
    "harness.stand.ja": "signed in",
    "harness.stand.nein": "not signed in",
    "harness.stand.unbekannt": "not checkable",
    "harness.zeichen.ja": "\u25CF",
    "harness.zeichen.nein": "\u2715",
    "harness.zeichen.unbekannt": "\u2013",
    "harness.keine": 'No startable program was found on this machine. This step can be caught up later on the "Programs and models" page.',
    // --- Step 3: Model -----------------------------------------------------
    "modell.titel": "Model",
    "modell.unterzeile": "Which model should the orchestrator use?",
    "modell.keine": 'No model is known yet for the chosen program. This step can be caught up later on the "Programs and models" page.',
    // --- Step 3, second question: the context window ---------------------------
    "kontext.titel": "Context window",
    "kontext.unterzeile": "How much text this model keeps in mind at once. A larger window holds more context and permanently occupies more GPU memory. Every level is selectable \u2014 including one the memory does not cover right now; it says so.",
    "kontext.empfohlen": "recommended",
    "kontext.token": "{0} tokens",
    "kontext.bedarf": "Needs {0} GiB.",
    "kontext.wirdErmittelt": "Determining the levels \u2026",
    "kontext.nichtErmittelt": "The levels could not be determined: {0}. The window then stays at whatever is registered for this model; it can be changed later in Settings.",
    // --- Step 4: Done -----------------------------------------------------
    "fertig.titel": "Done",
    "fertig.unterzeile": "That's it \u2014 everything else stays at its default.",
    "fertig.satz.gesetzt": "Set: {0}.",
    "fertig.satz.nichtsGesetzt": "Nothing was changed \u2014 everything stays at its default.",
    "fertig.satz.aendernWo": 'This can be changed at any time via Settings, on the "Programs and models" and "Machines" pages.',
    "fertig.eintrag.maschine": 'Machine "{0}"',
    "fertig.eintrag.harness": 'Program "{0}"',
    "fertig.eintrag.modell": 'Model "{0}"',
    "fertig.eintrag.kontext": "Context window {0} tokens",
    // --- State marks (no emoji) --------------------------------
    "zeichen.gewaehlt": "\u25CF",
    "zeichen.wahl": "\u25CB"
  };
  var TABELLEN = { de: DE, en: EN };
  var aktuelleSprache = "en";
  function setzeSprache(s) {
    aktuelleSprache = s === "de" ? "de" : "en";
  }
  function sprache() {
    return aktuelleSprache;
  }
  function t(schluessel, ...werte) {
    const tabelle = TABELLEN[aktuelleSprache] ?? DE;
    const roh = tabelle[schluessel] ?? DE[schluessel];
    if (roh === void 0) return `[${schluessel}]`;
    return roh.replace(/\{(\d+)\}/g, (treffer, nr) => {
      const w = werte[Number(nr)];
      return w === void 0 ? treffer : String(w);
    });
  }

  // src/erststart/erststart.ts
  function el(tag, klasse, text) {
    const e = document.createElement(tag);
    if (klasse) e.className = klasse;
    if (text !== void 0) e.textContent = text;
    return e;
  }
  var titelEl = document.getElementById("titel");
  var kopfUnterzeileEl = document.getElementById("kopf-unterzeile");
  var fortschrittEl = document.getElementById("fortschritt");
  var inhaltEl = document.getElementById("inhalt");
  var weiterKnopf = document.getElementById("knopf-weiter");
  var ueberspringenKnopf = document.getElementById("knopf-ueberspringen");
  function kopfzeileBeschriften() {
    document.documentElement.lang = sprache();
    document.title = t("fenster.titel");
    titelEl.textContent = t("kopf.titel");
    kopfUnterzeileEl.textContent = t("kopf.unterzeile");
  }
  var zustand = anfang();
  var daten = null;
  var laufendeWahl = "";
  function schreibungenAusfuehren(schreibungen) {
    return schreibungen.reduce(
      (p, s) => p.then(() => window.awbErststart.setzen(s.key, s.value)).then(() => void 0),
      Promise.resolve()
    );
  }
  function weiterKlick() {
    const { zustand: neu, schreibungen } = weiter(zustand, laufendeWahl);
    zustand = neu;
    void schreibungenAusfuehren(schreibungen).then(() => {
      if (zustand.abgeschlossen) window.close();
      else zeichnen();
    });
  }
  function ueberspringenKlick() {
    const { zustand: neu, schreibungen } = ueberspringen(zustand);
    zustand = neu;
    void schreibungenAusfuehren(schreibungen).then(() => {
      if (zustand.abgeschlossen) window.close();
      else zeichnen();
    });
  }
  weiterKnopf.addEventListener("click", weiterKlick);
  ueberspringenKnopf.addEventListener("click", ueberspringenKlick);
  function chipReihe(eintraege, vorbelegung, onWahl) {
    laufendeWahl = eintraege.some((e) => e.wert === vorbelegung) ? vorbelegung : eintraege[0]?.wert ?? "";
    const reihe = el("div", "chips");
    for (const eintrag of eintraege) {
      const knopf = el("button", "chip");
      knopf.type = "button";
      if (eintrag.zeichen) {
        const z = el("span", `zeichen ${eintrag.zeichenKlasse ?? ""}`.trim(), eintrag.zeichen);
        knopf.appendChild(z);
      }
      knopf.appendChild(document.createTextNode(eintrag.label));
      if (eintrag.wert === laufendeWahl) knopf.classList.add("gewaehlt");
      knopf.addEventListener("click", () => {
        laufendeWahl = eintrag.wert;
        for (const k of reihe.querySelectorAll(".chip")) k.classList.remove("gewaehlt");
        knopf.classList.add("gewaehlt");
        onWahl?.(eintrag.wert);
      });
      reihe.appendChild(knopf);
    }
    return reihe;
  }
  function harnessZeichen(stand) {
    if (stand === "ja") return { zeichen: t("harness.zeichen.ja"), klasse: "ja" };
    if (stand === "nein") return { zeichen: t("harness.zeichen.nein"), klasse: "nein" };
    return { zeichen: t("harness.zeichen.unbekannt"), klasse: "" };
  }
  function schrittMaschine(d) {
    const frag = document.createDocumentFragment();
    frag.appendChild(el("h2", void 0, t("maschine.titel")));
    frag.appendChild(el("p", "unterzeile", t("maschine.unterzeile")));
    const alle = ["local", ...d.maschinen];
    if (d.maschinen.length === 0) {
      frag.appendChild(el("p", "hinweis", t("maschine.nurEine", d.machine)));
      laufendeWahl = "local";
    } else {
      const eintraege = alle.map((m) => ({
        wert: m,
        label: m === "local" ? t("maschine.diese", d.machine) : m
      }));
      frag.appendChild(chipReihe(eintraege, d.settings.defaultWorkerMachine || d.vorgaben.defaultWorkerMachine));
    }
    return frag;
  }
  function schrittHarness(d) {
    const frag = document.createDocumentFragment();
    frag.appendChild(el("h2", void 0, t("harness.titel")));
    frag.appendChild(el("p", "unterzeile", t("harness.unterzeile")));
    if (d.harnesses.length === 0) {
      frag.appendChild(el("p", "hinweis", t("harness.keine")));
      return frag;
    }
    const eintraege = d.harnesses.map((h) => {
      const a = d.anmeldung[h.id];
      const z = harnessZeichen(a?.stand ?? "unbekannt");
      return { wert: h.id, label: h.label, zeichen: z.zeichen, zeichenKlasse: z.klasse };
    });
    const vorbelegung = d.settings.orchestratorHarness || d.vorgaben.orchestratorHarness;
    const grundEl = el("p", "grund");
    const grundSetzen = (harnessId) => {
      grundEl.textContent = d.anmeldung[harnessId]?.grund ?? "";
    };
    frag.appendChild(chipReihe(eintraege, vorbelegung, grundSetzen));
    grundSetzen(laufendeWahl);
    frag.appendChild(grundEl);
    return frag;
  }
  var kontextStand = {};
  var kontextLaeuft = /* @__PURE__ */ new Set();
  var kontextKasten = null;
  function kontextFuellen(wahl, modelle) {
    const modellId = modelle.find((m) => m.familie === wahl)?.id ?? wahl;
    const kasten = kontextKasten;
    if (!kasten) return;
    kasten.textContent = "";
    const modell = modelle.find((m) => m.id === modellId);
    if (!modell?.lokal) {
      zustand = mitKontext(zustand, 0);
      return;
    }
    const antwort = kontextStand[modellId];
    if (!antwort) {
      kasten.appendChild(el("p", "hinweis", t("kontext.wirdErmittelt")));
      if (!kontextLaeuft.has(modellId)) {
        kontextLaeuft.add(modellId);
        void window.awbErststart.kontextStufen(modellId).then((a) => {
          kontextStand[modellId] = a;
        }).catch((e) => {
          kontextStand[modellId] = { ok: false, fehler: String(e) };
        }).then(() => {
          kontextLaeuft.delete(modellId);
          if (laufendeWahl === modellId) kontextFuellen(modellId, modelle);
        });
      }
      return;
    }
    if (!antwort.ok) {
      kasten.appendChild(el("p", "hinweis", t("kontext.nichtErmittelt", antwort.fehler)));
      zustand = mitKontext(zustand, 0);
      return;
    }
    const s = antwort.sicht;
    const bisher = zustand.antworten.kontext;
    const wert = typeof bisher === "number" && s.stufen.some((x) => x.tokens === bisher) ? bisher : s.vorgabe;
    zustand = mitKontext(zustand, wert);
    kasten.appendChild(el("h3", void 0, t("kontext.titel")));
    kasten.appendChild(el("p", "unterzeile", t("kontext.unterzeile")));
    const liste = el("div", "kontextliste");
    for (const stufe of s.stufen) {
      const b = el("button", "kontexteintrag");
      b.type = "button";
      b.dataset.kontext = String(stufe.tokens);
      b.dataset.passt = stufe.passt ? "ja" : "nein";
      if (stufe.tokens === (zustand.antworten.kontext ?? s.vorgabe)) b.classList.add("gewaehlt");
      const z1 = el("div", "zeile1");
      z1.appendChild(el("span", void 0, stufe.label));
      if (stufe.tokens === s.empfehlung) {
        b.dataset.empfohlen = "ja";
        z1.appendChild(el("span", "marke", t("kontext.empfohlen")));
      }
      z1.appendChild(el("span", "kennung", t("kontext.token", stufe.tokens)));
      b.appendChild(z1);
      const eng = !stufe.passt && !!stufe.hinweis;
      const z2 = el("div", eng ? "zeile2 kontexthinweis" : "zeile2");
      z2.textContent = eng ? String(stufe.hinweis) : t("kontext.bedarf", stufe.bedarfGib.toFixed(1));
      b.appendChild(z2);
      b.addEventListener("click", () => {
        zustand = mitKontext(zustand, stufe.tokens);
        kontextFuellen(modellId, modelle);
      });
      liste.appendChild(b);
    }
    kasten.appendChild(liste);
  }
  function schrittModell(d) {
    const frag = document.createDocumentFragment();
    frag.appendChild(el("h2", void 0, t("modell.titel")));
    frag.appendChild(el("p", "unterzeile", t("modell.unterzeile")));
    const harness = String(
      zustand.antworten.harness || d.settings.orchestratorHarness || d.vorgaben.orchestratorHarness
    );
    const modelle = d.orchestratorModelle.filter((m) => m.harness === harness);
    kontextKasten = null;
    if (modelle.length === 0) {
      frag.appendChild(el("p", "hinweis", t("modell.keine")));
      return frag;
    }
    const eintraege = modelle.map((m) => ({ wert: m.familie || m.id, label: m.label }));
    const vorbelegt = d.settings.orchestratorModel || d.vorgaben.orchestratorModel;
    frag.appendChild(chipReihe(
      eintraege,
      modelle.find((m) => m.id === vorbelegt && m.familie)?.familie ?? vorbelegt,
      (wert) => kontextFuellen(wert, modelle)
    ));
    const kasten = el("div", "kontextblock");
    frag.appendChild(kasten);
    kontextKasten = kasten;
    kontextFuellen(laufendeWahl, modelle);
    return frag;
  }
  var FERTIG_LABEL = {
    maschine: "fertig.eintrag.maschine",
    harness: "fertig.eintrag.harness",
    modell: "fertig.eintrag.modell",
    kontext: "fertig.eintrag.kontext"
  };
  function modellAnzeige(wert) {
    const m = daten?.orchestratorModelle.find((z) => z.familie === wert);
    return m ? `${wert} (${m.label})` : wert;
  }
  function schrittFertig() {
    const frag = document.createDocumentFragment();
    frag.appendChild(el("h2", void 0, t("fertig.titel")));
    frag.appendChild(el("p", "unterzeile", t("fertig.unterzeile")));
    const eintraege = Object.keys(zustand.antworten).filter((k) => zustand.antworten[k] !== void 0).map((k) => t(FERTIG_LABEL[k], k === "modell" ? modellAnzeige(String(zustand.antworten[k])) : String(zustand.antworten[k])));
    if (eintraege.length === 0) {
      frag.appendChild(el("p", void 0, t("fertig.satz.nichtsGesetzt")));
    } else {
      frag.appendChild(el("p", void 0, t("fertig.satz.gesetzt", eintraege.join(", "))));
    }
    frag.appendChild(el("p", "hinweis", t("fertig.satz.aendernWo")));
    return frag;
  }
  function zeichnen() {
    if (!daten) return;
    inhaltEl.textContent = "";
    const name = schrittName(zustand);
    const index = SCHRITTE.indexOf(name);
    fortschrittEl.textContent = t("fortschritt.schritt", index + 1, SCHRITTE.length);
    if (name === "maschine") inhaltEl.appendChild(schrittMaschine(daten));
    else if (name === "harness") inhaltEl.appendChild(schrittHarness(daten));
    else if (name === "modell") inhaltEl.appendChild(schrittModell(daten));
    else inhaltEl.appendChild(schrittFertig());
    if (name === "fertig") {
      weiterKnopf.textContent = t("knopf.fertig");
      ueberspringenKnopf.style.display = "none";
    } else {
      weiterKnopf.textContent = t("knopf.weiter");
      ueberspringenKnopf.style.display = "";
      ueberspringenKnopf.textContent = t("knopf.ueberspringen");
    }
  }
  function themaAnwenden(d) {
    document.documentElement.dataset.thema = d.wirksam;
  }
  window.awbErststart.onThema(themaAnwenden);
  void window.awbErststart.thema().then(themaAnwenden);
  void window.awbErststart.daten().then((d) => {
    daten = d;
    setzeSprache(d.sprache);
    kopfzeileBeschriften();
    zeichnen();
    window.awbErststart.bereit();
  });
})();
