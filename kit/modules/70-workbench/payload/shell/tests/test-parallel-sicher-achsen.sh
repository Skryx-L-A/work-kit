#!/usr/bin/env bash
# test-parallel-sicher-achsen.sh -- der Nachweis fuer die geschaerfte
# ist_parallel_sicher aus lib-parallel-sicher.sh (Auftrag 2026-08-22).
#
# ANLASS: wb-notbremse hat am 21.08. den Modellserver einer Nachbarsuite
# erschossen, obwohl beide Suiten die damalige Pruefung (nur die $HOME-Achse)
# bestanden hatten. Der Auftrag verlangt einen Nachweis in BEIDE Richtungen:
# die geschaerfte Pruefung muss den Notbremsen-Fall und die genannten
# Beispiele wirklich finden, UND sie darf die sauberen Suiten dieses Bestands
# nicht faelschlich einsammeln. Nur eine Richtung zu zeigen sagt nichts.
#
# ISOLATION: reine Textpruefung gegen Dateien in einem eigenen mktemp-Ordner
# sowie LESEND gegen den echten Bestand von shell/tests/*.sh -- kein $HOME,
# kein tmux, kein Netz, kein Schreiben ausserhalb des eigenen WORK-Ordners.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$REPO/tests"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# shellcheck source=lib-parallel-sicher.sh
. "$TESTS_DIR/lib-parallel-sicher.sh"

# --- 1: der Notbremsen-Fall selbst ------------------------------------------
echo "-- 1: wb-notbremse ohne/mit Zaun --"

cat > "$WORK/ohne-zaun.sh" <<'EOF'
#!/usr/bin/env bash
TOOL="$REPO/wb-notbremse"
"$TOOL" jetzt --schwelle-mib 1024
EOF
if notbremse_ohne_zaun_gefunden "$WORK/ohne-zaun.sh"; then
    ok "1a: wb-notbremse OHNE WB_NOTBREMSE_NUR_MUSTER wird gefunden (der Vorfall vom 21.08.)"
else
    bad "1a: wb-notbremse ohne Zaun wurde NICHT gefunden"
fi
if ist_parallel_sicher "$WORK/ohne-zaun.sh"; then
    bad "1a: ist_parallel_sicher haelt die fensterlose Suite trotzdem fuer parallel-sicher"
else
    ok "1a: ist_parallel_sicher verweigert die fensterlose Suite den Parallel-Pool"
fi

cat > "$WORK/mit-zaun.sh" <<'EOF'
#!/usr/bin/env bash
TOOL="$REPO/wb-notbremse"
WB_NOTBREMSE_NUR_MUSTER="$MARKE" "$TOOL" jetzt --schwelle-mib 1024
EOF
if notbremse_ohne_zaun_gefunden "$WORK/mit-zaun.sh"; then
    bad "1b: wb-notbremse MIT Zaun wird trotzdem als ungezaeunt gemeldet"
else
    ok "1b: wb-notbremse mit gesetztem WB_NOTBREMSE_NUR_MUSTER gilt als eingegrenzt"
fi

[ -f "$REPO/test-notbremse.sh" ] 2>/dev/null # no-op, Pfad unten ist der richtige
if notbremse_ohne_zaun_gefunden "$TESTS_DIR/test-notbremse.sh"; then
    bad "1c: die echte test-notbremse.sh (setzt den Zaun selbst) wird faelschlich als ungezaeunt gemeldet"
else
    ok "1c: die echte test-notbremse.sh bleibt unbeanstandet -- sie setzt den Zaun bereits"
fi

# 1d (03.09.2026): der NAME in einem Meldetext ist kein Aufruf. `test-belegung.sh`
# nennt `wb-notbremse` seit dem 27.08. in einem `ok "..."`-Text und fiel dadurch
# aus dem Parallel-Pool, obwohl es das Werkzeug nie ruft -- im vollen Lauf war
# das eine rote Suite. Dieselbe Unterscheidung, die Punkt 2d fuer pkill haelt.
cat > "$WORK/nur-genannt.sh" <<'EOF'
#!/usr/bin/env bash
ok "die Reserve steht auf 0,0 GiB -- wb-notbremse ist der Ersatz"
echo "siehe wb-notbremse fuer die Schwelle"
EOF
if notbremse_ohne_zaun_gefunden "$WORK/nur-genannt.sh"; then
    bad "1d: der blosse Name in einem Meldetext wurde als Aufruf gezaehlt"
