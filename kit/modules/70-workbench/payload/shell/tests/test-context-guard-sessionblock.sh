#!/usr/bin/env bash
# test-context-guard-sessionblock.sh — der gemeinsame session-Block der Registry
# (SPEC-V4 Abschnitt 6.3, gebaut 2026-08-11).
#
# Anlass: Bis zum 11.08. beschrieb contextSession die Sitzungsdatei NUR fuer die
# Kontextwache. Seit dem 11.08. beschreibt EIN Block sie fuer die Wache UND fuer die
# Chat-Ansicht, und contextSession gibt es nicht mehr. Der Umbau ist hart: kein
# Uebergang, der beide Felder liest. Zwei Felder ueber dieselbe Datei waren am 06.08.
# der Grund fuer sieben tote Schalter; ein zweites Mal soll das nicht passieren.
#
# Geprueft wird:
#   1  contextSession kommt in der Auslieferung und im Werkzeug nicht mehr vor, und
#      jeder der achtzehn Harness-Eintraege hat einen session-Block mit Messdatum.
#   2  Der Block ist wohlgeformt: via aus vier Werten, Grund im Klartext, wo er leer
#      ist, eingabe 'pane', zeigtNicht nur aus dem vereinbarten Vokabular, und wo ein
#      lokaler Server im Spiel ist, stehen Bindung und Token IM Eintrag (Punkt 5).
#   3  SESS_FORMATE in context-guard und der Verteiler in session_load() nennen
#      DIESELBEN Formatnamen. Die Doppelung ist angemeldet, hier steht ihr Test.
#      Der Verteiler selbst liegt seit dem 11.08. in shell/wb-session-load
#      (herausgeloest, damit die Oberflaeche denselben Leser ruft statt ihn ein
#      zweites Mal in TypeScript nachzubauen) -- geprueft wird dort.
#   4  Die Torwaechter-Regel: die Wache zieht den Block nur heran, wenn via
#      'sessionFile' ist UND sie den Formatnamen kennt. Ein Block fuer die
#      Chat-Ansicht allein (claude-transcript, opencode-http) darf sie NICHT als
#      fuenfte Quelle zaehlen — sonst meldet sie einen Pane als bewacht, aus dem sie
#      nichts lesen kann. Geprueft am echten Ausschnitt aus context-guard.
#   5  Die acht Eintraege, die die Wache heute liest, lesen sich weiterhin: codex,
#      aider, crush, gptme, copilot, copilot-cloud, cline, openhands.
#   6  'wb-state models migrate-session' traegt die ausgelieferten Bloecke in eine
#      gepflegte Registry ein, entfernt contextSession im selben Zug und schreibt sein
#      Aenderungsprotokoll NEBEN die umgebogene Datei, nicht in die echte Geschichte.
#
# Alles laeuft gegen Dateien: die ausgelieferte Registry, den Quelltext von
# context-guard und eine Wegwerf-Registry unter eigenem HOME. Kein tmux, kein Harness,
# keine laufende Sitzung.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
REG="$REPO/models.default.json"
GUARD="$REPO/context-guard"
# Der Verteiler von session_load() liegt seit 2026-08-11 nicht mehr in
# context-guard selbst, sondern ausgelagert in wb-session-load (EIN Leser fuer
# die Wache UND das Worker-Modell der Oberflaeche, siehe dessen Kopfkommentar).
LOADER="$REPO/wb-session-load"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-sessionblock.XXXXXX")" && pwd)"
export HOME="$TESTHOME"
export WB_NO_DISCOVER=1
mkdir -p "$TESTHOME/.claude/workbench" "$TESTHOME/.local/bin" "$TESTHOME/.local/state"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT INT TERM

echo "== test-context-guard-sessionblock =="
echo "Geprueft: $REG und $GUARD"

