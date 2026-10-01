#!/usr/bin/env bash
# test-worktree-node-modules.sh — link_app_node_modules() in shell/wb-worktree.
#
# Anlass (2026-08-11): macOS zeigte "Agent Workbench.app kann bis zum Beenden
# keine Apps aktualisieren oder loeschen". Ursache: ein `npm install` in einem
# Worker-Worktree packte Electrons eigenes App-Buendel unter
# node_modules/electron/dist/Electron.app aus, und macOS schreibt eine solche
# Meldung der verantwortlichen App zu — jeder Pane laeuft unter demselben
# Programmbuendel wie die Werkbank selbst. Dieselbe Wurzel (fehlendes
# app/node_modules in frischen Worktrees) liess App-Testsuiten sich still
# ueberspringen; zwei Worker legten sich deshalb von Hand einen Symlink.
#
# ZWEITER Anlass (2026-08-12): der ERSTE Umbau (Symlink) hatte selbst ein
# Datenverlust-Risiko, ganz ohne rm-Falle. Ein Worker lief `npm ci` IN einem
# Worktree, dessen app/node_modules noch der Symlink war — npm raeumt vor der
# Installation den Zielordner leer, und weil ein Symlink fuer Dateioperationen
# transparent ist, traf das den Ordner im HAUPTBAUM: leerer Ordner mit mtime =
# Startzeitpunkt des Workers, der Hauptbaum brauchte danach selbst wieder
# `npm ci`. wb-worktree klont app/node_modules jetzt per `cp -c -R` (APFS
# clonefile, copy-on-write) statt zu verlinken — Schreibzugriffe im Worktree
# treffen dann nur noch dessen eigene Kopie. Nur wenn Klonen nicht verfuegbar
# ist (kein APFS o. ae.), faellt die Funktion auf den alten Symlink zurueck,
# MIT Warnung nach stderr, dass darin kein npm ci/install laufen darf.
#
# Diese Suite deckt ab: frischer Baum bekommt einen echten Klon (kein
# Symlink, (a)), Schreiben/Leeren im geklonten Worktree-node_modules laesst
# den Hauptbaum unberuehrt (der eigentliche Vorfall von 2026-08-12 als
# Assertion, (b)), ein Baum mit bereits echtem Verzeichnis behaelt es, git
# status im Arbeitsbaum bleibt sauber, der Rueckfall auf den Symlink greift,
# wenn `cp -c` scheitert ((c), per Stub erzwungen), und `wb-worktree remove`
# raeumt trotz echtem node_modules im Worktree anstandslos ab ((d)).
#
# ISOLATION (siehe regeln/tests-und-eingriffe.md): kein tmux noetig — `ensure`
# und `remove` brauchen kein Pane, nur git. Eigenes HOME (mktemp -d), eigene
# Wegwerf-Fixture-Repos (git init), die echten Repos dieser Maschine werden
# nie angefasst. `wb-worktree` wird als KOPIE in ein Test-$BIN gelegt (wie
# test-worktrees.sh es begruendet: eine Bearbeitung waehrend des Laufs soll
# den Code unter dem laufenden Test nicht aendern).
unset TMUX TMUX_PANE
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOL_SRC="$REPO_ROOT/wb-worktree"
[ -x "$TOOL_SRC" ] || { echo "FAIL  $TOOL_SRC fehlt oder ist nicht ausfuehrbar" >&2; exit 1; }