else
    ok "1d: 'wb-notbremse' als reiner Text (Meldung, Hinweis) zaehlt nicht als Aufruf"
fi

# 1e (Nachlese, 04.09.2026, Pruefer-Befund 2): vier Aufrufformen, die der
# Ausdruck vom 03.09. noch verfehlte -- ein Aufruf hinter `if`, `then` oder
# `do`, einer hinter `xargs`, und einer in Rueckwaertsapostrophen. Alle fuenf
# sind echte Aufrufe OHNE Zaun und muessen gefunden werden.
cat > "$WORK/vier-formen.sh" <<'EOF'
#!/usr/bin/env bash
if wb-notbremse jetzt --schwelle-mib 1024; then echo ok; fi
EOF
if notbremse_ohne_zaun_gefunden "$WORK/vier-formen.sh"; then
    ok "1e: 'if wb-notbremse ...' wird gefunden"
else
    bad "1e: 'if wb-notbremse ...' wurde NICHT gefunden"
fi

cat > "$WORK/vier-formen.sh" <<'EOF'
#!/usr/bin/env bash
true; then wb-notbremse jetzt --schwelle-mib 1024
EOF
if notbremse_ohne_zaun_gefunden "$WORK/vier-formen.sh"; then
    ok "1e: 'then wb-notbremse ...' wird gefunden"
else
    bad "1e: 'then wb-notbremse ...' wurde NICHT gefunden"
fi

cat > "$WORK/vier-formen.sh" <<'EOF'
#!/usr/bin/env bash
for m in a b; do wb-notbremse jetzt --schwelle-mib 1024; done
EOF
if notbremse_ohne_zaun_gefunden "$WORK/vier-formen.sh"; then
    ok "1e: 'do wb-notbremse ...' wird gefunden"
else
    bad "1e: 'do wb-notbremse ...' wurde NICHT gefunden"
fi

cat > "$WORK/vier-formen.sh" <<'EOF'
#!/usr/bin/env bash
echo x | xargs wb-notbremse jetzt --schwelle-mib 1024
EOF
if notbremse_ohne_zaun_gefunden "$WORK/vier-formen.sh"; then
    ok "1e: 'xargs wb-notbremse ...' wird gefunden"
else
    bad "1e: 'xargs wb-notbremse ...' wurde NICHT gefunden"
fi

cat > "$WORK/vier-formen.sh" <<'EOF'
#!/usr/bin/env bash
stand=`wb-notbremse jetzt --schwelle-mib 1024`
EOF
if notbremse_ohne_zaun_gefunden "$WORK/vier-formen.sh"; then
    ok "1e: Aufruf in Rueckwaertsapostrophen wird gefunden"
else
    bad "1e: Aufruf in Rueckwaertsapostrophen wurde NICHT gefunden"
fi

# --- 2: pkill/killall auf ein ungebundenes Muster ---------------------------
echo "-- 2: pkill/killall gebunden vs. ungebunden --"

cat > "$WORK/pkill-bloss.sh" <<'EOF'
#!/usr/bin/env bash
pkill -f ollama
EOF
if pkill_ungebunden_gefunden "$WORK/pkill-bloss.sh"; then
    ok "2a: 'pkill -f ollama' ohne jede Variable im Muster wird gefunden"
else
    bad "2a: das woertliche, ungebundene pkill-Muster wurde NICHT gefunden"
fi
if ist_parallel_sicher "$WORK/pkill-bloss.sh"; then
    bad "2a: ist_parallel_sicher haelt das ungebundene pkill trotzdem fuer parallel-sicher"
else
    ok "2a: ist_parallel_sicher verweigert das ungebundene pkill den Parallel-Pool"
fi

cat > "$WORK/killall-bloss.sh" <<'EOF'
#!/usr/bin/env bash
killall mlx_lm.server
EOF
if pkill_ungebunden_gefunden "$WORK/killall-bloss.sh"; then
    ok "2b: 'killall mlx_lm.server' ohne Variable wird ebenso gefunden"
