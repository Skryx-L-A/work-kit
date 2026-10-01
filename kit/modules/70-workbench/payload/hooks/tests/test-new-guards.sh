#!/bin/bash
# Tests fuer bash-guard-screencapture.sh und bash-guard-snapshot.sh.
#
# Alles laeuft gegen eine eigene Wegwerf-Fixture unter mktemp -- kein Testfall
# haengt daran, was auf dieser Maschine installiert oder konfiguriert ist, und
# keiner fasst die echte Umgebung an. Der Snapshot-Guard bekommt ueber
# SNAPSHOT_GUARD_CONF eine fixture-eigene Konfiguration; die ausgelieferte
# snapshot-guard-exempt.conf wird nur in zwei ausdruecklich markierten Faellen
# benutzt, um zu pruefen, dass sie ueberhaupt geparst wird.
set -uo pipefail
unset TMUX TMUX_PANE

# Prueflinge sind die Hooks neben dieser Testdatei; HOOKS_DIR aus der Umgebung
# schlaegt das, damit sich dieselbe Suite gegen eine andere Fassung fahren
# laesst (z.B. Arbeitsstand gegen installierte Fassung).
HOOKS="${HOOKS_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
SC="$HOOKS/bash-guard-screencapture.sh"
SN="$HOOKS/bash-guard-snapshot.sh"

FIX=$(mktemp -d)
trap 'rm -rf "$FIX"' EXIT

pass=0
fail=0

# --- Fixture ---------------------------------------------------------------
mkdir -p "$FIX/data/sub" "$FIX/emptydir" "$FIX/throwaway/junk" "$FIX/somedir" \
         "$FIX/snapshots" "$FIX/node_modules/pkg"
printf 'wichtige nutzdaten\n' > "$FIX/important.txt"
printf 'inhalt a\n' > "$FIX/data/a.txt"
printf 'inhalt b\n' > "$FIX/data/sub/b.txt"
printf 'wegwerf\n' > "$FIX/throwaway/junk/x.txt"
printf 'dep\n' > "$FIX/node_modules/pkg/index.js"
printf 'neu\n' > "$FIX/new.txt"
printf 'a\n' > "$FIX/a.txt"
: > "$FIX/leer.txt"

REPO="$FIX/repo"
mkdir -p "$REPO/clean_tracked_dir"
git init -q "$REPO"
printf 'tracked\n' > "$REPO/tracked.txt"
printf 'sauber\n' > "$REPO/clean.txt"
printf 'im ordner\n' > "$REPO/clean_tracked_dir/f.txt"
git -C "$REPO" add -A >/dev/null 2>&1
git -C "$REPO" -c user.name=t -c user.email=t@example.invalid \
    commit -qm init >/dev/null 2>&1
printf 'lokal geaendert\n' >> "$REPO/tracked.txt"
printf 'ungetrackt\n' > "$REPO/untracked.txt"