# `cd … && pwd -P` normalisiert den Pfad (wie test-worktrees.sh begruendet):
# /var ist auf macOS ein Symlink auf /private/var, und git meldet Worktree-
# Pfade in `worktree list --porcelain` immer AUFGELOEST -- ohne diese
# Normalisierung verglichen wir "/var/…" (aus $TESTHOME) gegen
# "/private/var/…" (aus git) und saehen einen Unterschied, der keiner ist.
# Scratch-Basis bewusst NICHT der Vorgabe-TMPDIR: unter Linux ist `/tmp`
# ueblicherweise tmpfs (RAM, kein Copy-on-Write-Dateisystem), waehrend der
# echte Bestand auf btrfs/APFS liegt -- die Klon-Faelle dieser Suite (2, 2b,
# 6) wuerden auf tmpfs IMMER auf den Symlink-Rueckfall treffen, egal wie gut
# wb-worktree Klonen sonst beherrscht (Befund 2026-08-21, `df -T /tmp` zeigt
# tmpfs auf host2). `$REAL_HOME/.cache` liegt auf demselben Volume wie der
# eigentliche Checkout und traegt dieselbe CoW-Faehigkeit.
REAL_HOME="$HOME"
mkdir -p "$REAL_HOME/.cache" 2>/dev/null
TESTBASIS="$REAL_HOME/.cache"
[ -d "$TESTBASIS" ] && [ -w "$TESTBASIS" ] || TESTBASIS="${TMPDIR:-/tmp}"
TESTHOME="$(cd "$(mktemp -d "$TESTBASIS/wb-worktree-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$TESTHOME"' EXIT
export HOME="$TESTHOME"
BIN="$TESTHOME/.local/bin"; mkdir -p "$BIN"
cp "$TOOL_SRC" "$BIN/wb-worktree"; chmod +x "$BIN/wb-worktree"
W="$BIN/wb-worktree"
WTROOT="$TESTHOME/.pi-workers/worktrees"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "'$2' != '$3'"; fi; }
have(){ case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "erwartet '$3' in: $(printf '%s' "$2" | tr '\n' ' ' | cut -c1-200)" ;; esac; }

echo "Geprueft: $TOOL_SRC"
echo "  HOME: $TESTHOME"

# --- Fixture: Hauptbaum mit app/-Unterprojekt, wie im echten Repo ----------
mkrepo() { # mkrepo <pfad>
  mkdir -p "$1"
  git -c init.defaultBranch=main init -q "$1"
  git -C "$1" config user.email "test@example.invalid"
  git -C "$1" config user.name  "Worktree Node-Modules Test"
  git -C "$1" config commit.gpgsign false
  mkdir -p "$1/app"
  printf '{"name":"app"}\n' > "$1/app/package.json"
  # Dieselben beiden Zeilen wie das echte .gitignore dieses Repos: die
  # bestehende trailing-slash-Zeile UNVERAENDERT, dazu die Zeile fuer den
  # Symlink-/Klon-Fall (beide gitignored, egal ob echtes Verzeichnis oder
  # Verweis). Damit prueft dieser Test die tatsaechliche .gitignore-Logik,
  # nicht nur eine angenommene.
  printf 'node_modules/\n/app/node_modules\n' > "$1/.gitignore"
  git -C "$1" add -A
  git -C "$1" commit -q -m init
}

REPO="$TESTHOME/hauptbaum"; mkrepo "$REPO"

echo
echo "== 1. ohne node_modules im Hauptbaum: nichts passiert =="
out="$("$W" ensure kein1 "$REPO" 2>"$TESTHOME/err-kein1")"
WT1="$out"
[ -e "$WT1/app/node_modules" ] \
  && bad "app/node_modules entsteht ohne Vorbild im Hauptbaum" "$WT1/app/node_modules existiert" \
  || ok  "app/node_modules bleibt weg, wenn der Hauptbaum selbst keins hat"
case "$(cat "$TESTHOME/err-kein1")" in
  *geklont*|*verlinkt*) bad "faelschlich ein Klon-/Verlinkungs-Hinweis, obwohl nichts geschah" ;;
  *) ok "kein Klon-/Verlinkungs-Hinweis in der Ausgabe, da nichts geschah" ;;
esac
"$W" remove kein1 --force >/dev/null 2>&1

echo
echo "== 2. frischer Baum bekommt einen echten Klon, kein Symlink (a) =="
mkdir -p "$REPO/app/node_modules/irgendein-paket"
printf 'echte-abhaengigkeit\n' > "$REPO/app/node_modules/irgendein-paket/index.js"
MARKER_VORHER="$(cat "$REPO/app/node_modules/irgendein-paket/index.js")"

out="$("$W" ensure frisch "$REPO" 2>"$TESTHOME/err-frisch")"
WTF="$out"
if [ -L "$WTF/app/node_modules" ]; then
  bad "app/node_modules im Worktree ist ein Symlink — soll ein Klon sein" "$(ls -la "$WTF/app" 2>&1)"
elif [ -d "$WTF/app/node_modules" ]; then
  ok "app/node_modules im Worktree ist ein echtes Verzeichnis (Klon)"