else
    bad "2b: das woertliche killall wurde NICHT gefunden"
fi

cat > "$WORK/pkill-gebunden.sh" <<'EOF'
#!/usr/bin/env bash
SOCKET="wbtest-suite-$$"
pkill -f "fake-modell.py.*$SOCKET" 2>/dev/null
EOF
if pkill_ungebunden_gefunden "$WORK/pkill-gebunden.sh"; then
    bad "2c: pkill mit eigenem, per-Lauf eindeutigem Muster wird faelschlich als ungebunden gemeldet"
else
    ok "2c: pkill mit \$SOCKET im Muster gilt als an diesen Lauf gebunden"
fi

cat > "$WORK/pkill-nur-text.sh" <<'EOF'
#!/usr/bin/env bash
# Testdaten, kein Aufruf -- derselbe Fall wie test-ereignisse.sh
ZEILE='{"command":"pkill x","cwd":"/tmp"}'
echo "$ZEILE"
EOF
if pkill_ungebunden_gefunden "$WORK/pkill-nur-text.sh"; then
    bad "2d: 'pkill' als Text mitten in einer JSON-Testzeile wird faelschlich als Aufruf gezaehlt"
else
    ok "2d: 'pkill' als reiner Text (nicht am Zeilenanfang) zaehlt nicht als Aufruf"
fi

# Die sieben echten pkill/killall-Aufrufe im Bestand (Stand 2026-08-22) --
# jeder muss als gebunden gelten, sonst waere der Fund ein falscher Alarm.
echo "-- 2e: die echten pkill-Aufrufe im Bestand --"
ECHTE_TREFFER=0
for f in "$TESTS_DIR"/test-*.sh; do
    [ "$(basename "$f")" = "$(basename "$0")" ] && continue
    grep -vE '^[[:space:]]*#' "$f" | grep -qE '^[[:space:]]*(pkill|killall)\b' || continue
    ECHTE_TREFFER=$((ECHTE_TREFFER+1))
    if pkill_ungebunden_gefunden "$f"; then
        bad "2e: $(basename "$f") hat einen echten pkill/killall-Aufruf, der als ungebunden gilt"
    fi
done
if [ "$ECHTE_TREFFER" -ge 1 ]; then
    ok "2e: $ECHTE_TREFFER echte(r) pkill/killall-Aufruf(e) im Bestand geprueft, keiner faelschlich ungebunden"
else
    bad "2e: kein einziger echter pkill/killall-Aufruf im Bestand gefunden -- die Gegenprobe lief leer"
fi

# --- 3: bekannte, suiten-uebergreifende Umgebungsvariablen ------------------
echo "-- 3: WB_EIGENTUEMER_WERKBANK gebunden vs. ungebunden --"

cat > "$WORK/env-ungebunden.sh" <<'EOF'
#!/usr/bin/env bash
if [ "$WB_EIGENTUEMER_WERKBANK" = "$$" ]; then
    echo "eigener Lauf"
fi
EOF
if env_var_ungebunden_gefunden "$WORK/env-ungebunden.sh"; then
    ok "3a: ein echter Lese-Zugriff auf \$WB_EIGENTUEMER_WERKBANK ohne lokale Bindung wird gefunden"
else
    bad "3a: der ungebundene Lese-Zugriff wurde NICHT gefunden"
fi
if ist_parallel_sicher "$WORK/env-ungebunden.sh"; then
    bad "3a: ist_parallel_sicher haelt die ungebundene Suite trotzdem fuer parallel-sicher"
else
    ok "3a: ist_parallel_sicher verweigert die ungebundene Suite den Parallel-Pool"
fi

cat > "$WORK/env-gesetzt.sh" <<'EOF'
#!/usr/bin/env bash
WB_EIGENTUEMER_WERKBANK="$$"
if [ "$WB_EIGENTUEMER_WERKBANK" = "$$" ]; then
    echo "eigener Lauf"
fi
EOF
if env_var_ungebunden_gefunden "$WORK/env-gesetzt.sh"; then
    bad "3b: eine Suite, die die Variable selbst setzt, gilt trotzdem als ungebunden"
