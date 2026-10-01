#!/usr/bin/env bash
# test-pi-worker-kv-schluessel.sh -- pi-worker muss fuer die "eigene Sequenz
# buchen"-Stufe (shell/pi-worker, "Eigene Sequenz buchen") den KV-Schluessel
# aus dem Modellkoerper holen, der WIRKLICH laeuft -- nicht aus dem Namen, den
# `pi` als --model bekommt.
#
# ANLASS (gemessen 2026-08-21, 05:10, Ergebnis 20260821-050834.md): auf der
# echten Maschine lief ein mtplx-Server (bauart "eingebaut", Registry-Feld
# vorhersage.modell ersetzt den Koerper lmgamma-27b-mlx-4bit durch
# Lmgamma-27B-MTPLX-Optimized-Speed) mit 24,7 GiB gebucht. Vier lokale
# Worker scheiterten danach alle sofort mit "pi-worker rc=1" -- ihre eigene
# Sequenzbuchung wurde abgelehnt. Nachgestellt mit einer reinen Abfrage:
#   wb-belegung darf --gewichte-gb 0.001 --modell mtplx-lmgamma-27b-optimized-speed \
#     --parallel 1 --kontext 32768 --ohne-sockel --json
# ergab spitze_gib=39.261 statt der rund 1,06 GiB, die 32768 Token bei dem
# gemessenen KV-Wert 0,033203 MiB/Token wirklich kosten -- fast das
# Vierzehnfache. URSACHE: pi-worker bildete den KV-Schluessel (BMODELL) als
# basename(MODEL), aber MODEL traegt seit der --bedient-als-Aenderung in
# wb-kontext den Namen, den PI ALS MODELL BEKOMMT (den bedienten Servernamen
# bei mtplx) -- eine ganz andere Aufgabe als der KV-Schluessel, der
# Verzeichnisname des Modellkoerpers.
#
# DIE ZUSAGEN, die hier hergestellt und gemessen werden:
#   1  Ein Worker mit bauart "eingebaut" (vorhersage.modell ersetzt den
#      Koerper) bucht fuer 32768 Token den KV-Anteil des wirklich laufenden
#      Koerpers (0,001 Sockel + 32768 x 0,033203 MiB KV + 2,3 GiB Zuschlag je
#      Sequenz, ohne_sockel = rund 3,36 GiB) -- nicht den grossen
#      "unbekannt"-Ersatzwert (mit dem hungrigsten gemessenen Wert waeren es
#      rund 39 GiB, exakt der auf der echten Maschine gemessene Wert).
#   2  --bedient-als wird an 'wb-kontext ensure' durchgereicht: der Name, den
#      der Server WIRKLICH bedient (aus 'wb-mlx-server ensure's stdout-Zeile
#      'modell=...'), landet als das, was pi als --model bekommt.
#   3  Der bediente Name (Zusage 2) und der KV-Schluessel (Zusage 1) sind
#      NICHT dasselbe -- der bediente Name trifft in kv-bedarf.json keinen
#      Eintrag, der Verzeichnisname des Koerpers schon.
#
# GEGENPROBE, getrennt gehalten: dass ein wirklich unbekanntes Modell weiterhin
# den grossen Ersatzwert bekommt UND die Antwort das sagt, ist bereits in
# test-belegung.sh Abschnitt 6 (kv_ersatzwert) geprueft -- dort isoliert, ohne
# den ganzen pi-worker-Apparat. Diese Datei prueft nur, dass pi-worker den
# RICHTIGEN Schluessel uebergibt.
#
# GEGEN STELLVERTRETER, KEIN ECHTER MODELLSTART: `wb-mlx-server` ist hier eine
# Attrappe, die nur die stdout-Zeile 'modell=<name>' liefert (der einzige
# Vertrag, auf den pi-worker sich verlaesst), `pi` selbst ist eine Attrappe, die
# nur ihr Bereitschaftszeichen zeigt und alles Eingegebene mitschreibt -- kein
# echtes Modell wird geladen, kein echter Port beruehrt. `wb-state`,
# `wb-kontext`, `wb-belegung`, `wb-worktree`, `wb-pane-write`, `wb-mensch`,
# `wb-rolle` sind ECHTE Kopien (isoliertes HOME statt Attrappe) -- das
# Zusammenspiel zwischen pi-worker und diesen Werkzeugen ist der eigentliche
# Pruefgegenstand.
#
# ISOLATION: eigener tmux-Socket, eigenes HOME (Registry, Buchungsbuch,
# kv-bedarf.json, Worktrees, Ergebnisse und Zustand liegen alle darunter),
# eigene Modell-Registry mit Phantom-Modellverzeichnissen. Am Ende wird
# geprueft, dass das ECHTE ~/.local/state/wb-belegung/buch.json und die
# echte kv-bedarf.json unberuehrt blieben -- der Lauf arbeitet auf den
# Stellvertretern, nicht auf der echten Maschine.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_REAL="$(command -v tmux 2>/dev/null)"
SOCKET="wbtest-kvschluessel-$$"
TESTHOME="$(mktemp -d)"
SHIM="$TESTHOME/.shim"
MARKE="k$(date +%s)$$$RANDOM"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local d=$((SECONDS + 5))
  while [ $SECONDS -lt $d ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null; sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

echo "== pi-worker: der KV-Schluessel fuer die eigene Sequenzbuchung (Socket $SOCKET, HOME $TESTHOME) =="

[ -n "$TMUX_REAL" ] || ueberspringen "tmux nicht im PATH"
[ -x "$REPO/pi-worker" ] || ueberspringen "shell/pi-worker fehlt"
[ -x "$REPO/wb-kontext" ] || ueberspringen "shell/wb-kontext fehlt"
[ -x "$REPO/wb-belegung" ] || ueberspringen "shell/wb-belegung fehlt"
command -v python3 >/dev/null 2>&1 || ueberspringen "python3 nicht im PATH"

# --- Die Testumgebung, vollstaendig selbst hergestellt ---------------------
mkdir -p "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/.claude/hooks/lib" \
         "$TESTHOME/.local/bin" "$TESTHOME/.local/state/wb-belegung" \
         "$TESTHOME/arbeit" \
         "$TESTHOME/models/koerper-basis" "$TESTHOME/models/Koerper-MTPLX-Gross"

# tmux des Prueflings auf den Testsocket nageln -- pi-worker ruft es ungeflaggt.
cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# Der falsche Agent -- zeigt nur sein Bereitschaftszeichen und schreibt alles
# Eingegebene fortlaufend mit, wie der 'claude'-Schirm in
# test-pi-worker-worktreehinweis.sh (derselbe Vertrag, anderer Binaername:
# ENGINE=pi execs 'pi', nicht 'claude').
cat > "$TESTHOME/.local/bin/pi" <<SHIMEOF
#!/bin/sh
stty -echo 2>/dev/null
printf '\342\235\257 \n'
exec tee -a "$TESTHOME/capture.log"
SHIMEOF
chmod +x "$TESTHOME/.local/bin/pi"

# Die Attrappe fuer wb-mlx-server: der einzige Vertrag, auf den pi-worker sich
# verlaesst, ist die stdout-Zeile 'modell=<bedienter-name>' nach 'ensure'. Kein
# echter Server startet, kein echter Port wird beruehrt.
BEDIENTER_NAME="test-bedient-als-mtplx"
cat > "$TESTHOME/.local/bin/wb-mlx-server" <<SHIMEOF
#!/bin/sh
if [ "\$1" = "ensure" ]; then
  echo "wb-mlx-server (Attrappe): ensure \$*" >&2
  printf 'modell=%s\n' "$BEDIENTER_NAME"
  exit 0
fi
exit 0
SHIMEOF
chmod +x "$TESTHOME/.local/bin/wb-mlx-server"

# Zwei Werkzeuge, die pi-worker im Vorbeigehen ruft und die hier nichts zu tun
# haben (derselbe Nullbefund wie in test-pi-worker-worktreehinweis.sh).
for leer in wb-grid context-guard; do
  printf '#!/bin/sh\nexit 0\n' > "$TESTHOME/.local/bin/$leer"
  chmod +x "$TESTHOME/.local/bin/$leer"
done

# check-resources: immer reichlich frei, wie in test-entwerfer.sh.
cat > "$TESTHOME/.local/bin/check-resources" <<'EOF'
#!/bin/sh
echo '{"ram":{"free_mib":40960,"total_mib":49152},"vram":{"free_mib":40960,"total_mib":49152},"ollama_loaded":[]}'
EOF
chmod +x "$TESTHOME/.local/bin/check-resources"

# Die ECHTEN Werkzeuge, kein Platzhalter -- das Zusammenspiel mit ihnen ist der
# Pruefgegenstand.
for w in wb-state wb-worktree wb-pane-write wb-mensch wb-rolle wb-kontext wb-belegung; do
  cp "$REPO/$w" "$TESTHOME/.local/bin/$w"
  chmod +x "$TESTHOME/.local/bin/$w"
done
cp "$REPO/../hooks/lib/rollen.py" "$TESTHOME/.claude/hooks/lib/rollen.py"

# --- Registry: EIN Modell mit bauart "eingebaut" -- derselbe Fall wie bei
# lmgamma-27b/MTPLX auf der echten Maschine, mit Phantom-Verzeichnissen statt
# echten Gewichten. ---
KOERPER_BASIS="$TESTHOME/models/koerper-basis"
KOERPER_ERSATZ="$TESTHOME/models/Koerper-MTPLX-Gross"
# wb-kontext loest den REGISTRY-PFAD auf (pi-worker gibt fuer harness=pi das
# aufgeloeste modelRef weiter, nicht die Registry-ID) -- ohne registrierten
# Eintrag unter diesem Pfad braucht 'natives Maximum' ein echtes config.json,
# genau wie bei einem echten MLX-Modellverzeichnis.
cat > "$KOERPER_BASIS/config.json" <<'CFGEOF'
{"max_position_embeddings": 65536}
CFGEOF
cat > "$TESTHOME/.claude/workbench/models.json" <<JSONEOF
{
  "models": [
    {
      "id": "test-mtplx", "label": "test-mtplx (Testfixture)", "alias": "test-mtplx",
      "harness": "pi", "provider": "mlx-local",
      "modelRef": "$KOERPER_BASIS",
      "roles": ["worker"], "maxEffort": "high", "defaultEffort": "medium",
      "contextWindow": 65536, "gewichteGb": 1.0,
      "vorhersage": {"bauart": "eingebaut", "modell": "$KOERPER_ERSATZ", "gewichteGb": 1.0}
    }
  ]
}
JSONEOF

# workerVorhersage MUSS an sein, sonst liest pi-worker das vorhersage-Feld gar
# nicht erst (siehe pi-worker, VORH_AN) -- exakt der Schalter, unter dem der
# gemessene Fall auf der echten Maschine lief.
cat > "$TESTHOME/.claude/workbench/settings.json" <<'JSONEOF'
{"workerVorhersage": true, "workerWorktrees": false}
JSONEOF

# Der KV-Wert des wirklich laufenden Koerpers, unter seinem Verzeichnisnamen
# (case wie auf der Platte -- wb-belegungs eigene kv_schluessel() faltet die
# Gross-/Kleinschreibung selbst). 0,033203 MiB/Token ist der ECHTE gemessene
# Wert von lmgamma-27b-mtplx-optimized-speed (kv-bedarf.json, 2026-08-21) --
# bei 32768 Token allein rund 1,06 GiB KV-Anteil (siehe Zusage 1 unten fuer
# die volle Spitze samt Sockel und Zuschlag), nicht die rund 39 GiB des
# Ersatzwerts.
env HOME="$TESTHOME" PATH="$TESTHOME/.local/bin:$PATH" \
    "$TESTHOME/.local/bin/wb-belegung" kv setzen "$(basename "$KOERPER_ERSATZ")" 0.033203 \
    --herkunft gemessen --kv-quant q8 --notiz "Testfixture" >/dev/null 2>&1

pi() {
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
      TMUX= TMUX_PANE= \
      bash "$REPO/pi-worker" "$@" 2>&1
}

# Eine Workbench-Session, in die pi-worker seine Panes haengen kann. MIT HOME/
# PATH auf die Testumgebung genagelt (anders als bei claude: die ENGINE=pi-
# Startzeile in pi-worker baut "exec pi ..." mit einem UNAUFGELOESTEN \$HOME
# (Laufzeit der Pane-Shell), nicht wie beim claude-Zweig mit einem beim
# CHAT-Zusammenbau schon aufgeloesten $HOME/.local/bin/claude -- ein neu
# gespawnter Pane erbt sein Environment vom tmux-SERVER (dessen globales
# Environment beim ERSTEN new-session-Aufruf entsteht), nicht vom Environment
# des SPAETEREN Aufrufers, der 'new-window' ruft. Ohne diesen Prefix haette der
# Pane das ECHTE HOME/PATH dieser Maschine geerbt und die ECHTE 'pi'-CLI
# gestartet -- gemessen beim Bau dieses Tests (node-Prozess, "New version ...
# is available", statt der Attrappe).
env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
  tmux -L "$SOCKET" -f /dev/null new-session -d -s "wb-$MARKE" -x 200 -y 40
tmux -L "$SOCKET" set-option -p -t "wb-$MARKE" @wb_role orchestrator

# --- Die ECHTEN Buecher -- der Lauf darf sie nicht anfassen. Geprueft wird
# das an den SPUREN dieses Laufs (Worker-Name mit MARKE, Fixture-Schluessel),
# nicht an einem Vorher/Nachher-Hash: das echte Buch ist eine lebende Datei
# der Maschine, jeder Worker-Spawn und jedes `wb-belegung wer` (Session-Start-
# Hook) schreibt sie neu. Ein Hash-Vergleich ueber 13 s Laufzeit fiel darum
# im run-all-Lauf vom 2026-09-05 16:00 rot (Lauf parallel zu echten Workern),
# obwohl kv-bedarf.json und ~/.pi-workers unberuehrt waren -- die Aenderung
# kam von aussen, nicht aus diesem Test. ---
ECHT_BUCH="$HOME/.local/state/wb-belegung/buch.json"
ECHT_KV="$HOME/.local/state/wb-belegung/kv-bedarf.json"

echo
echo "-- Worker mit bauart 'eingebaut', 32768 Token --"
WORKER_A="a$MARKE"
: > "$TESTHOME/capture.log"
AUS_A="$(pi --kontext 32768 "$WORKER_A" test-mtplx "$TESTHOME/arbeit" "Testauftrag $MARKE")"
RC_A=$?

if [ ! -s "$TESTHOME/capture.log" ]; then
  bad "nichts im Pane angekommen (rc=$RC_A)"
  printf '%s\n' "$AUS_A" | sed 's/^/      | /' | tail -30
else
  # Zusage 2/3: der bediente Name landet als das, was pi als --model bekommt.
  grep -qF "der Server bedient '$BEDIENTER_NAME'" <<<"$AUS_A" \
    && ok "pi-worker meldet den bedienten Namen aus 'wb-mlx-server ensure' laut" \
    || bad "keine Meldung ueber den bedienten Namen: $AUS_A"

  BUCH_JSON="$(env HOME="$TESTHOME" PATH="$TESTHOME/.local/bin:$PATH" \
                 "$TESTHOME/.local/bin/wb-belegung" wer --json 2>&1)"
  GEBUCHTES_MODELL="$(printf '%s' "$BUCH_JSON" | python3 -c '
import json, sys
txt = sys.stdin.read()
start = txt.find("{")
d = json.loads(txt[start:])
b = [e for e in d.get("belegungen", []) if str(e.get("zweck","")).startswith("pi-worker:")]
print(b[0].get("modell","") if b else "")
' 2>/dev/null)"
  GEBUCHTE_GB="$(printf '%s' "$BUCH_JSON" | python3 -c '
import json, sys
txt = sys.stdin.read()
start = txt.find("{")
d = json.loads(txt[start:])
b = [e for e in d.get("belegungen", []) if str(e.get("zweck","")).startswith("pi-worker:")]
print(b[0].get("gb", -1) if b else -1)
' 2>/dev/null)"

  if [ "$GEBUCHTES_MODELL" = "$(basename "$KOERPER_ERSATZ")" ]; then
    ok "Zusage 1: der KV-Schluessel der Buchung ist der Verzeichnisname des KOERPERS ('$GEBUCHTES_MODELL'), nicht der bediente Name"
  else
    bad "falscher KV-Schluessel gebucht: '$GEBUCHTES_MODELL' (erwartet '$(basename "$KOERPER_ERSATZ")', bedienter Name waere '$BEDIENTER_NAME')"
  fi

  if [ "$GEBUCHTES_MODELL" != "$BEDIENTER_NAME" ]; then
    ok "Zusage 3: der bediente Name und der KV-Schluessel sind nicht dasselbe"
  else
    bad "der bediente Name wurde faelschlich als KV-Schluessel gebucht"
  fi

  # Zusage 1, die eigentliche Zahl: 0,001 Sockel + 32768 x 0,033203 MiB / 1024
  # KV = rund 1,06 GiB.
  #
  # BIS ZUM 2026-08-27 standen hier 3,36 GiB, weil `wb-belegung` je Sequenz
  # 2,3 GiB aufschlug. Dieser Zuschlag ist an diesem Tag auf 0 gefallen
  # (Vorgabe: "alle Reserven weg, nur den Notfall-Kill behalten"), zusammen mit
  # der 6-GiB-Reserve und dem 20-GiB-Boden in wb-mlx-server. Die Zahl hier
  # wurde deshalb nachgezogen -- NICHT die Sache, die dieser Test prueft: dass
  # der KV-Schluessel ueber den KOERPER aufgeloest wird und nicht ueber den
  # bedienten Namen. Genau das steht und faellt weiter mit dem Unterschied
  # zwischen rund 1 GiB (richtiger Wert) und rund 39 GiB (Ersatzwert bei
  # fehlendem Treffer: hungrigstes gemessenes Modell x Sicherheitsfaktor,
  # exakt der auf der echten Maschine gemessene Fehlbetrag, Ergebnis
  # 20260821-050834.md).
  if python3 -c "import sys; g=float('$GEBUCHTE_GB'); sys.exit(0 if 0.9 <= g <= 1.3 else 1)" 2>/dev/null; then
    ok "Zusage 1: gebucht wurden $GEBUCHTE_GB GiB -- rund 1,06 (der richtige KV-Wert), nicht rund 39 (der Ersatzwert)"
  else
    bad "falsche Buchungsgroesse: $GEBUCHTE_GB GiB (erwartet rund 3,2-3,5)"
  fi

  # Die Kennung wirklich uebernehmen, damit die Belegung beim Aufraeumen nicht
  # als 'verfallen' im echten Buch dieser Testsitzung haengen bleibt -- wird
  # ohnehin nur im isolierten TESTHOME gefuehrt, rein zur Ordnung.
fi

echo
echo "-- die echte Maschine blieb unberuehrt --"
if ! grep -qF "$MARKE" "$ECHT_BUCH" 2>/dev/null; then
  ok "das ECHTE Buchungsbuch (~/.local/state/wb-belegung/buch.json) traegt keine Buchung dieses Laufs ($MARKE)"
else
  bad "die Buchung dieses Laufs ($MARKE) steht im ECHTEN Buchungsbuch -- Testisolation gebrochen"
fi
if ! grep -qF "$(basename "$KOERPER_ERSATZ")" "$ECHT_KV" 2>/dev/null; then
  ok "die ECHTE kv-bedarf.json traegt den Fixture-Schluessel '$(basename "$KOERPER_ERSATZ")' nicht"
else
  bad "der Fixture-Schluessel '$(basename "$KOERPER_ERSATZ")' steht in der ECHTEN kv-bedarf.json -- Testisolation gebrochen"
fi
if [ ! -e "$HOME/.pi-workers/results/$WORKER_A" ]; then
  ok "kein Ergebnisordner fuer den Testworker unter dem echten HOME"
else
  bad "es wurde ins ECHTE ~/.pi-workers geschrieben -- Testisolation gebrochen"
fi

echo
echo "Ergebnis: $pass ok, $fail FAIL"
[ "$fail" -eq 0 ]