# ── 1 und 2: die Auslieferung ────────────────────────────────────────────────────────
BERICHT="$(/usr/bin/python3 - "$REG" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
VIA = ("sessionFile", "http-sse", "acp", "")
WORT = ("freigabedialog", "kontextauslastung", "arbeits-anzeige")
fehler = []
for h in d["harnesses"]:
    hid = h["id"]
    if "contextSession" in h:
        fehler.append("%s traegt noch contextSession" % hid)
    s = h.get("session")
    if not isinstance(s, dict):
        fehler.append("%s hat keinen session-Block" % hid); continue
    if s.get("via") not in VIA:
        fehler.append("%s: via '%s' ist keiner der vier Werte" % (hid, s.get("via")))
    if s.get("via") == "" and not (s.get("grund") or "").strip():
        fehler.append("%s: via leer, aber kein Grund im Klartext" % hid)
    if s.get("eingabe") != "pane":
        fehler.append("%s: eingabe '%s' statt 'pane'" % (hid, s.get("eingabe")))
    if not isinstance(s.get("live"), bool):
        fehler.append("%s: live ist kein Ja/Nein" % hid)
    for w in (s.get("zeigtNicht") or []):
        if w not in WORT:
            fehler.append("%s: zeigtNicht kennt '%s' nicht" % (hid, w))
    p = s.get("probe") or {}
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", str(p.get("datum") or "")):
        fehler.append("%s: probe.datum fehlt oder ist kein Datum" % hid)
    if not (p.get("beleg") or "").strip():
        fehler.append("%s: probe.beleg fehlt" % hid)
    if s.get("via") == "sessionFile" and not (s.get("ort") and s.get("format")):
        fehler.append("%s: via sessionFile ohne ort/format" % hid)
    if s.get("via") == "http-sse":
        srv = s.get("server") or {}
        if not srv.get("bind") or not srv.get("token"):
            fehler.append("%s: lokaler Server ohne Bindung/Token im Eintrag" % hid)
print("\n".join(fehler) if fehler else "SAUBER")
print("ANZAHL %d" % len(d["harnesses"]))
PY
)"
ANZ="$(printf '%s\n' "$BERICHT" | sed -n 's/^ANZAHL //p')"
MELD="$(printf '%s\n' "$BERICHT" | grep -v '^ANZAHL ')"
[ "$MELD" = "SAUBER" ] \
  && ok "1+2: alle $ANZ Harness-Eintraege haben einen wohlgeformten session-Block mit Messdatum, keiner traegt noch contextSession" \
  || bad "1+2: $MELD"
grep -q '"contextSession"' "$REG" \
  && bad "1: contextSession steht noch in der ausgelieferten Registry" \
  || ok "1: contextSession steht nirgends mehr in der ausgelieferten Registry"
# Im Werkzeug darf der Name nur noch als Geschichte vorkommen (Kommentarzeilen), nie
# als gelesenes Feld.
if grep -n 'contextSession' "$GUARD" | grep -qv '^[0-9]*:#'; then
  bad "1: context-guard liest ausserhalb der Kommentare noch contextSession"
else
  ok "1: context-guard nennt contextSession nur noch im Kommentar, liest es nicht mehr"
fi

# ── 3: die angemeldete Doppelung ─────────────────────────────────────────────────────
[ -x "$LOADER" ] || bad "3: wb-session-load fehlt oder ist nicht ausfuehrbar ($LOADER)"
AUS_LISTE="$(sed -n 's/^SESS_FORMATE="\(.*\)"$/\1/p' "$GUARD" | tr ' ' '\n' | sort | tr '\n' ' ')"
AUS_CODE="$(grep -oE 'fmt == "[a-z-]+"' "$LOADER" | sed 's/.*"\(.*\)"/\1/' | sort -u | tr '\n' ' ')"
[ -n "$AUS_LISTE" ] && ok "3: SESS_FORMATE ist gesetzt: $AUS_LISTE" || bad "3: SESS_FORMATE fehlt in context-guard"
[ "$AUS_LISTE" = "$AUS_CODE" ] \
  && ok "3: SESS_FORMATE (context-guard) und der Verteiler in wb-session-load nennen dieselben Formate" \
  || bad "3: SESS_FORMATE nennt '$AUS_LISTE', der Verteiler in wb-session-load aber '$AUS_CODE' — eine der beiden Stellen ist nachgezogen worden, die andere nicht"

# ── 4: der Torwaechter, am echten Ausschnitt ────────────────────────────────────────
TOR="$TESTHOME/torwaechter.py"
/usr/bin/python3 - "$GUARD" "$TOR" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
marke = "h = json.load(sys.stdin)"
i = src.index(marke)
j = src.index("\n' \"$SESS_FORMATE\"", i)
open(sys.argv[2], "w", encoding="utf-8").write("import json, sys\n" + src[i:j] + "\n")
PY
[ -s "$TOR" ] && ok "4: der Torwaechter aus harness_info ist herausgeloest" \
  || bad "4: der Torwaechter liess sich nicht herausloesen"

torfrage() {   # <harness-id> -> das dritte Feld (der weitergereichte session-Block)
  /usr/bin/python3 - "$REG" "$1" <<'PY' | /usr/bin/python3 "$TOR" "$SESS_FORMATE" | tr '\002' '\t' | cut -f3
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(json.dumps(next(h for h in d["harnesses"] if h["id"] == sys.argv[2])))
PY
}
export SESS_FORMATE="$(sed -n 's/^SESS_FORMATE="\(.*\)"$/\1/p' "$GUARD")"
TOR="$TOR" ; export TOR