else
    ok "3b: eine selbst gesetzte Variable gilt als gebunden"
fi

cat > "$WORK/env-unset.sh" <<'EOF'
#!/usr/bin/env bash
AUS="$(env -u WB_EIGENTUEMER_WERKBANK tool)"
echo "$WB_EIGENTUEMER_WERKBANK"
EOF
if env_var_ungebunden_gefunden "$WORK/env-unset.sh"; then
    bad "3c: eine Suite mit 'env -u WB_EIGENTUEMER_WERKBANK' gilt trotzdem als ungebunden"
else
    ok "3c: 'env -u WB_EIGENTUEMER_WERKBANK' zaehlt als lokale Bindung (Ausschluss)"
fi

cat > "$WORK/env-heredoc-escaped.sh" <<'OUTER'
#!/usr/bin/env bash
cat > "$STUB" <<'INNER'
echo "WB_EIGENTUEMER_WERKBANK=\${WB_EIGENTUEMER_WERKBANK:-<nicht gesetzt>}"
INNER
OUTER
if env_var_ungebunden_gefunden "$WORK/env-heredoc-escaped.sh"; then
    bad "3d: ein Backslash-entschaerfter Heredoc-Literal (gilt erst im Kindprozess) wird faelschlich als Lese-Zugriff gezaehlt"
else
    ok "3d: der Backslash-entschaerfte Heredoc-Literal zaehlt nicht als Lese-Zugriff (test-app-mensch-sitzungsstart.sh-Fall)"
fi

if env_var_ungebunden_gefunden "$TESTS_DIR/test-wb-nohup-eigentuemer.sh"; then
    bad "3e: die echte test-wb-nohup-eigentuemer.sh (bindet die Variable durchgehend) wird faelschlich beanstandet"
else
    ok "3e: die echte test-wb-nohup-eigentuemer.sh bleibt unbeanstandet"
fi

# --- 4: Gegenprobe ueber den GANZEN echten Bestand --------------------------
# Die eigentliche Zusage: keine Suite, die die ALTE (nur $HOME-basierte)
# Pruefung schon bestanden hat, faellt durch die drei neuen Achsen aus dem
# Parallel-Pool. Ein Fund hier waere ein echter falscher Alarm dieser Arbeit.
echo "-- 4: Gegenprobe ueber $(ls "$TESTS_DIR"/test-*.sh 2>/dev/null | wc -l | tr -d ' ') echte Suiten --"

alt_sicher() {
    local pfad="$1" name
    name="$(basename "$pfad")"
    case "$NICHT_PARALLEL_NAMEN" in *" $name "*) return 1 ;; esac
    grep -qE '\$HOME|~/\.claude|~/\.local|~/work/brain' "$pfad" || return 0
    grep -qE '(^|[^A-Za-z_])HOME=' "$pfad" && return 0
    case "$LESEND_LIVE_ALLOWLIST" in *" $name "*) return 0 ;; esac
    return 1
}

FLIPS=0
ALT_SICHER_ZAHL=0
for f in "$TESTS_DIR"/test-*.sh; do
    [ "$(basename "$f")" = "$(basename "$0")" ] && continue
    if alt_sicher "$f"; then
        ALT_SICHER_ZAHL=$((ALT_SICHER_ZAHL+1))
        if ! ist_parallel_sicher "$f"; then
            FLIPS=$((FLIPS+1))
            bad "4: $(basename "$f") war unter der alten Pruefung parallel-sicher und faellt jetzt heraus"
        fi
    fi
done
if [ "$FLIPS" -eq 0 ] && [ "$ALT_SICHER_ZAHL" -ge 1 ]; then
    ok "4: alle $ALT_SICHER_ZAHL vorher sicheren Suiten bleiben es -- keine neue Achse sammelt faelschlich ein"
elif [ "$ALT_SICHER_ZAHL" -eq 0 ]; then
    bad "4: keine einzige vorher sichere Suite gefunden -- die Gegenprobe lief leer"
fi

echo
echo "  bestanden: $pass, gescheitert: $fail"
[ "$fail" -eq 0 ]
