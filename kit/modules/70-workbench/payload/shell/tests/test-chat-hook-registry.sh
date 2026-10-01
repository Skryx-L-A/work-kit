#!/usr/bin/env bash
# test-chat-hook-registry.sh — die ECHTEN session.hook-Eintraege aus
# shell/models.default.json gegen die Hook-Installation in wb-harness-run
# (SPEC-V4 6.3 Punkt 4, Eintraege nachgetragen 2026-08-11).
#
# UNTERSCHIED zu test-chat-hook-installation.sh: jene Suite tippt ihre
# Hook-Bloecke von Hand und prueft damit den MECHANISMUS. Diese Suite nimmt
# stattdessen die claude- und codex-Eintraege WOERTLICH aus der ausgelieferten
# Registry (Python liest sie ein, kein Abtippen) — sie faengt einen Tippfehler
# oder eine falsche Verschachtelung in MEINEN Eintraegen, den ein von Hand
# gebauter Testfall nie sehen wuerde.
#
# WAS HIER HAENGT:
#   1  claude traegt zuordnung 'hook' schon in der Auslieferung — der Eintrag
#      installiert sich unveraendert, mit GENAU dem event/matcher/timeout, die
#      in der Registry stehen.
#   2  codex traegt session.hook jetzt auch, aber zuordnung bleibt 'cwd' — der
#      Mechanismus greift deshalb HEUTE nicht, und das ist keine Luecke,
#      sondern Absicht (siehe die Begruendung im session.probe.beleg von
#      codex): der Wechsel auf 'hook' braucht einen eigenen Beleg, dass die
#      SessionStart-Nutzlast von codex ueberhaupt eine Sitzungskennung traegt,
#      die zum Rollout-Dateinamen passt.
#   3  Der codex-Block SELBST ist trotzdem korrekt: mit zuordnung probehalber
#      auf 'hook' gesetzt (NUR fuer diese eine Zusage, keine Behauptung ueber
#      den heutigen Stand) installiert er hooks.json in genau der Form, die
#      auf dieser Maschine bereits ein fremder, von jcode gesetzter Hook
#      belegt (~/.codex/hooks.json, [hooks.state."<datei>:session_start:0:0"]
#      in ~/.codex/config.toml) — und meldet ohne trustedHash sichtbar, dass
#      codex ihn nicht ausfuehren wird, statt still zu bleiben.
#
# ISOLATION: eigenes HOME, eigenes TMPDIR, ein Stub fuer wb-state (cat einer
# Datei), keine tmux, kein echter codex/claude. Nur die ausgelieferte Registry
# wird gelesen, nie geschrieben.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUF="$REPO/shell/wb-harness-run"
REG="$REPO/shell/models.default.json"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-chathookreg.XXXXXX")" && pwd)"
export TMPDIR="$TESTHOME/tmp"
mkdir -p "$TESTHOME/.local/bin" "$TESTHOME/.claude" "$TESTHOME/.codex" "$TMPDIR"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT INT TERM

echo "== Hook-Installation gegen die echten Registry-Eintraege =="
echo "Geprueft: $LAUF gegen $REG"

cat > "$TESTHOME/.local/bin/wb-state" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "models resolve")
    printf 'harness\t%s\n' "$WB_TEST_HARNESS"
    printf 'cmd\t/usr/bin/true\n'
    ;;
  "harness get")
    cat "$WB_TEST_HJSON"
    ;;
esac
exit 0
STUB
chmod +x "$TESTHOME/.local/bin/wb-state"

lauf() { # lauf <harness-id> <json-datei>
  env HOME="$TESTHOME" TMPDIR="$TMPDIR" WB_TEST_HARNESS="$1" WB_TEST_HJSON="$2" \
    bash "$LAUF" --model testmodell --role worker --dir "$TESTHOME" 2>&1
}

