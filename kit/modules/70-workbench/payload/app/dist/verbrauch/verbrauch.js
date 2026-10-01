"use strict";
(() => {
  // src/gemeinsam/umlaute.ts
  var UMSCHRIFT = {
    // Aus `wb-budget` (Stand 03.09.2026).
    Abstaende: "Abst\xE4nde",
    Abstaenden: "Abst\xE4nden",
    Aufloesung: "Aufl\xF6sung",
    DARUEBER: "DAR\xDCBER",
    Datensaetze: "Datens\xE4tze",
    Faehigkeit: "F\xE4higkeit",
    Fuehrt: "F\xFChrt",
    Luecken: "L\xFCcken",
    Naeherung: "N\xE4herung",
    Punktemassstab: "Punktema\xDFstab",
    Stueck: "St\xFCck",
    aehnlicher: "\xE4hnlicher",
    annaehernd: "ann\xE4hernd",
    aussen: "au\xDFen",
    ausserhalb: "au\xDFerhalb",
    beruecksichtigt: "ber\xFCcksichtigt",
    bestaetigt: "best\xE4tigt",
    binaer: "bin\xE4r",
    braeuchte: "br\xE4uchte",
    einschliessen: "einschlie\xDFen",
    frueh: "fr\xFCh",
    Erschoepft: "Ersch\xF6pft",
    erschoepft: "ersch\xF6pft",
    Rueckfall: "R\xFCckfall",
    fuer: "f\xFCr",
    gehoeren: "geh\xF6ren",
    geoeffnet: "ge\xF6ffnet",
    gueltig: "g\xFCltig",
    heisst: "hei\xDFt",
    koennen: "k\xF6nnen",
    loesbar: "l\xF6sbar",
    mitgezaehlt: "mitgez\xE4hlt",
    moeglich: "m\xF6glich",
    oeffnen: "\xF6ffnen",
    pruefbar: "pr\xFCfbar",
    geprueft: "gepr\xFCft",
    singulaer: "singul\xE4r",
    spaet: "sp\xE4t",
    traegt: "tr\xE4gt",
    ueber: "\xFCber",
    uebersprungen: "\xFCbersprungen",
    unabhaengig: "unabh\xE4ngig",
    ungeklaert: "ungekl\xE4rt",
    ungeprueft: "ungepr\xFCft",
    verfuegbar: "verf\xFCgbar",
    waehrend: "w\xE4hrend",
    widerspruechlich: "widerspr\xFCchlich",
    wuerde: "w\xFCrde",
    zaehlt: "z\xE4hlt",
    zaehlen: "z\xE4hlen",
    // Aus `shell/models.default.json`, aus den Feldern, die das
    // Einstellungsfenster wirklich zeigt: der Name eines Programms, der Grund
    // gegen eine Chat-Ansicht, was eine Ansicht nicht zeigt, und die Herkunft
    // eines Vorhersage-Weges samt seiner Beschriftung (Stand 03.09.2026).
    FUER: "F\xDCR",
    Buendelung: "B\xFCndelung",
    Endgueltiger: "Endg\xFCltiger",
    GUETE: "G\xDCTE",
    Guete: "G\xFCte",
    Guetefassung: "G\xFCtefassung",
    KOERPER: "K\xD6RPER",
    Koerper: "K\xF6rper",
    Koerpern: "K\xF6rpern",
    Laenge: "L\xE4nge",
    Massgeblich: "Ma\xDFgeblich",
    Modellkoerper: "Modellk\xF6rper",
    Moeglichkeit: "M\xF6glichkeit",
    NEBENLAEUFIGKEIT: "NEBENL\xC4UFIGKEIT",
    Pruefung: "Pr\xFCfung",
    Schlaegt: "Schl\xE4gt",
    Stroeme: "Str\xF6me",
    ausdruecklich: "ausdr\xFCcklich",
    dafuer: "daf\xFCr",
    darueber: "dar\xFCber",
    eigenstaendigen: "eigenst\xE4ndigen",
    erfuellten: "erf\xFCllten",
    faellt: "f\xE4llt",
    gebuendelte: "geb\xFCndelte",
    gegenueber: "gegen\xFCber",
    gewoehnlichen: "gew\xF6hnlichen",
    haelt: "h\xE4lt",
    haengt: "h\xE4ngt",
    hoehere: "h\xF6here",
    laedt: "l\xE4dt",
    laege: "l\xE4ge",
    laeuft: "l\xE4uft",
    liesse: "lie\xDFe",
    ungepruefte: "ungepr\xFCfte",
    waehlbare: "w\xE4hlbare",
    waehlt: "w\xE4hlt",
    waere: "w\xE4re"
  };
  function umlaute(text) {
    if (!text) return text;
    return text.replace(/[A-Za-z]+/g, (w) => UMSCHRIFT[w] ?? w);
  }

  // src/verbrauch/rechnen.ts
  var ARTEN = ["input", "output", "cache_write", "cache_read", "reasoning"];
  function leereWerte() {
    return { input: 0, output: 0, cache_write: 0, cache_read: 0, reasoning: 0, nachrichten: 0, ohne_cache_read: 0 };
  }
  function ohneCacheRead(w) {
    return Number.isFinite(w.ohne_cache_read) ? w.ohne_cache_read : (w.input || 0) + (w.output || 0) + (w.cache_write || 0);
  }
  function summiere(zeilen) {
    const s = leereWerte();
    for (const z of zeilen) {
      for (const a of ARTEN) s[a] += z[a] || 0;
      s.nachrichten += z.nachrichten || 0;
    }
    s.ohne_cache_read = s.input + s.output + s.cache_write;
    return s;
  }
  function leereAuswahl() {
    return { harness: [], modell: [] };
  }
  function trifft(auswahl2, wert) {
    return auswahl2.length === 0 || auswahl2.indexOf(wert) >= 0;
  }
  function filterModelle(zeilen, a) {
    return zeilen.filter((z) => trifft(a.harness, z.harness) && trifft(a.modell, z.modell));
  }
  function filterTage(zeilen, a) {
    return zeilen.filter((z) => trifft(a.harness, z.harness) && trifft(a.modell, z.modell));
  }
  function filterSitzungen(zeilen, a) {
    return zeilen.filter(
      (z) => trifft(a.harness, z.harness) && (a.modell.length === 0 || z.modelle.some((m) => a.modell.indexOf(m) >= 0))
    );
  }
  function sitzungenTeilweise(zeilen, a) {
    if (a.modell.length === 0) return false;
    return zeilen.some((z) => z.modelle.some((m) => a.modell.indexOf(m) < 0));
  }
  function harnessAuswahlliste(zeilen) {
    const m = /* @__PURE__ */ new Map();
    for (const z of zeilen) m.set(z.harness, (m.get(z.harness) ?? 0) + ohneCacheRead(z));
    return [...m.entries()].map(([id, tokens]) => ({ id, tokens })).sort((x, y) => y.tokens - x.tokens || x.id.localeCompare(y.id));
  }
  function modellAuswahlliste(zeilen, a) {
    const m = /* @__PURE__ */ new Map();
    for (const z of zeilen) {
      if (!trifft(a.harness, z.harness)) continue;
      const da = m.get(z.modell);
      if (da) da.tokens += ohneCacheRead(z);
      else m.set(z.modell, { harness: z.harness, tokens: ohneCacheRead(z) });
    }
    return [...m.entries()].map(([id, w]) => ({ id, harness: w.harness, tokens: w.tokens })).sort((x, y) => y.tokens - x.tokens || x.id.localeCompare(y.id));
  }
  var CACHE_SCHWELLE = 4;
  function cacheAchse(w) {
    const rest = w.ohne_cache_read || w.input + w.output + w.cache_write;
    if (w.cache_read <= 0) return { art: "gemeinsam", verhaeltnis: 0 };
    if (rest <= 0) return { art: "getrennt", verhaeltnis: Infinity };
    const v = w.cache_read / rest;
    return { art: v >= CACHE_SCHWELLE ? "getrennt" : "gemeinsam", verhaeltnis: v };
  }
  function tagesreihe(zeilen, vonISO, bisISO) {
    const proTag = /* @__PURE__ */ new Map();
    for (const z of zeilen) {
      const e = proTag.get(z.tag) ?? { tag: z.tag, ohne_cache_read: 0, cache_read: 0, input: 0, output: 0, cache_write: 0 };
      e.ohne_cache_read += ohneCacheRead(z);
      e.cache_read += z.cache_read || 0;
      e.input += z.input || 0;
      e.output += z.output || 0;
      e.cache_write += z.cache_write || 0;
      proTag.set(z.tag, e);
    }
    const von = Date.parse(vonISO);
    const bis = Date.parse(bisISO);
    if (!Number.isFinite(von) || !Number.isFinite(bis) || bis < von) {
      return [...proTag.values()].sort((a, b) => a.tag.localeCompare(b.tag));
    }
    const raus = [];
    for (let t2 = Date.UTC(new Date(von).getUTCFullYear(), new Date(von).getUTCMonth(), new Date(von).getUTCDate()); t2 <= bis; t2 += 864e5) {
      const tag = new Date(t2).toISOString().slice(0, 10);
      raus.push(proTag.get(tag) ?? { tag, ohne_cache_read: 0, cache_read: 0, input: 0, output: 0, cache_write: 0 });
    }
    return raus;
  }
  function balken(reihen, breite, hoehe, hoechstwert) {
    const summen = reihen.map((r) => r.teile.reduce((s, t2) => s + Math.max(0, t2.wert), 0));
    const max = hoechstwert !== void 0 ? hoechstwert : Math.max(1, ...summen);
    const schritt = reihen.length > 0 ? breite / reihen.length : breite;
    const balkenBreite = Math.max(1, schritt * 0.7);
    const raus = reihen.map((r, i) => {
      let unten = hoehe;
      const stapel = r.teile.map((teil) => {
        const h = max > 0 ? Math.max(0, teil.wert) / max * hoehe : 0;
        unten -= h;
        return { y: unten, hoehe: h, art: teil.art };
      });
      return {
        x: i * schritt + (schritt - balkenBreite) / 2,
        breite: balkenBreite,
        stapel,
        beschriftung: r.beschriftung,
        summe: summen[i]
      };
    });
    return { balken: raus, hoechstwert: max };
  }
  function ruecksetzZeit(roh) {
    if (roh === null || roh === void 0 || roh === "") return null;
    const zahl2 = Number(roh);
    const ms = Number.isFinite(zahl2) && zahl2 > 1e9 ? zahl2 * 1e3 : Date.parse(String(roh));
    return Number.isFinite(ms) ? ms : null;
  }
  function limitVerlauf(punkte, feld) {
    const resetFeld = feld === "five_hour_pct" ? "five_hour_resets_at" : "seven_day_resets_at";
    const segmente = [];
    const ruecksetzpunkte = [];
    let laufend = [];
    let spitze = 0;
    let zuletzt = null;
    let naechsterReset = null;
    let von = Infinity;
    let bis = -Infinity;
    let hoechstwert = 0;
    for (const p of punkte) {
      const wert = p[feld];
      const t2 = Date.parse(p.ts);
      if (wert === null || wert === void 0 || !Number.isFinite(t2)) continue;
      von = Math.min(von, t2);
      bis = Math.max(bis, t2);
      hoechstwert = Math.max(hoechstwert, wert);
      if (laufend.length > 0 && wert < spitze / 2) {
        segmente.push(laufend);
        ruecksetzpunkte.push(t2);
        laufend = [];
        spitze = 0;
      }
      laufend.push({ t: t2, pct: wert });
      spitze = Math.max(spitze, wert);
      zuletzt = wert;
      const ms = ruecksetzZeit(p[resetFeld]);
      if (ms !== null) naechsterReset = ms;
    }
    if (laufend.length > 0) segmente.push(laufend);
    return {
      segmente,
      ruecksetzpunkte,
      von: Number.isFinite(von) ? von : 0,
      bis: Number.isFinite(bis) ? bis : 0,
      hoechstwert: Math.max(hoechstwert, 100),
      zuletzt,
      naechsterReset
    };
  }
  function linienPfad(punkte, von, bis, hoechstwert, breite, hoehe) {
    if (punkte.length === 0) return "";
    const spanne = bis - von || 1;
    const teile = punkte.map((p, i) => {
      const x = (p.t - von) / spanne * breite;
      const y = hoehe - p.pct / (hoechstwert || 100) * hoehe;
      return `${i === 0 ? "M" : "L"}${x.toFixed(1)} ${y.toFixed(1)}`;
    });
    return teile.join(" ");
  }
  function kostenBild(zeilen) {
    const raus = { aequivalent: 0, katalog: 0, aiu: 0, ohnePreis: [] };
    for (const z of zeilen) {
      if (z.aiu) raus.aiu += z.aiu;
      const p = z.preis;
      if (!p || p.usd === null || p.usd === void 0) {
        if (ohneCacheRead(z) > 0) raus.ohnePreis.push(`${z.harness}/${z.modell}`);
        continue;
      }
      if (p.art === "kein-preis") {
        if (ohneCacheRead(z) > 0 && p.usd === 0 && p.nie_abgebucht !== true) raus.ohnePreis.push(`${z.harness}/${z.modell}`);
        continue;
      }
      if (p.nie_abgebucht === true) raus.aequivalent += p.usd;
      else raus.katalog += p.usd;
    }
    return raus;
  }
  function vergleichsZeile(schluessel, jetzt, vorher) {
    const differenz = jetzt - vorher;
    return {
      schluessel,
      jetzt,
      vorher,
      differenz,
      prozent: vorher === 0 ? null : differenz / vorher * 100,
      richtung: differenz > 0 ? "mehr" : differenz < 0 ? "weniger" : "gleich"
    };
  }
  function vergleicheWerte(jetzt, vorher) {
    const felder = ["ohne_cache_read", "input", "output", "cache_write", "cache_read", "nachrichten"];
    return felder.map((f) => vergleichsZeile(String(f), jetzt[f] || 0, vorher[f] || 0));
  }
  function vergleicheHarnesses(jetzt, vorher) {
    const a = new Map(jetzt.map((z) => [z.harness, z.ohne_cache_read]));
    const b = new Map(vorher.map((z) => [z.harness, z.ohne_cache_read]));
    const alle = [.../* @__PURE__ */ new Set([...a.keys(), ...b.keys()])].sort();
    return alle.map((h) => vergleichsZeile(h, a.get(h) ?? 0, b.get(h) ?? 0)).sort((x, y) => Math.abs(y.differenz) - Math.abs(x.differenz));
  }
  function vorherigerZeitraum(vonISO, bisISO) {
    const von = Date.parse(vonISO);
    const bis = Date.parse(bisISO);
    if (!Number.isFinite(von) || !Number.isFinite(bis) || bis <= von) return null;
    const dauer = bis - von;
    return { von: new Date(von - dauer).toISOString(), bis: new Date(von).toISOString() };
  }
  function kompakt(n) {
    const z = Math.abs(n);
    if (z >= 1e9) return `${(n / 1e9).toFixed(1).replace(".", ",")} Mrd.`;
    if (z >= 1e6) return `${(n / 1e6).toFixed(1).replace(".", ",")} Mio.`;
    if (z >= 1e3) return `${(n / 1e3).toFixed(1).replace(".", ",")}k`;
    return String(Math.round(n));
  }
  function zahl(n) {
    return Math.round(n).toLocaleString("de-DE");
  }
  function usd(n) {
    return `${n.toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} USD`;
  }
  function prozent(n) {
    return `${n.toLocaleString("de-DE", { minimumFractionDigits: 0, maximumFractionDigits: 1 })} %`;
  }
  function zeitpunkt(iso) {
    const t2 = Date.parse(iso);
    if (!Number.isFinite(t2)) return iso;
    return new Date(t2).toLocaleString("de-DE", { dateStyle: "short", timeStyle: "short" });
  }
  function wochenbudget(punkte, jetzt = Date.now()) {
    let letzter = null;
    let bis = 0;
    for (const p of punkte) {
      if (p.seven_day_pct === null || p.seven_day_pct === void 0) continue;
      const ms = ruecksetzZeit(p.seven_day_resets_at);
      if (ms === null) continue;
      letzter = p;
      bis = ms;
    }
    if (!letzter || letzter.seven_day_pct === null || letzter.seven_day_pct === void 0) return null;
    const von = bis - 7 * 86400 * 1e3;
    const tagAnfang = new Date(von);
    const tagHeute = new Date(jetzt);
    const tage2 = Math.round(
      (Date.UTC(tagHeute.getFullYear(), tagHeute.getMonth(), tagHeute.getDate()) - Date.UTC(tagAnfang.getFullYear(), tagAnfang.getMonth(), tagAnfang.getDate())) / 864e5
    );
    const tag = Math.max(1, Math.min(7, tage2 + 1));
    const erlaubt = Math.min(100, tag * 100 / 7);
    const verbraucht = letzter.seven_day_pct;
    return { verbraucht, erlaubt, luft: erlaubt - verbraucht, tag, von, bis };
  }
  function gemeinsamerVorspann(zeilen) {
    if (zeilen.length < 2) return "";
    let gemeinsam = zeilen[0];
    for (const z of zeilen.slice(1)) {
      let i = 0;
      while (i < gemeinsam.length && i < z.length && gemeinsam[i] === z[i]) i += 1;
      gemeinsam = gemeinsam.slice(0, i);
      if (!gemeinsam) return "";
    }
    const m = /^[\s\S]*[.!?](?=\s|$)/.exec(gemeinsam);
    if (!m) return "";
    const satz = m[0].trim();
    return satz.length >= 30 ? satz : "";
  }

  // src/verbrauch/texte.ts
  var DE = {
    // --- Rahmen ---------------------------------------------------------------
    "fenster.titel": "Agent-Workbench \u2013 Verbrauch",
    "kopf.titel": "Verbrauch",
    "kopf.unterzeile": "Alle Harnesses, die auf dieser Maschine eine lesbare Spur hinterlassen. Zeitraum, Harness und Modell lassen sich unten einschr\xE4nken.",
    "laden": "wird gelesen \u2026",
    "fehler.titel": "Der Verbrauch lie\xDF sich nicht lesen",
    "leer": "Im gew\xE4hlten Zeitraum ist nichts verbucht.",
    "stand": "Stand {0}, Zeitraum {1} bis {2}",
    // --- Zeitraum -------------------------------------------------------------
    "zeitraum.titel": "Zeitraum",
    "zeitraum.1": "heute",
    "zeitraum.2": "2 Tage",
    "zeitraum.7": "7 Tage",
    "zeitraum.14": "14 Tage",
    "zeitraum.30": "30 Tage",
    // --- Filter ---------------------------------------------------------------
    "filter.harness": "Harness",
    "filter.modell": "Modell",
    "filter.alle": "alle",
    "filter.zuruecksetzen": "Auswahl aufheben",
    "filter.aktiv": "Es z\xE4hlt nur, was zu allen gew\xE4hlten Merkmalen zugleich passt.",
    // --- Die Summen -----------------------------------------------------------
    "summe.titel": "Gesamt",
    "summe.gesamt": "Verbrauch gesamt",
    // Der Vergleich beschriftet seine Zeilen ueber den FELDNAMEN (summe.<feld>). Dieser hier
    // meint dasselbe wie 'summe.gesamt', muss aber unter seinem Feldnamen auffindbar sein.
    "summe.ohne_cache_read": "Verbrauch gesamt",
    "summe.gesamt.hinweis": "Eingabe, Ausgabe und Cache-Schreiben zusammen. Cache-Lesen steht getrennt daneben, siehe unten.",
    "summe.input": "Eingabe",
    "summe.output": "Ausgabe",
    "summe.cache_write": "Cache-Schreiben",
    "summe.cache_read": "Cache-Lesen",
    "summe.reasoning": "Denken",
    "summe.nachrichten": "Nachrichten",
    // --- Cache-Lesen ----------------------------------------------------------
    "cache.titel": "Cache-Lesen, getrennt gezeichnet",
    "cache.grund": "Cache-Lesen ist im gew\xE4hlten Zeitraum {0}-mal so gro\xDF wie alles \xFCbrige zusammen. Auf einer gemeinsamen linearen Achse bliebe vom Rest ein Strich \u2013 deshalb zwei Diagramme statt eines.",
    "cache.grund.klein": "Cache-Lesen ist im gew\xE4hlten Zeitraum {0}-mal so gro\xDF wie alles \xFCbrige. Das tr\xE4gt eine gemeinsame Achse noch.",
    "cache.diagramm.ohne": "Eingabe, Ausgabe, Cache-Schreiben",
    "cache.diagramm.nur": "Cache-Lesen allein",
    // --- Tagesverlauf ---------------------------------------------------------
    "tage.titel": "Verlauf je Tag",
    "tage.hinweis": "UTC-Tagesgrenzen, dieselben wie im Bericht von wb-budget.",
    "tage.leer": "F\xFCr diesen Zeitraum liegen keine Tageswerte vor.",
    // --- Harnesses ------------------------------------------------------------
    "harness.titel": "Je Harness",
    "harness.spalte": "Harness",
    // --- Modelle --------------------------------------------------------------
    "modell.titel": "Je Modell",
    "modell.spalte": "Modell",
    // --- Tempo ----------------------------------------------------------------
    "tempo.titel": "Token je Sekunde, je Modell",
    "tempo.spalte": "Token/s",
    "tempo.gemessen": "gemessen",
    "tempo.naeherung": "N\xE4herung",
    "tempo.unbekannt": "nicht messbar",
    "tempo.zeichen.naeherung": "\u2248",
    "tempo.warnung": "Nur die mit {0} bezeichneten Zahlen sind eine echte Generierungsrate. Alle \xFCbrigen sind eine Wanduhr-N\xE4herung aus Zeitstempeln: Denkzeit, Netz und Werkzeugpausen z\xE4hlen mit. Der Fehler ist weder klein noch gleichbleibend.",
    "tempo.grundlage": "gemessene Zeit: {0} s",
    // --- Kosten ---------------------------------------------------------------
    "kosten.titel": "Geld und Kontingent",
    "kosten.zwei": "Zwei Gr\xF6\xDFen mit verschiedenen Nennern, die nie zu einer Zahl addiert werden: ein Dollarbetrag gilt nur, wo ein Anbieter pro Token abrechnet \u2013 die Abo-Zug\xE4nge zahlen stattdessen einen Anteil ihres Kontingents.",
    "kosten.usd": "Betrag",
    "kosten.art": "Art",
    "kosten.art.abo-aequivalent": "API-\xC4quivalent",
    "kosten.art.katalogpreis": "Listenpreis",
    "kosten.art.harness-angabe": "vom Harness selbst gerechnet",
    "kosten.art.kein-preis": "kein Preis bekannt",
    "kosten.nie_abgebucht": "nie abgebucht \u2013 dieser Betrag sagt, was derselbe Verbrauch \xFCber die API gekostet h\xE4tte. Bezahlt wurde ein Abo.",
    "kosten.aiu": "AIC (Copilots eigene Abrechnungseinheit)",
    "kosten.summe.aequivalent": "Summe API-\xC4quivalent (nie abgebucht)",
    "kosten.summe.katalog": "Summe Listenpreis",
    "kosten.ohne": "ohne Preis",
    // --- Kontingent -----------------------------------------------------------
    "kontingent.titel": "Kontingente",
    "kontingent.verbraucht": "verbraucht",
    "kontingent.rest": "\xFCbrig",
    "kontingent.zurueck": "f\xE4llt zur\xFCck am {0}",
    "kontingent.erschoepft": "ersch\xF6pft",
    "kontingent.keins": "kein Kontingent",
    "kontingent.ohnestand": "Kontingent ohne lesbaren Stand",
    "einheit.aic": "AI Credits",
    // WAS SCHIEFGING UND WIE ES WEITERGEHT (08.09.2026). Hier stand bis dahin
    // „Kein Kontingentstand verfügbar: {0}", und {0} war die rohe Ausgabe des
    // Werkzeugs -- an einem Rechner ohne `wb-kontingent` las der Mensch
    // „JSONDecodeError: Expecting value…". Ein Fehler, der die Sprache seines
    // Erzeugers spricht, sagt nichts darüber, was jetzt zu tun ist
    // (apple-native-design, abnahme.md: „Die Fehlermeldung sagt, was schiefging
    // und wie es weitergeht"). Der Rohtext bleibt -- im Hilfeschildchen.
    "kontingent.fehlt": "Das Werkzeug wb-kontingent fehlt oder antwortet nicht \u2013 Stand abfragen mit `wb-kontingent` im Terminal.",
    "kontingent.fehlt.tipp": "Was das Werkzeug gemeldet hat: {0}",
    "kontingent.werkzeug.fehlt": "Das Werkzeug hat keine Ausgabe hinterlassen.",
    // --- Limit ----------------------------------------------------------------
    "limit.titel": "Der Weg zum Limit",
    "limit.5h": "5-Stunden-Fenster",
    "limit.7d": "7-Tage-Fenster",
    "limit.stand": "zuletzt {0}",
    "limit.reset": "R\xFCcksetzpunkt",
    "limit.reset.anzahl": "R\xFCcksetzpunkte im Zeitraum: {0}",
    "limit.reset.naechster": "n\xE4chster R\xFCcksetzpunkt: {0}",
    "limit.leer": "F\xFCr diesen Zeitraum ist kein Limit-Stand geloggt.",
    "limit.quelle": "Aus ~/.claude/workbench/limits.jsonl, das die Statusleiste bei jedem Zeichnen fortschreibt. Es gilt f\xFCr das Anthropic-Konto als Ganzes, nicht je Modell.",
    // --- Das Tagesbudget des Wochenfensters -----------------------------------
    "wochen.erlaubt": "erlaubt bis heute Abend",
    "wochen.tag": "Tag {0} von 7",
    "wochen.luft": "Luft {0} Punkte",
    "wochen.darueber": "dar\xFCber um {0} Punkte",
    "wochen.fehlt": "F\xFCr das Wochenfenster ist kein Stand geloggt.",
    // --- Sitzungen und Worker -------------------------------------------------
    "sitzung.titel": "Je Sitzung und Worker",
    "sitzung.spalte": "Sitzung",
    "sitzung.worker": "Worker",
    "sitzung.ordner": "Ordner",
    "sitzung.zeitraum": "von \u2026 bis",
    "sitzung.ohne_worker": "\u2013",
    "sitzung.mehr": "weitere {0} Sitzungen nicht gezeigt",
    // --- Vergleich ------------------------------------------------------------
    "vergleich.titel": "Zwei Zeitr\xE4ume nebeneinander",
    "vergleich.knopf": "Mit dem Zeitraum davor vergleichen",
    "vergleich.aus": "Vergleich schlie\xDFen",
    "vergleich.jetzt": "gew\xE4hlter Zeitraum",
    "vergleich.vorher": "der gleich lange davor",
    "vergleich.differenz": "Unterschied",
    "vergleich.laedt": "der fr\xFChere Zeitraum wird gelesen \u2026",
    "vergleich.kein_vorher": "Im fr\xFCheren Zeitraum ist nichts verbucht \u2013 ein Prozentwert w\xE4re hier eine Division durch null.",
    // --- Lücken ---------------------------------------------------------------
    "luecke.titel": "Was hier nicht stehen kann",
    "luecke.einleitung": "Diese Harnesses f\xFChrt die Registry, aber sie hinterlassen auf dieser Maschine keine lesbare Verbrauchsspur. Sie fehlen nicht, weil nichts verbraucht wurde, sondern weil nichts zu messen ist.",
    "luecke.spalte": "Harness",
    "luecke.grund": "Grund",
    // --- Quellen --------------------------------------------------------------
    "quelle.titel": "Woher die Zahlen kommen",
    "quelle.spalte": "Quelle",
    "quelle.zustand.gelesen": "gelesen",
    "quelle.zustand.leer": "vorhanden, aber im Zeitraum ohne Eintrag",
    "quelle.zustand.fehlt": "auf dieser Maschine nicht vorhanden",
    "quelle.zustand.unlesbar": "nicht lesbar",
    "quelle.nachrichten": "{0} Nachrichten",
    // --- Zustandszeichen (keine Emojis) --------------------------------------
    "zeichen.gelesen": "\u25CF",
    "zeichen.leer": "\u25CB",
    "zeichen.fehlt": "\u2013",
    "zeichen.unlesbar": "\u2715",
    "zeichen.mehr": "\u25B2",
    "zeichen.weniger": "\u25BC",
    "zeichen.gleich": "="
  };
  var EN = {
    // --- Frame ---------------------------------------------------------------
    "fenster.titel": "Agent Workbench \u2014 Usage",
    "kopf.titel": "Usage",
    "kopf.unterzeile": "Every harness that leaves a readable trace on this machine. Narrow it down below by time range, harness, and model.",
    "laden": "reading \u2026",
    "fehler.titel": "Usage could not be read",
    "leer": "Nothing is booked in the chosen time range.",
    "stand": "As of {0}, range {1} to {2}",
    // --- Time range -------------------------------------------------------------
    "zeitraum.titel": "Range",
    "zeitraum.1": "today",
    "zeitraum.2": "2 days",
    "zeitraum.7": "7 days",
    "zeitraum.14": "14 days",
    "zeitraum.30": "30 days",
    // --- Filter ---------------------------------------------------------------
    "filter.harness": "Harness",
    "filter.modell": "Model",
    "filter.alle": "all",
    "filter.zuruecksetzen": "Clear selection",
    "filter.aktiv": "Only what matches every chosen trait at once counts.",
    // --- The totals -----------------------------------------------------------
    "summe.titel": "Total",
    "summe.gesamt": "Total usage",
    // Der Vergleich beschriftet seine Zeilen ueber den FELDNAMEN (summe.<feld>). Dieser hier
    // meint dasselbe wie 'summe.gesamt', muss aber unter seinem Feldnamen auffindbar sein.
    "summe.ohne_cache_read": "Total usage",
    "summe.gesamt.hinweis": "Input, output, and cache write together. Cache read stands separately next to it, see below.",
    "summe.input": "Input",
    "summe.output": "Output",
    "summe.cache_write": "Cache write",
    "summe.cache_read": "Cache read",
    "summe.reasoning": "Reasoning",
    "summe.nachrichten": "Messages",
    // --- Cache read ----------------------------------------------------------
    "cache.titel": "Cache read, drawn separately",
    "cache.grund": "In the chosen range, cache read is {0} times the size of everything else combined. On a shared linear axis the rest would flatten to a line \u2014 hence two charts instead of one.",
    "cache.grund.klein": "In the chosen range, cache read is {0} times the size of everything else. A shared axis still carries that.",
    "cache.diagramm.ohne": "Input, output, cache write",
    "cache.diagramm.nur": "Cache read alone",
    // --- Daily trend ---------------------------------------------------------
    "tage.titel": "Trend by day",
    "tage.hinweis": "UTC day boundaries, the same ones wb-budget's report uses.",
    "tage.leer": "No daily figures are available for this range.",
    // --- Harnesses ------------------------------------------------------------
    "harness.titel": "By harness",
    "harness.spalte": "Harness",
    // --- Models --------------------------------------------------------------
    "modell.titel": "By model",
    "modell.spalte": "Model",
    // --- Speed ----------------------------------------------------------------
    "tempo.titel": "Tokens per second, by model",
    "tempo.spalte": "Tokens/s",
    "tempo.gemessen": "measured",
    "tempo.naeherung": "estimate",
    "tempo.unbekannt": "not measurable",
    "tempo.zeichen.naeherung": "\u2248",
    "tempo.warnung": "Only the numbers marked {0} are a real generation rate. Every other one is a wall-clock estimate from timestamps: thinking time, network, and tool pauses count too. The error is neither small nor consistent.",
    "tempo.grundlage": "measured time: {0} s",
    // --- Cost ---------------------------------------------------------------
    "kosten.titel": "Money and quota",
    "kosten.zwei": "Two figures with different denominators, never added into one number: a dollar amount only applies where a provider bills per token \u2014 subscription access instead spends a share of its quota.",
    "kosten.usd": "Amount",
    "kosten.art": "Kind",
    "kosten.art.abo-aequivalent": "API equivalent",
    "kosten.art.katalogpreis": "List price",
    "kosten.art.harness-angabe": "computed by the harness itself",
    "kosten.art.kein-preis": "no known price",
    "kosten.nie_abgebucht": "never charged \u2014 this amount says what the same usage would have cost through the API. What was actually paid was a subscription.",
    "kosten.aiu": "AIC (Copilot's own billing unit)",
    "kosten.summe.aequivalent": "Total API equivalent (never charged)",
    "kosten.summe.katalog": "Total list price",
    "kosten.ohne": "no price",
    // --- Quota -----------------------------------------------------------
    "kontingent.titel": "Quotas",
    "kontingent.verbraucht": "used",
    "kontingent.rest": "left",
    "kontingent.zurueck": "resets on {0}",
    "kontingent.erschoepft": "exhausted",
    "kontingent.keins": "no quota",
    "kontingent.ohnestand": "quota with no readable reading",
    "einheit.aic": "AI credits",
    "kontingent.fehlt": "The tool wb-kontingent is missing or does not answer \u2014 run `wb-kontingent` in a terminal to read the status.",
    "kontingent.fehlt.tipp": "What the tool reported: {0}",
    "kontingent.werkzeug.fehlt": "The tool left no output.",
    // --- Limit ----------------------------------------------------------------
    "limit.titel": "The path to the limit",
    "limit.5h": "5-hour window",
    "limit.7d": "7-day window",
    "limit.stand": "last {0}",
    "limit.reset": "Reset point",
    "limit.reset.anzahl": "Reset points in this range: {0}",
    "limit.reset.naechster": "next reset point: {0}",
    "limit.leer": "No limit status is logged for this range.",
    "limit.quelle": "From ~/.claude/workbench/limits.jsonl, which the status bar appends to on every draw. It applies to the Anthropic account as a whole, not per model.",
    // --- Das Tagesbudget des Wochenfensters -----------------------------------
    "wochen.erlaubt": "allowed by tonight",
    "wochen.tag": "day {0} of 7",
    "wochen.luft": "{0} points to spare",
    "wochen.darueber": "{0} points over",
    "wochen.fehlt": "No reading logged for the weekly window.",
    // --- Sessions and workers -------------------------------------------------
    "sitzung.titel": "By session and worker",
    "sitzung.spalte": "Session",
    "sitzung.worker": "Worker",
    "sitzung.ordner": "Folder",
    "sitzung.zeitraum": "from \u2026 to",
    "sitzung.ohne_worker": "\u2014",
    "sitzung.mehr": "{0} further sessions not shown",
    // --- Comparison ------------------------------------------------------------
    "vergleich.titel": "Two ranges side by side",
    "vergleich.knopf": "Compare with the range before",
    "vergleich.aus": "Close comparison",
    "vergleich.jetzt": "chosen range",
    "vergleich.vorher": "the equally long one before it",
    "vergleich.differenz": "Difference",
    "vergleich.laedt": "reading the earlier range \u2026",
    "vergleich.kein_vorher": "Nothing is booked in the earlier range \u2014 a percentage here would be a division by zero.",
    // --- Gaps ---------------------------------------------------------------
    "luecke.titel": "What cannot show up here",
    "luecke.einleitung": "These harnesses are listed in the registry, but leave no readable usage trace on this machine. They are not missing because nothing was used, but because there is nothing to measure.",
    "luecke.spalte": "Harness",
    "luecke.grund": "Reason",
    // --- Sources --------------------------------------------------------------
    "quelle.titel": "Where the numbers come from",
    "quelle.spalte": "Source",
    "quelle.zustand.gelesen": "read",
    "quelle.zustand.leer": "present, but no entry in this range",
    "quelle.zustand.fehlt": "not present on this machine",
    "quelle.zustand.unlesbar": "not readable",
    "quelle.nachrichten": "{0} messages",
    // --- State marks (no emoji) --------------------------------
    "zeichen.gelesen": "\u25CF",
    "zeichen.leer": "\u25CB",
    "zeichen.fehlt": "\u2013",
    "zeichen.unlesbar": "\u2715",
    "zeichen.mehr": "\u25B2",
    "zeichen.weniger": "\u25BC",
    "zeichen.gleich": "="
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
    const tabelle2 = TABELLEN[aktuelleSprache] ?? DE;
    const roh = tabelle2[schluessel] ?? DE[schluessel];
    if (roh === void 0) return `[${schluessel}]`;
    return roh.replace(/\{(\d+)\}/g, (treffer, nr) => {
      const w = werte[Number(nr)];
      return w === void 0 ? treffer : String(w);
    });
  }

  // src/verbrauch/verbrauch.ts
  var NS = "http://www.w3.org/2000/svg";
  var ARTFARBE = {
    input: "var(--ein)",
    output: "var(--raus)",
    cache_write: "var(--cw)",
    cache_read: "var(--cr)"
  };
  var inhaltEl = document.getElementById("inhalt");
  var standEl = document.getElementById("stand");
  var statusEl = document.getElementById("statuszeile");
  var zeitraumEl = document.getElementById("zeitraum");
  var filterHarnessEl = document.getElementById("filter-harness");
  var filterModellEl = document.getElementById("filter-modell");
  function kopfzeileBeschriften() {
    document.documentElement.lang = sprache();
    document.title = t("fenster.titel");
    document.getElementById("titel").textContent = t("kopf.titel");
    document.getElementById("unterzeile").textContent = t("kopf.unterzeile");
  }
  var ZEITRAEUME = [1, 2, 7, 14, 30];
  var tage = 7;
  var daten = null;
  var vergleichsDaten = null;
  var vergleichAn = false;
  var auswahl = leereAuswahl();
  var status = "";
  function setzeStatus(text) {
    status = text;
    statusEl.textContent = text;
  }
  function el(name, klasse, text) {
    const n = document.createElement(name);
    if (klasse) n.className = klasse;
    if (text !== void 0) n.textContent = text;
    return n;
  }
  function abschnitt(titel, ...kinder) {
    const s = el("section");
    s.dataset.abschnitt = titel;
    s.appendChild(el("h2", void 0, titel));
    for (const k of kinder) if (k) s.appendChild(k);
    return s;
  }
  function tabelle(kopf, zeilen) {
    const tb = el("table");
    const thead = el("thead");
    const kr = el("tr");
    for (const k of kopf) {
      const th = el("th", k.zahl ? "zahl" : void 0, k.text);
      kr.appendChild(th);
    }
    thead.appendChild(kr);
    tb.appendChild(thead);
    const body = el("tbody");
    for (const z of zeilen) {
      const tr = el("tr");
      z.forEach((wert, i) => {
        const td = el("td", kopf[i]?.zahl ? "zahl" : void 0);
        if (typeof wert === "string") td.textContent = wert;
        else td.appendChild(wert);
        tr.appendChild(td);
      });
      body.appendChild(tr);
    }
    tb.appendChild(body);
    return tb;
  }
  function svgKnoten(name, attribute) {
    const n = document.createElementNS(NS, name);
    for (const [k, v] of Object.entries(attribute)) n.setAttribute(k, String(v));
    return n;
  }
  function legende(arten) {
    const l = el("div", "legende");
    for (const a of arten) {
      const s = el("span", void 0);
      const p = el("span", "punkt");
      p.style.background = ARTFARBE[a] ?? "var(--gedaempft)";
      s.appendChild(p);
      s.appendChild(document.createTextNode(t(`summe.${a}`)));
      l.appendChild(s);
    }
    return l;
  }
  function zeichneZeitraum() {
    zeitraumEl.replaceChildren();
    zeitraumEl.appendChild(el("span", "marke", `${t("zeitraum.titel")}:`));
    const streifen = el("div", "segmente");
    for (const n of ZEITRAEUME) {
      const k = el("button", `knopf${n === tage ? " gewaehlt" : ""}`, t(`zeitraum.${n}`));
      k.type = "button";
      k.dataset.tage = String(n);
      k.addEventListener("click", () => {
        if (n === tage) return;
        tage = n;
        vergleichsDaten = null;
        void laden();
      });
      streifen.appendChild(k);
    }
    zeitraumEl.appendChild(streifen);
    const v = el("button", `knopf${vergleichAn ? " gewaehlt" : ""}`, vergleichAn ? t("vergleich.aus") : t("vergleich.knopf"));
    v.type = "button";
    v.id = "vergleich-knopf";
    v.addEventListener("click", () => {
      vergleichAn = !vergleichAn;
      if (vergleichAn && !vergleichsDaten) void ladeVergleich();
      else zeichne();
    });
    zeitraumEl.appendChild(v);
  }
  function chipReihe(ziel, beschriftung, eintraege, gewaehlt, umschalten2, praefix) {
    ziel.replaceChildren();
    if (eintraege.length === 0) return;
    ziel.appendChild(el("span", "marke", `${beschriftung}:`));
    const alle = el("button", `knopf${gewaehlt.length === 0 ? " gewaehlt" : ""}`, t("filter.alle"));
    alle.type = "button";
    alle.dataset.filter = `${praefix}:alle`;
    alle.addEventListener("click", () => {
      if (gewaehlt.length === 0) return;
      gewaehlt.splice(0, gewaehlt.length);
      zeichne();
    });
    ziel.appendChild(alle);
    for (const e of eintraege) {
      const k = el("button", `knopf${gewaehlt.indexOf(e.id) >= 0 ? " gewaehlt" : ""}`, e.id);
      k.type = "button";
      k.dataset.filter = `${praefix}:${e.id}`;
      k.title = `${e.id} \u2014 ${zahl(e.tokens)} ${t("summe.gesamt")}`;
      k.addEventListener("click", () => umschalten2(e.id));
      ziel.appendChild(k);
    }
  }
  function umschalten(liste, id) {
    const i = liste.indexOf(id);
    if (i >= 0) liste.splice(i, 1);
    else liste.push(id);
    zeichne();
  }
  function kachel(klasse, titel, wert, neben, titelText) {
    const k = el("div", `zahlenfeld ${klasse}`);
    if (titelText) k.title = titelText;
    k.appendChild(el("div", "titel", titel));
    k.appendChild(el("div", "wert", wert));
    k.appendChild(el("div", "strich"));
    if (neben) k.appendChild(el("div", "neben", neben));
    return k;
  }
  function abschnittSummen(w) {
    const k = el("div", "zahlenreihe");
    k.appendChild(kachel("summe", t("summe.gesamt"), zahl(w.ohne_cache_read), t("summe.nachrichten") + ": " + zahl(w.nachrichten), t("summe.gesamt.hinweis")));
    k.appendChild(kachel("ein", t("summe.input"), zahl(w.input), kompakt(w.input)));
    k.appendChild(kachel("raus", t("summe.output"), zahl(w.output), kompakt(w.output)));
    k.appendChild(kachel("cw", t("summe.cache_write"), zahl(w.cache_write), kompakt(w.cache_write)));
    k.appendChild(kachel("cr", t("summe.cache_read"), zahl(w.cache_read), kompakt(w.cache_read)));
    return abschnitt(t("summe.titel"), k);
  }
  function balkenDiagramm(titel, reihen, arten) {
    const kasten = el("div", "diagramm");
    const breite = 560;
    const hoehe = 150;
    const kopf = el("div", "kopfzeile");
    kopf.appendChild(el("span", void 0, titel));
    const { balken: stangen, hoechstwert } = balken(reihen, breite, hoehe);
    kopf.appendChild(el("span", void 0, kompakt(hoechstwert)));
    kasten.appendChild(kopf);
    const svg = svgKnoten("svg", { viewBox: `0 0 ${breite} ${hoehe + 18}`, role: "img" });
    svg.appendChild(svgKnoten("line", { x1: 0, y1: hoehe, x2: breite, y2: hoehe, stroke: "var(--linie)" }));
    for (const s of stangen) {
      for (const teil of s.stapel) {
        if (teil.hoehe <= 0) continue;
        const r = svgKnoten("rect", {
          x: s.x.toFixed(1),
          y: teil.y.toFixed(1),
          width: s.breite.toFixed(1),
          height: Math.max(0.5, teil.hoehe).toFixed(1),
          fill: ARTFARBE[teil.art] ?? "var(--gedaempft)"
        });
        const titelKnoten = svgKnoten("title", {});
        titelKnoten.textContent = `${s.beschriftung} \u2014 ${t(`summe.${teil.art}`)}: ${zahl(teil.hoehe / hoehe * hoechstwert)}`;
        r.appendChild(titelKnoten);
        svg.appendChild(r);
      }
      if (stangen.length <= 10 || stangen.indexOf(s) % 2 === 0) {
        const beschriftung = svgKnoten("text", {
          x: (s.x + s.breite / 2).toFixed(1),
          y: hoehe + 13,
          fill: "var(--gedaempft)",
          "font-size": 9,
          "text-anchor": "middle"
        });
        beschriftung.textContent = s.beschriftung.slice(5);
        svg.appendChild(beschriftung);
      }
    }
    kasten.appendChild(svg);
    kasten.appendChild(legende(arten));
    return kasten;
  }
  function abschnittTage(d, gefiltertTage, gesamt) {
    const reihe = tagesreihe(gefiltertTage, d.fenster.von, d.fenster.bis);
    const plan = cacheAchse(gesamt);
    const kasten = el("div", "diagramme");
    if (reihe.length === 0) {
      return abschnitt(t("tage.titel"), el("p", "hinweis", t("tage.leer")));
    }
    if (plan.art === "getrennt") {
      kasten.appendChild(
        balkenDiagramm(
          t("cache.diagramm.ohne"),
          reihe.map((r) => ({
            beschriftung: r.tag,
            teile: [
              { wert: r.input, art: "input" },
              { wert: r.output, art: "output" },
              { wert: r.cache_write, art: "cache_write" }
            ]
          })),
          ["input", "output", "cache_write"]
        )
      );
      kasten.appendChild(
        balkenDiagramm(
          t("cache.diagramm.nur"),
          reihe.map((r) => ({ beschriftung: r.tag, teile: [{ wert: r.cache_read, art: "cache_read" }] })),
          ["cache_read"]
        )
      );
    } else {
      kasten.appendChild(
        balkenDiagramm(
          t("cache.diagramm.ohne"),
          reihe.map((r) => ({
            beschriftung: r.tag,
            teile: [
              { wert: r.input, art: "input" },
              { wert: r.output, art: "output" },
              { wert: r.cache_write, art: "cache_write" },
              { wert: r.cache_read, art: "cache_read" }
            ]
          })),
          ["input", "output", "cache_write", "cache_read"]
        )
      );
    }
    const verhaeltnis = Number.isFinite(plan.verhaeltnis) ? plan.verhaeltnis.toFixed(1).replace(".", ",") : "\u221E";
    const grund = el(
      "p",
      "hinweis",
      plan.art === "getrennt" ? t("cache.grund", verhaeltnis) : t("cache.grund.klein", verhaeltnis)
    );
    return abschnitt(t("tage.titel"), el("p", "hinweis", t("tage.hinweis")), grund, kasten);
  }
  function tempoMarke(z) {
    const art = z.tempo?.art ?? "unbekannt";
    const klasse = art === "gemessen" ? "gemessen" : art === "naeherung" ? "naeherung" : "fehlt";
    const m = el("span", `marke-art ${klasse}`, t(`tempo.${art}`));
    m.title = umlaute(z.tempo?.grund ?? "");
    return m;
  }
  function tempoWert(z) {
    const s = el("span");
    if (z.tempo?.wert === null || z.tempo?.wert === void 0) {
      s.textContent = "\u2014";
      return s;
    }
    const vorzeichen = z.tempo.art === "naeherung" ? `${t("tempo.zeichen.naeherung")} ` : "";
    s.textContent = `${vorzeichen}${z.tempo.wert.toLocaleString("de-DE", { maximumFractionDigits: 1 })}`;
    if (z.tempo.sekunden) s.title = t("tempo.grundlage", zahl(z.tempo.sekunden));
    return s;
  }
  function preisZelle(z) {
    const d = el("div");
    const p = z.preis;
    if (!p || p.usd === null || p.usd === void 0) {
      d.appendChild(el("span", "fein", t("kosten.ohne")));
      return d;
    }
    d.appendChild(el("div", void 0, usd(p.usd)));
    const art = el("div", "fein", t(`kosten.art.${p.art}`));
    art.title = p.quelle;
    d.appendChild(art);
    if (p.nie_abgebucht === true && p.usd > 0) d.appendChild(el("div", "einschraenkung", t("kosten.nie_abgebucht")));
    if (z.aiu) d.appendChild(el("div", "fein", `${z.aiu.toLocaleString("de-DE", { maximumFractionDigits: 3 })} ${t("kosten.aiu")}`));
    return d;
  }
  function abschnittHarnesses(modelle) {
    const proHarness = /* @__PURE__ */ new Map();
    for (const z of modelle) {
      const l = proHarness.get(z.harness) ?? [];
      l.push(z);
      proHarness.set(z.harness, l);
    }
    const zeilen = [...proHarness.entries()].map(([h, l]) => ({ h, w: summiere(l) })).sort((a, b) => b.w.ohne_cache_read - a.w.ohne_cache_read).map(({ h, w }) => [
      h,
      zahl(w.ohne_cache_read),
      zahl(w.input),
      zahl(w.output),
      zahl(w.cache_write),
      zahl(w.cache_read),
      zahl(w.nachrichten)
    ]);
    return abschnitt(
      t("harness.titel"),
      tabelle(
        [
          { text: t("harness.spalte") },
          { text: t("summe.gesamt"), zahl: true },
          { text: t("summe.input"), zahl: true },
          { text: t("summe.output"), zahl: true },
          { text: t("summe.cache_write"), zahl: true },
          { text: t("summe.cache_read"), zahl: true },
          { text: t("summe.nachrichten"), zahl: true }
        ],
        zeilen
      )
    );
  }
  function abschnittModelle(modelle) {
    const zeilen = modelle.map((z) => [
      z.harness,
      z.modell,
      zahl(ohneCacheRead(z)),
      zahl(z.input),
      zahl(z.output),
      zahl(z.cache_read),
      tempoWert(z),
      tempoMarke(z),
      preisZelle(z)
    ]);
    return abschnitt(
      t("modell.titel"),
      tabelle(
        [
          { text: t("harness.spalte") },
          { text: t("modell.spalte") },
          { text: t("summe.gesamt"), zahl: true },
          { text: t("summe.input"), zahl: true },
          { text: t("summe.output"), zahl: true },
          { text: t("summe.cache_read"), zahl: true },
          { text: t("tempo.spalte"), zahl: true },
          { text: t("kosten.art") },
          { text: t("kosten.usd") }
        ],
        zeilen
      )
    );
  }
  function abschnittTempo(modelle) {
    const mit = modelle.filter((z) => z.tempo && z.tempo.wert !== null);
    const sortiert = [...mit].sort((a, b) => (b.tempo.wert ?? 0) - (a.tempo.wert ?? 0));
    const warnung = el("p", "hinweis einschraenkung", t("tempo.warnung", t("tempo.gemessen")));
    if (sortiert.length === 0) return abschnitt(t("tempo.titel"), warnung, el("p", "hinweis", t("leer")));
    const zeilen = sortiert.map((z) => [z.harness, z.modell, tempoWert(z), tempoMarke(z)]);
    return abschnitt(
      t("tempo.titel"),
      warnung,
      tabelle(
        [
          { text: t("harness.spalte") },
          { text: t("modell.spalte") },
          { text: t("tempo.spalte"), zahl: true },
          { text: t("kosten.art") }
        ],
        zeilen
      )
    );
  }
  function abschnittKosten(modelle) {
    const bild = kostenBild(modelle);
    const k = el("div", "zahlenreihe");
    const aequivalent = kachel("summe", t("kosten.summe.aequivalent"), usd(bild.aequivalent));
    aequivalent.appendChild(el("div", "einschraenkung", t("kosten.nie_abgebucht")));
    k.appendChild(aequivalent);
    k.appendChild(kachel("ein", t("kosten.summe.katalog"), usd(bild.katalog)));
    if (bild.aiu > 0) k.appendChild(kachel("cw", t("kosten.aiu"), bild.aiu.toLocaleString("de-DE", { maximumFractionDigits: 3 })));
    if (bild.ohnePreis.length > 0) k.appendChild(kachel("cr", t("kosten.ohne"), String(bild.ohnePreis.length), bild.ohnePreis.join(", ")));
    return abschnitt(t("kosten.titel"), el("p", "hinweis", t("kosten.zwei")), k);
  }
  function balkenZeile(o) {
    const z = el("div", "balkenzeile");
    if (o.lage) z.dataset.lage = o.lage;
    const oben = el("div", "oben");
    oben.appendChild(el("span", "name", o.name));
    if (o.rechts) oben.appendChild(el("span", "rechts", o.rechts));
    z.appendChild(oben);
    z.appendChild(el("div", "wert", o.wert));
    if (o.anteil !== null) {
      const bahn = el("div", "bahn");
      const fuellung = el("div", "fuellung");
      fuellung.style.width = `${Math.max(0, Math.min(100, o.anteil * 100)).toFixed(1)}%`;
      bahn.appendChild(fuellung);
      if (o.marke !== void 0 && o.marke > 0 && o.marke < 1) {
        const marke = el("div", "marke");
        marke.style.left = `${(o.marke * 100).toFixed(1)}%`;
        bahn.appendChild(marke);
      }
      z.appendChild(bahn);
    }
    if (o.fuss) z.appendChild(o.fuss);
    return z;
  }
  var EINHEIT_LANG = { AIC: "einheit.aic" };
  function einheitLesbar(e) {
    const schluessel = EINHEIT_LANG[e];
    return schluessel ? t(schluessel) : umlaute(e);
  }
  function kontingentZahl(v) {
    const stellen = Math.abs(v) >= 100 ? 0 : Math.abs(v) >= 10 ? 1 : 2;
    return v.toLocaleString(sprache() === "en" ? "en-US" : "de-DE", {
      minimumFractionDigits: 0,
      maximumFractionDigits: stellen
    });
  }
  function abschnittKontingente(d) {
    const liste = el("div", "balkenliste");
    let balken2 = 0;
    const woche = wochenbudget(d.limits ?? []);
    if (woche) {
      const fuss = el("div", "fuss");
      fuss.appendChild(document.createTextNode(`${t("wochen.erlaubt")} `));
      fuss.appendChild(el("b", void 0, prozent(woche.erlaubt)));
      fuss.appendChild(document.createTextNode(" \xB7 "));
      fuss.appendChild(
        document.createTextNode(
          woche.luft >= 0 ? t("wochen.luft", zahl(woche.luft)) : t("wochen.darueber", zahl(Math.abs(woche.luft)))
        )
      );
      liste.appendChild(
        balkenZeile({
          name: t("limit.7d"),
          wert: prozent(woche.verbraucht),
          anteil: woche.verbraucht / 100,
          marke: woche.erlaubt / 100,
          rechts: t("wochen.tag", woche.tag),
          fuss,
          lage: woche.luft < 0 ? "knapp" : void 0
        })
      );
      balken2 += 1;
    }
    const roh = d.kontingent;
    const harnesses = roh && typeof roh === "object" ? roh["harnesses"] : void 0;
    const ohne = [];
    const ohneStand = [];
    if (harnesses) {
      for (const [id, e] of Object.entries(harnesses)) {
        const kont = e["kontingent"] ?? {};
        const art = String(kont["art"] ?? "");
        const einheit = einheitLesbar(String(kont["einheit"] ?? ""));
        const verbraucht = typeof kont["verbraucht"] === "number" ? kont["verbraucht"] : NaN;
        const grenze = typeof kont["grenze"] === "number" ? kont["grenze"] : NaN;
        const rest = kont["rest"];
        const zurueck = kont["faellt_zurueck_am"];
        const erschoepft = e["erschoepft"] === true;
        if (art === "keins" || art === "" || !Number.isFinite(verbraucht)) {
          const wohin = art === "keins" || art === "" ? ohne : ohneStand;
          wohin.push({ wer: id, grund: umlaute(String(e["hinweis"] ?? "")) || t("kontingent.keins") });
          continue;
        }
        const teile2 = [];
        if (rest !== null && rest !== void 0) teile2.push(`${t("kontingent.rest")} ${String(rest)}`);
        if (zurueck) teile2.push(t("kontingent.zurueck", zeitpunkt(String(zurueck))));
        const hatGrenze = Number.isFinite(grenze) && grenze > 0;
        const bedeutung = hatGrenze ? einheit : [einheit, t("kontingent.verbraucht")].filter(Boolean).join(" ");
        const fuss = el("div", "fuss", bedeutung);
        if (erschoepft) {
          fuss.textContent = "";
          fuss.appendChild(el("b", void 0, t("kontingent.erschoepft")));
          if (bedeutung) fuss.appendChild(document.createTextNode(` \xB7 ${bedeutung}`));
        }
        liste.appendChild(
          balkenZeile({
            name: id,
            // Ohne Grenze keine Prozentzahl: dann steht der rohe Wert da, und der
            // Balken bleibt leer, statt einen Nenner zu behaupten.
            wert: hatGrenze ? prozent(verbraucht / grenze * 100) : kontingentZahl(verbraucht),
            anteil: hatGrenze ? verbraucht / grenze : null,
            rechts: teile2.join(" \xB7 "),
            fuss,
            lage: erschoepft ? "voll" : void 0
          })
        );
        balken2 += 1;
      }
    }
    const teile = [];
    if (balken2 > 0) teile.push(liste);
    if (!harnesses) {
      const grund = roh && typeof roh["fehler"] === "string" && roh["fehler"].trim() ? String(roh["fehler"]).trim() : t("kontingent.werkzeug.fehlt");
      const zeile = el("p", "hinweis", t("kontingent.fehlt"));
      zeile.dataset.grund = grund;
      zeile.title = t("kontingent.fehlt.tipp", grund);
      teile.push(zeile);
    }
    if (!woche) teile.push(el("p", "hinweis", t("wochen.fehlt")));
    for (const [ueberschrift, zeilen] of [
      [t("kontingent.ohnestand"), ohneStand],
      [t("kontingent.keins"), ohne]
    ]) {
      if (zeilen.length === 0) continue;
      teile.push(el("div", "untertitel", ueberschrift));
      const vorspann = gemeinsamerVorspann(zeilen.map((z) => z.grund));
      if (vorspann) teile.push(el("p", "hinweis", vorspann));
      const kasten = el("div");
      for (const z of zeilen) {
        const zeile = el("div", "ohnekontingent");
        zeile.appendChild(el("span", "wer", z.wer));
        zeile.appendChild(el("span", void 0, z.grund.slice(vorspann.length).trim()));
        kasten.appendChild(zeile);
      }
      teile.push(kasten);
    }
    return abschnitt(t("kontingent.titel"), ...teile);
  }
  function abschnittLimit(d) {
    if (!d.limits || d.limits.length === 0) {
      return abschnitt(t("limit.titel"), el("p", "hinweis", t("limit.leer")), el("p", "hinweis", t("limit.quelle")));
    }
    const kasten = el("div", "diagramme");
    for (const feld of ["five_hour_pct", "seven_day_pct"]) {
      const v = limitVerlauf(d.limits, feld);
      if (v.segmente.length === 0) continue;
      const diagramm = el("div", "diagramm");
      const kopf = el("div", "kopfzeile");
      kopf.appendChild(el("span", void 0, feld === "five_hour_pct" ? t("limit.5h") : t("limit.7d")));
      kopf.appendChild(el("span", void 0, v.zuletzt === null ? "" : t("limit.stand", prozent(v.zuletzt))));
      diagramm.appendChild(kopf);
      const breite = 560;
      const hoehe = 120;
      const svg = svgKnoten("svg", { viewBox: `0 0 ${breite} ${hoehe + 16}`, role: "img" });
      svg.appendChild(svgKnoten("line", { x1: 0, y1: hoehe, x2: breite, y2: hoehe, stroke: "var(--linie)" }));
      svg.appendChild(svgKnoten("line", { x1: 0, y1: 0, x2: breite, y2: 0, stroke: "var(--aus)", "stroke-dasharray": "3 4", opacity: 0.5 }));
      for (const seg of v.segmente) {
        svg.appendChild(
          svgKnoten("path", {
            d: linienPfad(seg, v.von, v.bis, v.hoechstwert, breite, hoehe),
            fill: "none",
            stroke: feld === "five_hour_pct" ? "var(--ein)" : "var(--cw)",
            "stroke-width": 1.5
          })
        );
      }
      for (const r of v.ruecksetzpunkte) {
        const x = (r - v.von) / (v.bis - v.von || 1) * breite;
        const linie = svgKnoten("line", { x1: x.toFixed(1), y1: 0, x2: x.toFixed(1), y2: hoehe, stroke: "var(--laeuft)", "stroke-dasharray": "2 3" });
        const titelKnoten = svgKnoten("title", {});
        titelKnoten.textContent = `${t("limit.reset")}: ${zeitpunkt(new Date(r).toISOString())}`;
        linie.appendChild(titelKnoten);
        svg.appendChild(linie);
      }
      diagramm.appendChild(svg);
      const fuss = el("div", "legende");
      fuss.appendChild(el("span", void 0, t("limit.reset.anzahl", v.ruecksetzpunkte.length)));
      if (v.naechsterReset) fuss.appendChild(el("span", void 0, t("limit.reset.naechster", zeitpunkt(new Date(v.naechsterReset).toISOString()))));
      diagramm.appendChild(fuss);
      kasten.appendChild(diagramm);
    }
    return abschnitt(t("limit.titel"), kasten, el("p", "hinweis", t("limit.quelle")));
  }
  var SITZUNGEN_MAX = 40;
  function abschnittSitzungen(sitzungen) {
    const gezeigt = sitzungen.slice(0, SITZUNGEN_MAX);
    const zeilen = gezeigt.map((z) => [
      z.harness,
      z.worker || t("sitzung.ohne_worker"),
      z.sitzung.slice(0, 12),
      z.modelle.join(", "),
      zahl(ohneCacheRead(z)),
      zahl(z.output),
      zahl(z.cache_read),
      `${zeitpunkt(z.von)} \u2013 ${zeitpunkt(z.bis)}`
    ]);
    const teile = [
      tabelle(
        [
          { text: t("harness.spalte") },
          { text: t("sitzung.worker") },
          { text: t("sitzung.spalte") },
          { text: t("modell.spalte") },
          { text: t("summe.gesamt"), zahl: true },
          { text: t("summe.output"), zahl: true },
          { text: t("summe.cache_read"), zahl: true },
          { text: t("sitzung.zeitraum") }
        ],
        zeilen
      )
    ];
    if (sitzungen.length > gezeigt.length) {
      teile.push(el("p", "hinweis", t("sitzung.mehr", sitzungen.length - gezeigt.length)));
    }
    if (sitzungenTeilweise(sitzungen, auswahl)) {
      teile.push(el("p", "hinweis einschraenkung", t("filter.aktiv")));
    }
    return abschnitt(t("sitzung.titel"), ...teile);
  }
  function vergleichsTabelle(zeilen, beschriftung) {
    return tabelle(
      [
        { text: "" },
        { text: t("vergleich.jetzt"), zahl: true },
        { text: t("vergleich.vorher"), zahl: true },
        { text: t("vergleich.differenz"), zahl: true },
        { text: "", zahl: true }
      ],
      zeilen.map((z) => {
        const zeichen = z.richtung === "mehr" ? t("zeichen.mehr") : z.richtung === "weniger" ? t("zeichen.weniger") : t("zeichen.gleich");
        const p = el("span", z.richtung);
        p.textContent = z.prozent === null ? t("vergleich.kein_vorher") : `${zeichen} ${prozent(Math.abs(z.prozent))}`;
        return [beschriftung(z.schluessel), zahl(z.jetzt), zahl(z.vorher), zahl(z.differenz), p];
      })
    );
  }
  function abschnittVergleich(d, gefiltert) {
    if (!vergleichAn) return null;
    if (!vergleichsDaten) return abschnitt(t("vergleich.titel"), el("p", "hinweis", t("vergleich.laedt")));
    const vorherModelle = filterModelle(vergleichsDaten.je_modell, auswahl);
    const jetztWerte = summiere(gefiltert);
    const vorherWerte = summiere(vorherModelle);
    const spanne = el(
      "p",
      "hinweis",
      `${t("vergleich.jetzt")}: ${zeitpunkt(d.fenster.von)} \u2013 ${zeitpunkt(d.fenster.bis)} \xB7 ${t("vergleich.vorher")}: ${zeitpunkt(vergleichsDaten.fenster.von)} \u2013 ${zeitpunkt(vergleichsDaten.fenster.bis)}`
    );
    return abschnitt(
      t("vergleich.titel"),
      spanne,
      vergleichsTabelle(vergleicheWerte(jetztWerte, vorherWerte), (s) => t(`summe.${s}`)),
      el("p", "hinweis", t("harness.titel")),
      vergleichsTabelle(
        vergleicheHarnesses(
          harnessAuswahlliste(gefiltert).map((h) => ({ ...summiere(gefiltert.filter((z) => z.harness === h.id)), harness: h.id })),
          harnessAuswahlliste(vorherModelle).map((h) => ({ ...summiere(vorherModelle.filter((z) => z.harness === h.id)), harness: h.id }))
        ),
        (s) => s
      )
    );
  }
  function abschnittLuecken(d) {
    const zeilen = (d.luecken ?? []).map((l) => [l.harness, umlaute(l.grund)]);
    return abschnitt(
      t("luecke.titel"),
      el("p", "hinweis", t("luecke.einleitung")),
      tabelle([{ text: t("luecke.spalte") }, { text: t("luecke.grund") }], zeilen)
    );
  }
  function abschnittQuellen(d) {
    const zeilen = (d.quellen ?? []).map((q) => {
      const zeichen = el("span", "marke-art " + (q.zustand === "gelesen" ? "gemessen" : q.zustand === "unlesbar" ? "fehlt" : ""), t(`zeichen.${q.zustand}`));
      zeichen.title = t(`quelle.zustand.${q.zustand}`);
      return [
        q.harness,
        zeichen,
        t(`quelle.zustand.${q.zustand}`),
        q.pfad,
        t("quelle.nachrichten", zahl(q.nachrichten)),
        el("span", "fein", umlaute(q.hinweis))
      ];
    });
    return abschnitt(
      t("quelle.titel"),
      tabelle(
        [
          { text: t("harness.spalte") },
          { text: "" },
          { text: "" },
          { text: t("quelle.spalte") },
          { text: "", zahl: true },
          { text: t("luecke.grund") }
        ],
        zeilen
      )
    );
  }
  function zeichne() {
    zeichneZeitraum();
    if (!daten) return;
    const d = daten;
    const alleModelle = d.je_modell ?? [];
    chipReihe(filterHarnessEl, t("filter.harness"), harnessAuswahlliste(alleModelle), auswahl.harness, (id) => umschalten(auswahl.harness, id), "harness");
    chipReihe(
      filterModellEl,
      t("filter.modell"),
      modellAuswahlliste(alleModelle, auswahl).map((m) => ({ id: m.id, tokens: m.tokens })),
      auswahl.modell,
      (id) => umschalten(auswahl.modell, id),
      "modell"
    );
    const gefiltert = filterModelle(alleModelle, auswahl);
    const gesamt = summiere(gefiltert);
    standEl.textContent = t("stand", zeitpunkt(d.erzeugt), zeitpunkt(d.fenster.von), zeitpunkt(d.fenster.bis));
    inhaltEl.replaceChildren();
    inhaltEl.appendChild(abschnittKontingente(d));
    inhaltEl.appendChild(abschnittSummen(gesamt));
    inhaltEl.appendChild(abschnittTage(d, filterTage(d.je_tag ?? [], auswahl), gesamt));
    inhaltEl.appendChild(abschnittHarnesses(gefiltert));
    inhaltEl.appendChild(abschnittModelle(gefiltert));
    inhaltEl.appendChild(abschnittTempo(gefiltert));
    inhaltEl.appendChild(abschnittKosten(gefiltert));
    inhaltEl.appendChild(abschnittLimit(d));
    inhaltEl.appendChild(abschnittSitzungen(filterSitzungen(d.je_sitzung ?? [], auswahl)));
    const v = abschnittVergleich(d, gefiltert);
    if (v) inhaltEl.appendChild(v);
    inhaltEl.appendChild(abschnittLuecken(d));
    inhaltEl.appendChild(abschnittQuellen(d));
  }
  function zeigeFehler(text) {
    inhaltEl.replaceChildren();
    const k = el("div");
    k.id = "fehler";
    k.appendChild(el("div", void 0, t("fehler.titel")));
    k.appendChild(el("div", "fein", text));
    inhaltEl.appendChild(k);
  }
  async function laden() {
    setzeStatus(t("laden"));
    zeichneZeitraum();
    const antwort = await window.awbVerbrauch.daten({ tage });
    if (!antwort || !antwort.ok || !antwort.daten) {
      daten = null;
      zeigeFehler(antwort?.fehler ?? t("fehler.titel"));
      setzeStatus(antwort?.fehler ?? t("fehler.titel"));
      return;
    }
    daten = antwort.daten;
    setzeStatus("");
    zeichne();
    if (vergleichAn && !vergleichsDaten) void ladeVergleich();
  }
  async function ladeVergleich() {
    if (!daten) return;
    const zeitraum = vorherigerZeitraum(daten.fenster.von, daten.fenster.bis);
    if (!zeitraum) return;
    setzeStatus(t("vergleich.laedt"));
    zeichne();
    const antwort = await window.awbVerbrauch.daten(zeitraum);
    if (antwort && antwort.ok && antwort.daten) {
      vergleichsDaten = antwort.daten;
      setzeStatus("");
    } else {
      setzeStatus(antwort?.fehler ?? t("fehler.titel"));
    }
    zeichne();
  }
  window.__awbVerbrauch = {
    text: () => document.body.innerText,
    status: () => status,
    klick: (a) => {
      const e = document.querySelector(a);
      if (!e) return false;
      e.click();
      return true;
    },
    zustand: (a) => {
      const e = document.querySelector(a);
      if (!e) return { da: false, gesperrt: false, wert: "", text: "" };
      return {
        da: true,
        gesperrt: e.disabled === true,
        wert: e.value ?? "",
        text: e.textContent ?? ""
      };
    },
    abschnitte: () => [...document.querySelectorAll("section")].map((s) => s.dataset.abschnitt ?? "")
  };
  function themaAnwenden(d) {
    document.documentElement.dataset.thema = d.wirksam;
  }
  window.awbVerbrauch.onThema(themaAnwenden);
  void window.awbVerbrauch.thema().then(themaAnwenden);
  void (async () => {
    setzeSprache(await window.awbVerbrauch.sprache());
    kopfzeileBeschriften();
    await laden();
    window.awbVerbrauch.bereit();
  })();
})();