CONF="$FIX/test.conf"
cat > "$CONF" <<CONFEOF
exempt_glob=$FIX/throwaway
exempt_glob=$FIX/throwaway/*
exempt_glob=*/node_modules
exempt_glob=*/node_modules/*
exempt_glob=/dev/null
snapshot_dir=$FIX/snapshots
snapshot_max_age_minutes=120
min_bytes=1
git_committed_is_exempt=true
CONFEOF

# --- Hilfen ----------------------------------------------------------------
run_hook() {  # run_hook <script> <command> <cwd> [conf]
  local script="$1" cmd="$2" cwd="$3" conf="${4:-$CONF}"
  SNAPSHOT_GUARD_CONF="$conf" python3 -c '
import json,sys
print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],
                  "tool_input":{"command":sys.argv[1]}}))
' "$cmd" "$cwd" | SNAPSHOT_GUARD_CONF="$conf" bash "$script" 2>/dev/null
}

expect() {  # expect <deny|allow> <script> <label> <command> [cwd] [conf]
  local want="$1" script="$2" label="$3" cmd="$4" cwd="${5:-$FIX}" conf="${6:-$CONF}"
  local out got
  out=$(run_hook "$script" "$cmd" "$cwd" "$conf")
  if printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf 'OK    [%s] %s\n' "$want" "$label"
  else
    fail=$((fail+1)); printf 'FEHL  erwartet=%s bekommen=%s  %s\n      cmd: %s\n' \
      "$want" "$got" "$label" "$cmd"
    [ -n "$out" ] && printf '      hook: %s\n' "$(printf '%s' "$out" | head -c 300)"
  fi
}

# Bis 2026-08-22 war jede Aufnahme ohne Fensterbegrenzung ein Deny (Regel
# 2026-07-25, "NIEMALS den gesamten Bildschirm"). Die Freigabe vom
# 2026-08-22 ("Die Maschine gehoert Dir, ... auch vom ganzen Bildschirm,
# vollkommen egal") hat das Vollbild-Verbot aufgehoben -- der Wächter
# (hooks/lib/screencapture_classify.py) wurde entsprechend geoeffnet. Die neun
# Faelle unten, die frueher hier unter MUSS BLOCKIEREN standen, stehen jetzt
# im MUSS-DURCHGEHEN-Block, mit einem Vermerk, dass sie das mal waren --
# das haelt fest, dass diese Form einmal verboten war, nicht nur, dass sie
# jetzt erlaubt ist. Weiterhin blockiert bleibt einzig der interaktive
# Auswahlmodus (-i/-w/-W), aber aus einem technischen statt dem alten
# Regelgrund -- siehe die beiden Faelle unten.
echo "=============================================================="
echo "HOOK 1  bash-guard-screencapture  --  MUSS BLOCKIEREN"
echo "=============================================================="
expect deny "$SC" "interaktive Auswahl -i (bleibt gesperrt: Fadenkreuz wartet auf Eingabe, kein altes Regelthema mehr)" \
        'screencapture -i sel.png'
expect deny "$SC" "interaktiv im Fenstermodus -W (bleibt gesperrt, gleicher technischer Grund)" \
        'screencapture -W sel.png'

echo
echo "=============================================================="
echo "HOOK 1  bash-guard-screencapture  --  MUSS DURCHGEHEN"
echo "=============================================================="
expect allow "$SC" "Fenster-ID -l"              'screencapture -l 42 win.png'
expect allow "$SC" "Rechteck -R"                'screencapture -R 0,0,800,600 rect.png'
expect allow "$SC" "-l mit ID aus Variable (Form von wb-shot)" \
        'screencapture -x -o -l "$id" "$OUT"'
expect allow "$SC" "Flag-Cluster mit l"         'screencapture -xol 42 win.png'
expect allow "$SC" "der vorgesehene Weg"        'wb-shot Terminal /tmp/x.png'
expect allow "$SC" "Wort nur als Suchbegriff"   'grep -rn screencapture ~/.claude/hooks'
expect allow "$SC" "Wort nur als Text"          'echo "nie screencapture ohne -l"'
expect allow "$SC" "ueber ssh, aber fenstergenau" \
        "ssh remotehost 'screencapture -l 7 /tmp/w.png'"
expect allow "$SC" "Alltag: ls"                 'ls -la'
expect allow "$SC" "Alltag: git status"         'git status'

# Ab hier die neun, die bis 2026-08-22 MUSS BLOCKIEREN waren (siehe Vermerk
# oben) und seit der Freigabe MUSS DURCHGEHEN sind.
expect allow "$SC" "vormals MUSS BLOCKIEREN (bis 2026-08-22): blanker Aufruf" \
        'screencapture out.png'
expect allow "$SC" "vormals MUSS BLOCKIEREN (bis 2026-08-22): nur Flags ohne Begrenzung" \
        'screencapture -x -t png /tmp/full.png'
expect allow "$SC" "vormals MUSS BLOCKIEREN (bis 2026-08-22): in Pipeline hinter && mit absolutem Pfad" \
        'ls | head -1 && /usr/sbin/screencapture -m shot.png'
expect allow "$SC" "vormals MUSS BLOCKIEREN (bis 2026-08-22): ganzer Display via -D" \
        'screencapture -D 1 /tmp/x.png'
expect allow "$SC" "vormals MUSS BLOCKIEREN (bis 2026-08-22): ueber ssh auf der anderen Maschine" \
        "ssh remotehost 'screencapture -x /tmp/x.png'"
expect allow "$SC" "vormals MUSS BLOCKIEREN (bis 2026-08-22): verschachtelt in bash -c" \
        'bash -c "screencapture -T 3 a.png"'
expect allow "$SC" "vormals MUSS BLOCKIEREN (bis 2026-08-22): hinter sudo" \
        'sudo screencapture /tmp/a.png'
expect allow "$SC" "vormals MUSS BLOCKIEREN als UNENTSCHEIDBAR (bis 2026-08-22): Flags aus Kommandosubstitution -- jetzt gleichgueltig, da auch das Vollbild-Ergebnis erlaubt ist" \
        'screencapture $(cat /tmp/flags) a.png'
expect allow "$SC" "vormals MUSS BLOCKIEREN als UNENTSCHEIDBAR (bis 2026-08-22): Flags aus freier Variable -- jetzt gleichgueltig, da auch das Vollbild-Ergebnis erlaubt ist" \
        'screencapture $FLAGS a.png'

echo
echo "=============================================================="
echo "HOOK 2  bash-guard-snapshot  --  MUSS BLOCKIEREN"
echo "=============================================================="
expect deny "$SN" "rm -rf auf Verzeichnis mit Inhalt" "rm -rf $FIX/data"
expect deny "$SN" "rm -r ohne -f"                     "rm -r $FIX/data"
expect deny "$SN" "mv auf existierende Datei"         "mv $FIX/new.txt $FIX/important.txt"
expect deny "$SN" "> auf existierende Datei"          "echo neu > $FIX/important.txt"
expect deny "$SN" "truncate"                          "truncate -s 0 $FIX/important.txt"
expect deny "$SN" "shred"                             "shred -u $FIX/important.txt"
expect deny "$SN" "dd of="                            "dd if=/dev/zero of=$FIX/important.txt bs=1"
expect deny "$SN" "git reset --hard bei schmutzigem Tree" 'git reset --hard' "$REPO"
expect deny "$SN" "git clean -fd mit ungetrackter Datei"  'git clean -fd' "$REPO"
expect deny "$SN" "git checkout -- geaenderte Datei"      'git checkout -- tracked.txt' "$REPO"
expect deny "$SN" "git restore geaenderte Datei"          'git restore tracked.txt' "$REPO"
expect deny "$SN" "versteckt hinter ; in einer Kette"     "cd $FIX && ls ; rm -rf $FIX/data"
expect deny "$SN" "UNENTSCHEIDBAR: Ziel aus freier Variable" 'rm -rf "$TARGET"'
expect deny "$SN" "UNENTSCHEIDBAR: Ziel aus Kommandosubstitution" 'rm -rf $(cat liste.txt)'

echo
echo "=============================================================="
echo "HOOK 2  bash-guard-snapshot  --  MUSS DURCHGEHEN"
echo "=============================================================="
expect allow "$SN" "Alltag: ls"                    'ls -la'
expect allow "$SN" "Alltag: git status"            'git status' "$REPO"
expect allow "$SN" "Alltag: grep mit Umleitung nach /dev/null" 'grep -r x . 2>/dev/null'
expect allow "$SN" "Wegwerf-Ort aus der Konfiguration" "rm -rf $FIX/throwaway/junk"
expect allow "$SN" "node_modules"                  "rm -rf $FIX/node_modules"
expect allow "$SN" "Pfad existiert gar nicht"      "rm -rf $FIX/gibtsnicht"
expect allow "$SN" "leeres Verzeichnis"            "rm -rf $FIX/emptydir"
expect allow "$SN" "0-Byte-Datei ueberschreiben"   "echo x > $FIX/leer.txt"
expect allow "$SN" "Anhaengen statt ueberschreiben" "echo x >> $FIX/important.txt"
expect allow "$SN" "Ziel existiert noch nicht"     "echo x > $FIX/ganzneu.txt"
expect allow "$SN" "mv in ein Verzeichnis"         "mv $FIX/a.txt $FIX/somedir/"
expect allow "$SN" "mv -n (ueberschreibt nie)"     "mv -n $FIX/new.txt $FIX/important.txt"
expect allow "$SN" "Glob ohne Treffer"             "rm -rf $FIX/nichts-*"
expect allow "$SN" "vollstaendig committet in git" "rm -rf $REPO/clean_tracked_dir" "$REPO"
expect allow "$SN" "git checkout -- unveraenderte Datei" 'git checkout -- clean.txt' "$REPO"
expect allow "$SN" "git checkout <branch> (kein Pfad)"   'git checkout -b feature' "$REPO"
expect allow "$SN" "git restore --staged (Inhalt bleibt)" 'git restore --staged tracked.txt' "$REPO"
expect allow "$SN" "Snapshot im selben Befehl" \
        "cp -a $FIX/data $FIX/snapshots/2026-08-03-data && rm -rf $FIX/data"
expect allow "$SN" "rm ohne -r (bewusst nicht erfasst)" "rm $FIX/important.txt"

# Frischer Snapshot muss auch dann gefunden werden, wenn im Snapshot-Verzeichnis
# tausend aeltere Eintraege liegen und der passende alphabetisch spaet steht.
mkdir -p "$FIX/data2/sub" && printf 'x\n' > "$FIX/data2/sub/f.txt"
for i in $(seq 1 900); do mkdir -p "$FIX/snapshots/0000-alt-$i"; done
mkdir -p "$FIX/snapshots/zzzz-2026-08-03-data2/data2"
printf 'x\n' > "$FIX/snapshots/zzzz-2026-08-03-data2/data2/f.txt"
expect allow "$SN" "frischer Snapshot in grossem Verzeichnis wird gefunden" \
        "rm -rf $FIX/data2"
expect allow "$SN" "Heredoc-Inhalt ist Text, kein Befehl" \
        "cat > $FIX/doku.md <<EOF
rm -rf $FIX/data
EOF"

echo
echo "--- Falsch-Positive-Runde 2026-08-05: aufloesbar statt unentscheidbar ---"
# Ein Ziel unter `$(mktemp)`/`$(mktemp -d)` ist per Definition frisch angelegt:
# dort kann nichts Vorhandenes ueberschrieben oder geloescht werden. Vorher
# galt jede solche Zeile als unentscheidbar und wurde abgelehnt -- darunter
# `echo TESTINHALT > "$P/schmutz.txt"` mit `P=$(mktemp -d)`.
expect allow "$SN" "F4: > \"\$P/datei\" mit P=\$(mktemp -d)" \
        'P=$(mktemp -d)
echo TESTINHALT > "$P/schmutz.txt"'
expect allow "$SN" "rm -rf \"\$(mktemp -d)\" (frisch, nichts darin)" \
        'rm -rf "$(mktemp -d)"'
expect allow "$SN" "dd of=\$(mktemp) (frische Datei)" \
        'dd if=/dev/zero of=$(mktemp) bs=1 count=1'
# Und die Grenzen daneben, jede einzeln:
expect deny "$SN" "GRENZE: \$D/../data klettert aus dem frischen Verzeichnis" \
        'D=$(mktemp -d)
rm -rf "$D/../data"'
expect deny "$SN" "GRENZE: > \"\$UNBEKANNT/f.txt\" bleibt unentscheidbar" \
        'echo x > "$UNBEKANNT/f.txt"'
expect deny "$SN" "GRENZE: dd of=\$UNBEKANNT bleibt unentscheidbar" \
        'dd if=/dev/zero of=$UNBEKANNT bs=1 count=1'
expect deny "$SN" "GRENZE: rm -rf \$(echo <pfad>) bleibt unentscheidbar" \
        "rm -rf \$(echo $FIX/data)"
# Eigenes Verzeichnis mit eigenem Namen: die frueheren Faelle haben unter
# $FIX/snapshots Eintraege angelegt, deren Name den Teilstring "data" enthaelt
# -- gegen $FIX/data zaehlt der Guard das (zu Recht) als vorhandenen Snapshot.
mkdir -p "$FIX/echtdaten" && printf 'nutzdaten\n' > "$FIX/echtdaten/f.txt"
expect deny "$SN" "GRENZE: rm -rf auf echte Daten bleibt geblockt" \
        "rm -rf $FIX/echtdaten"
# Heredoc mit Apostroph im Text: fruehes Scheitern am Zerlegen, obwohl dort
# nur geschrieben wird. Der Guard entfernt Heredoc-Inhalte vor dem Zerlegen.
expect allow "$SN" "Heredoc mit Apostroph und Anfuehrungszeichen im Text" \
        "cat > $FIX/notiz.md <<'EOF'
Guard: don't block the \"obvious\" case
EOF"

echo
echo "--- Runde 2 (2026-08-05): Schleifenrumpf und Zuweisungsreihenfolge ---"
# Der Rumpf einer Schleife war fuer diesen Guard nie sichtbar: das einleitende
# `do` wurde als Kommandoname gelesen, `rm` dahinter nie erreicht.
# $FIX/echtdaten statt $FIX/data: gegen "data" zaehlen die weiter oben
# angelegten Snapshot-Eintraege mit "data" im Namen (zu Recht) als Sicherung.
expect deny "$SN" "Schleifenrumpf wird ueberhaupt geprueft" \
        "for x in a; do rm -rf $FIX/echtdaten; done"
# Rein literale Werteliste: jeder Wert wird eingesetzt und einzeln geprueft.
mkdir -p "$FIX/schleife/eins" "$FIX/schleife/zwei"
printf 'x\n' > "$FIX/schleife/eins/f.txt"
printf 'x\n' > "$FIX/schleife/zwei/f.txt"
expect deny "$SN" "literale Werteliste: EIN gefaehrlicher Wert reicht" \
        "for d in $FIX/leerdir $FIX/schleife/eins; do rm -rf \"\$d\"; done"
expect allow "$SN" "literale Werteliste ohne Fund geht durch" \
        'for s in eins zwei drei; do echo "$s"; done'
expect deny "$SN" "GRENZE: Liste mit Glob bleibt unentscheidbar" \
        'for f in *.sh; do rm -rf "$f"; done'
expect deny "$SN" 'GRENZE: Liste aus $(ls) bleibt unentscheidbar' \
        'for f in $(ls); do rm -rf "$f"; done'
# Eine Zuweisung gilt erst ab ihrer Stelle. `rm -rf $D/unterordner; D=/tmp/x`
# loescht zur Laufzeit /unterordner -- die alte Karte beurteilte /tmp/x/...
expect deny "$SN" "Zuweisung NACH der Verwendung zaehlt nicht mehr" \
        'rm -rf $D/unterordner
D=/tmp/x'
expect allow "$SN" "Zuweisung VOR der Verwendung zaehlt weiter" \
        'D=$(mktemp -d)
rm -rf "$D/unterordner"'

echo
echo "--- ausgelieferte snapshot-guard-exempt.conf (nur diese zwei) ---"
expect allow "$SN" "mktemp-Verzeichnis unter /var/folders ist Wegwerf-Ort" \
        "rm -rf $FIX/data" "$FIX" "$HOOKS/snapshot-guard-exempt.conf"
expect allow "$SN" "Alltag mit echter Konfiguration: ls" \
        'ls -la' "$FIX" "$HOOKS/snapshot-guard-exempt.conf"

echo
echo "=============================================================="
printf 'ERGEBNIS: %d gruen, %d rot\n' "$pass" "$fail"
echo "=============================================================="
[ "$fail" -eq 0 ]