# --- die zwei echten Eintraege aus der Registry, wortgetreu -------------------
CLAUDE_ECHT="$TESTHOME/claude-echt.json"
CODEX_ECHT="$TESTHOME/codex-echt.json"
CODEX_HOOK_MIT_HOOK_ZUORDNUNG="$TESTHOME/codex-hook-zuordnung.json"
/usr/bin/python3 - "$REG" "$CLAUDE_ECHT" "$CODEX_ECHT" "$CODEX_HOOK_MIT_HOOK_ZUORDNUNG" <<'PY'
import json, sys
reg, claude_out, codex_out, codex_hookzu_out = sys.argv[1:5]
d = json.load(open(reg))
h = {x["id"]: x for x in d["harnesses"]}
claude = h["claude"]
codex = h["codex"]
assert claude["session"]["zuordnung"] == "hook", "claude soll schon ueber hook zugeordnet sein"
assert isinstance(claude["session"].get("hook"), dict), "claude braucht session.hook"
assert isinstance(codex["session"].get("hook"), dict), "codex braucht session.hook"
json.dump(claude, open(claude_out, "w"))
json.dump(codex, open(codex_out, "w"))
# Kopie mit zuordnung probehalber auf 'hook' -- NUR um den hook-Block selbst zu
# pruefen, keine Behauptung ueber den heutigen Stand der Registry (siehe oben).
codex_probehalber = json.loads(json.dumps(codex))
codex_probehalber["session"]["zuordnung"] = "hook"
json.dump(codex_probehalber, open(codex_hookzu_out, "w"))
PY

# Die drei Werte, die MEIN Eintrag fuer claude traegt -- direkt aus der Registry
# gelesen, nicht hier noch einmal von Hand behauptet.
read -r CLAUDE_EVENT CLAUDE_MATCHER CLAUDE_TIMEOUT <<EOF
$(/usr/bin/python3 -c "
import json
h = json.load(open('$CLAUDE_ECHT'))
hk = h['session']['hook']
print(hk['event'], hk['matcher'], hk['timeout'])
")
EOF

HAKEN="$TESTHOME/.claude/workbench/chat-zuordnung.sh"

# --- 1: claude, wortgetreu aus der Registry -----------------------------------
printf '%s\n' '{}' > "$TESTHOME/.claude/settings.json"
AUSGABE="$(lauf claude "$CLAUDE_ECHT")"
[ -x "$HAKEN" ] && ok "1: der Haken entsteht aus dem echten claude-Eintrag" \
  || bad "1: $HAKEN fehlt"
if /usr/bin/python3 - "$TESTHOME/.claude/settings.json" "$HAKEN" "$CLAUDE_EVENT" "$CLAUDE_MATCHER" "$CLAUDE_TIMEOUT" <<'PY'
import json, sys
ziel, haken, event, matcher, timeout = sys.argv[1:6]
d = json.load(open(ziel))
gruppen = (d.get("hooks") or {}).get(event) or []
treffer = [e for g in gruppen for e in (g.get("hooks") or []) if e.get("command") == haken]
sys.exit(0 if treffer and treffer[0].get("timeout") == int(timeout) and
         any(g.get("matcher") == matcher for g in gruppen) else 1)
PY
then ok "1: settings.json traegt event/matcher/timeout genau wie in der Registry"
else bad "1: der Eintrag in settings.json weicht von der Registry ab"; fi
case "$AUSGABE" in *"Chat-Zuordnung als SessionStart-Hook"*) ok "1: die Ausgabe bestaetigt den Eintrag" ;;
  *) bad "1: keine Bestaetigung (Ausgabe: $AUSGABE)" ;; esac

# --- 2: codex, wortgetreu aus der Registry (zuordnung bleibt 'cwd') -----------
AUSGABE="$(lauf codex "$CODEX_ECHT")"
[ -f "$TESTHOME/.codex/hooks.json" ] \
  && bad "2: der echte codex-Eintrag (zuordnung cwd) hat trotzdem einen Hook installiert" \
  || ok "2: der echte codex-Eintrag installiert heute nichts -- zuordnung ist noch 'cwd'"