else
  bad "app/node_modules im Worktree fehlt ganz" "$(ls -la "$WTF/app" 2>&1)"
fi
[ -f "$WTF/app/node_modules/irgendein-paket/index.js" ] \
  && ok "der geklonte Inhalt ist vorhanden" \
  || bad "der geklonte Inhalt fehlt"
INODE_SRC="$(stat -f %i "$REPO/app/node_modules/irgendein-paket/index.js" 2>/dev/null)"
INODE_DST="$(stat -f %i "$WTF/app/node_modules/irgendein-paket/index.js" 2>/dev/null)"
[ -n "$INODE_SRC" ] && [ "$INODE_SRC" != "$INODE_DST" ] \
  && ok "Klon hat eine eigene Inode, ist keine Hardlink-Identitaet mit dem Original" \
  || bad "Inode-Vergleich unerwartet" "src=$INODE_SRC dst=$INODE_DST"
have "die Ausgabe sagt, dass geklont wurde" "$(cat "$TESTHOME/err-frisch")" "geklont"

echo
echo "== 2b. Leeren im Worktree-node_modules laesst den Hauptbaum unberuehrt (b, der Vorfall vom 2026-08-12) =="
# Reproduziert den eigentlichen Vorfall: etwas (wie `npm ci`) leert
# app/node_modules IM WORKTREE. Bei einem Symlink traf das den Hauptbaum;
# beim Klon darf davon im Hauptbaum nichts ankommen.
rm -rf "$WTF/app/node_modules"/*
[ -z "$(ls -A "$WTF/app/node_modules" 2>/dev/null)" ] \
  && ok "Vorbereitung: Worktree-node_modules ist jetzt leer" \
  || bad "Vorbereitung fehlgeschlagen: Worktree-node_modules ist nicht leer"
[ -f "$REPO/app/node_modules/irgendein-paket/index.js" ] \
  && ok "der Hauptbaum behaelt seinen Inhalt, obwohl der Worktree-Klon geleert wurde" \
  || bad "DER VORFALL VOM 2026-08-12 IST ZURUECK — der Hauptbaum wurde mit-geleert"
NACHHER_2B="$(cat "$REPO/app/node_modules/irgendein-paket/index.js" 2>/dev/null)"
eq "und sein Inhalt ist unveraendert" "$NACHHER_2B" "$MARKER_VORHER"
# Fixture fuer den Rest des Tests reparieren (nur der Worktree wurde geleert).
"$W" remove frisch --force >/dev/null 2>&1

echo
echo "== 3. git status im Arbeitsbaum bleibt sauber =="
WT3A="$("$W" ensure sauber "$REPO" 2>/dev/null)"
STATUS="$(git -C "$WT3A" status --porcelain 2>/dev/null)"
eq "git status zeigt den Klon nicht als unversioniert" "$STATUS" ""
"$W" remove sauber --force >/dev/null 2>&1

echo
echo "== 4. Baum mit echtem Verzeichnis behaelt es =="
# Zweiter ensure-Aufruf auf denselben (bereits bestehenden) Worktree, diesmal
# mit einer EIGENEN Installation an der Stelle -- simuliert einen Worker, der
# selbst schon 'npm install' laufen liess, bevor die Verlinkung existierte.
WT2="$("$W" ensure wiederda "$REPO" 2>/dev/null)"
rm -rf "$WT2/app/node_modules"   # der frische Klon aus dem ersten ensure-Aufruf
mkdir -p "$WT2/app/node_modules"
printf 'eigene-installation\n' > "$WT2/app/node_modules/eigene-datei.txt"

out="$("$W" ensure wiederda "$REPO" 2>"$TESTHOME/err-wiederda")"
eq "zweiter ensure-Aufruf liefert denselben Pfad" "$out" "$WT2"
[ -f "$WT2/app/node_modules/eigene-datei.txt" ] \
  && ok "sein Inhalt ist unangetastet" \
  || bad "sein Inhalt ist WEG"
case "$(cat "$TESTHOME/err-wiederda")" in
  *geklont*|*verlinkt*) bad "faelschlich ein Klon-/Verlinkungs-Hinweis, obwohl nichts geschah" ;;
  *) ok "kein Klon-/Verlinkungs-Hinweis, weil nichts geschah" ;;
esac

echo
echo "== 5. wb-worktree remove raeumt trotz echtem node_modules ab (d) =="
out="$("$W" remove wiederda 2>&1)"; rc=$?
eq "remove (ohne --force) raeumt den Baum trotz echtem Verzeichnis ohne Widerstand weg" "$rc" "0"
have "und meldet 'entfernt'" "$out" "entfernt: $WT2"
[ -e "$WT2" ] && bad "der Worktree steht noch" "$WT2 existiert" || ok "der Worktree ist weg"

echo
echo "== 6. nach dem Klonen+Entfernen bleibt das Ziel im Hauptbaum unveraendert =="
WT5="$("$W" ensure weg "$REPO" 2>/dev/null)"
[ -d "$WT5/app/node_modules" ] && [ ! -L "$WT5/app/node_modules" ] \
  && ok "Vorbereitung: Klon steht wie erwartet" \
  || bad "Vorbereitung fehlgeschlagen: kein Klon in $WT5/app"
out="$("$W" remove weg 2>&1)"; rc=$?
eq "remove (ohne --force) laeuft durch" "$rc" "0"
have "und meldet 'entfernt'" "$out" "entfernt: $WT5"
[ -e "$WT5" ] && bad "der Worktree steht noch" "$WT5 existiert" || ok "der Worktree ist weg"
[ -d "$REPO/app/node_modules/irgendein-paket" ] \
  && ok "app/node_modules im Hauptbaum existiert nach dem Entfernen weiterhin" \
  || bad "app/node_modules im Hauptbaum ist WEG"
NACHHER="$(cat "$REPO/app/node_modules/irgendein-paket/index.js" 2>/dev/null)"
eq "und sein Inhalt ist unveraendert" "$NACHHER" "$MARKER_VORHER"

echo
echo "== 7. Rueckfall auf den Symlink, wenn Klonen scheitert (c, per Stub erzwungen) =="
# Ein Stub-'cp', VOR dem echten in PATH, das jeden Aufruf mit '-c' ODER
# '--reflink=always' scheitern laesst -- simuliert ein Zielvolume ganz ohne
# Copy-on-Write-Unterstuetzung (weder APFS clonefile noch btrfs/xfs-Reflink),
# ohne dafuer wirklich ein anderes Dateisystem einhaengen zu muessen. Beide
# Flags absichtlich, seit clone_flag_available() beide der Reihe nach
# ausprobiert (2026-08-21) -- sonst wuerde dieser Fall auf einem echten
# CoW-Dateisystem (host2: btrfs) durch den zweiten Versuch trotzdem einen
# Klon bekommen und den Rueckfall gar nicht mehr pruefen. Alle anderen
# cp-Aufrufe (z. B. das Skript kopiert sich selbst weiter oben) laufen
# unveraendert an den echten cp durch.
STUBDIR="$TESTHOME/stubbin"; mkdir -p "$STUBDIR"
cat > "$STUBDIR/cp" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    -c|--reflink=always) echo "cp-stub: $a erzwungen zu scheitern" >&2; exit 1 ;;
  esac
done
exec /bin/cp "$@"
EOF
chmod +x "$STUBDIR/cp"

out="$(PATH="$STUBDIR:$PATH" "$W" ensure fallback "$REPO" 2>"$TESTHOME/err-fallback")"
WTFB="$out"
if [ -L "$WTFB/app/node_modules" ]; then
  ok "ohne Klon-Faehigkeit faellt die Funktion auf einen Symlink zurueck"
else
  bad "kein Rueckfall auf Symlink, obwohl 'cp -c' erzwungen scheiterte" "$(ls -la "$WTFB/app" 2>&1)"
fi
ZIEL_FB="$(readlink "$WTFB/app/node_modules" 2>/dev/null)"
eq "der Rueckfall-Symlink zeigt auf den Hauptbaum" "$ZIEL_FB" "$REPO/app/node_modules"
have "die Ausgabe warnt ausdruecklich vor npm ci/install im Rueckfall-Symlink" \
  "$(cat "$TESTHOME/err-fallback")" "npm ci/install"
"$W" remove fallback --force >/dev/null 2>&1

echo
echo "wb-worktree (app/node_modules): $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