[ -n "$(torfrage codex)" ] \
  && ok "4: codex (codex-rollout) kommt bei der Wache an" \
  || bad "4: codex kommt NICHT an — die fuenfte Quelle waere fuer ihn tot"
[ -z "$(torfrage claude)" ] \
  && ok "4: claude (claude-transcript) kommt NICHT an — die Wache hat fuer dieses Format keinen Leser" \
  || bad "4: claude kommt an, obwohl die Wache 'claude-transcript' nicht lesen kann"
[ -z "$(torfrage opencode)" ] \
  && ok "4: opencode (http-sse) kommt NICHT an — ein Serverkanal ist keine Sitzungsdatei" \
  || bad "4: opencode kommt an, obwohl sein Weg ein HTTP-Kanal ist"
[ -z "$(torfrage forge)" ] \
  && ok "4: forge (via leer) kommt NICHT an" \
  || bad "4: forge kommt an, obwohl er es nach eigener Auskunft nicht kann"
[ -z "$(torfrage nanocoder)" ] \
  && ok "4: nanocoder (nanocoder-sessions) kommt NICHT an — die Datei traegt Rolle und Text, aber keine Tokenzahl" \
  || bad "4: nanocoder kommt an, obwohl seine Sitzungsdatei keine Tokenzahlen traegt"

# ── 5: die acht, die die Wache heute liest ──────────────────────────────────────────
FEHLT=""
for H in codex aider copilot copilot-cloud; do  # Kit: crush, gptme, cline, openhands are not shipped
  [ -n "$(torfrage "$H")" ] || FEHLT="$FEHLT $H"
done
[ -z "$FEHLT" ] \
  && ok "5: alle ausgelieferten Harnesses mit lesbarer Sitzungsdatei kommen weiterhin an" \
  || bad "5: die Wache verlor ihre Quelle fuer:$FEHLT"

# ── 6: die Migration der gepflegten Registry ────────────────────────────────────────
WBS="$TESTHOME/.local/bin/wb-state"
cp "$REPO/wb-state" "$WBS"; chmod +x "$WBS"
ALT="$TESTHOME/alt-models.json"
/usr/bin/python3 - "$ALT" <<'PY'
import json, sys
# Eine Registry im Stand VOR dem 11.08.: contextSession, kein session-Block.
json.dump({"version": 1,
           "providers": [{"id": "p", "label": "P", "kind": "subscription"}],
           "harnesses": [
             {"id": "codex", "label": "codex", "command": "codex", "args": [],
              "cwdMode": "cd", "readyPattern": "x",
              "contextSession": {"format": "codex-rollout",
                                 "path": "~/.codex/sessions/*/*/*/rollout-*.jsonl"}},
             {"id": "eigenbau", "label": "Eigenbau", "command": "eigenbau", "args": [],
              "cwdMode": "cd", "readyPattern": "x"}],
           "models": [{"id": "m", "label": "M", "harness": "codex", "provider": "p",
                       "modelRef": "r", "roles": ["worker"]}]},
          open(sys.argv[1], "w"), indent=2)
PY
MIGOUT="$(WB_MODELS_FILE="$ALT" "$WBS" models migrate-session --from "$REG" 2>&1)"
/usr/bin/python3 - "$ALT" <<'PY' && ok "6: die Migration traegt session ein und entfernt contextSession" \
  || bad "6: die Migration hat den Eintrag nicht sauber umgestellt"
import json, sys
d = json.load(open(sys.argv[1]))
h = next(x for x in d["harnesses"] if x["id"] == "codex")
assert "contextSession" not in h, "contextSession blieb stehen"
assert (h.get("session") or {}).get("format") == "codex-rollout", h.get("session")
assert (h.get("session") or {}).get("via") == "sessionFile"
assert len(d["models"]) == 1, "die Modelle haben den Schreibvorgang nicht ueberlebt"
PY
printf '%s\n' "$MIGOUT" | grep -q "eigenbau" \
  && ok "6: ein handgepflegter Eintrag ohne session-Block wird GENANNT, statt still unbewacht zu bleiben" \
  || bad "6: der Eintrag 'eigenbau' ohne session-Block wurde nicht gemeldet: $MIGOUT"
[ -s "$ALT.changes.log" ] \
  && ok "6: das Aenderungsprotokoll liegt neben der umgebogenen Registry" \
  || bad "6: kein Protokoll neben $ALT — dann schrieb der Lauf in die echte Geschichte"
[ -e "$TESTHOME/.local/state/wb-models-changes.log" ] \
  && bad "6: der Lauf schrieb trotz WB_MODELS_FILE in das Protokoll der echten Registry" \
  || ok "6: das Protokoll der echten Registry blieb unberuehrt"

echo
echo "== $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