[ -z "$AUSGABE" ] || case "$AUSGABE" in *"Chat-Zuordnung"*|*"NICHT ausfuehren"*)
    bad "2: trotz zuordnung 'cwd' kam eine Hook-Meldung (Ausgabe: $AUSGABE)" ;;
  *) ok "2: keine Hook-Meldung, wie es fuer 'cwd' sein soll" ;; esac

# --- 3: derselbe codex-hook-Block, probehalber mit zuordnung 'hook' ----------
# Zeigt: der Block selbst ist korrekt und installierbar. Keine Aussage ueber die
# echte Registry (dort bleibt zuordnung 'cwd', siehe Test 2).
printf '%s\n' '[projects."/x"]' 'trust_level = "trusted"' > "$TESTHOME/.codex/config.toml"
AUSGABE="$(lauf codex "$CODEX_HOOK_MIT_HOOK_ZUORDNUNG")"
[ -f "$TESTHOME/.codex/hooks.json" ] && ok "3: mit zuordnung 'hook' installiert derselbe Block hooks.json" \
  || bad "3: hooks.json fehlt trotz zuordnung 'hook'"
if /usr/bin/python3 - "$TESTHOME/.codex/hooks.json" "$HAKEN" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
g = (d.get("hooks") or {}).get("SessionStart") or []
sys.exit(0 if any(e.get("command") == sys.argv[2] for gr in g for e in (gr.get("hooks") or [])) else 1)
PY
then ok "3: der Eintrag in hooks.json zeigt auf den Haken"
else bad "3: hooks.json traegt den Haken nicht"; fi
case "$AUSGABE" in *"NICHT ausfuehren"*) ok "3: ohne trustedHash meldet es sichtbar, dass codex nicht ausfuehrt" ;;
  *) bad "3: keine Meldung ueber den fehlenden trusted_hash (Ausgabe: $AUSGABE)" ;; esac
grep -q "trusted_hash" "$TESTHOME/.codex/config.toml" \
  && bad "3: ohne trustedHash wurde trotzdem ein Vertrauenseintrag geschrieben" \
  || ok "3: config.toml bleibt ohne trustedHash unangetastet"
grep -q '\[projects."/x"\]' "$TESTHOME/.codex/config.toml" \
  && ok "3: der bestehende Vertrauensspeicher blieb stehen" \
  || bad "3: config.toml hat ihren bisherigen Abschnitt verloren"

# --- 4: derselbe Block, jetzt MIT einer (gueltig geformten) Pruefsumme -------
# Schluesselform "<datei>:session_start:0:0" ist an der echten config.toml
# dieser Maschine abgelesen (von jcode installiert, siehe Ergebnisbericht).
rm -f "$TESTHOME/.codex/hooks.json"
HASH="sha256:$(printf 'testinhalt' | shasum -a 256 | cut -d' ' -f1)"
/usr/bin/python3 - "$CODEX_HOOK_MIT_HOOK_ZUORDNUNG" "$TESTHOME/codex-mit-hash.json" "$HASH" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["session"]["hook"]["trustedHash"] = sys.argv[3]
json.dump(d, open(sys.argv[2], "w"))
PY
lauf codex "$TESTHOME/codex-mit-hash.json" >/dev/null
SCHLUESSEL="$TESTHOME/.codex/hooks.json:session_start:0:0"
if grep -qF "[hooks.state.\"$SCHLUESSEL\"]" "$TESTHOME/.codex/config.toml" && grep -q "$HASH" "$TESTHOME/.codex/config.toml"; then
  ok "4: mit trustedHash steht der Vertrauenseintrag in codex-Schreibweise da"
else
  bad "4: der Vertrauenseintrag fehlt oder heisst anders"
fi

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
