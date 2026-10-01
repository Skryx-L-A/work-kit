#!/usr/bin/env bash
# test-run-all-appbau.sh -- die Baustufe von run-all.sh fuer app/ (15.08.).
#
# ANLASS (Reviewer-Pass zur Kontextwache, 2026-08-15): run-all.sh baute app/
# nicht. Jede der rund dreissig test-app-*.sh-Suiten liest app/dist/test/*.mjs
# und ueberspringt sich per Exit 77, wenn dort nichts liegt. Ein fehlender oder
# veralteter Baustand machte damit die halbe Testerfassung still wirkungslos:
# lauter SKIP-Zeilen, Exit-Code 0, und die geprueften Zusagen -- zuletzt die
# ganze neue Kontextwache -- waren nie gelaufen.
#
# DIE ZUSAGEN:
#   1  Fehlt app/ ganz, ist das ein SKIP mit Grund (ein Klon ohne App ist kein
#      Fehlschlag).
#   2  Laesst sich nicht bauen (kein npm oder kein app/node_modules) UND fehlt
#      app/dist, ist das ein FAIL -- laut, weil die App-Suiten danach nichts
#      pruefen.
#   3  Derselbe Fall mit AKTUELLEM app/dist ist ein SKIP mit Grund: gebaut wird
#      nicht, geprueft schon.
#   4  Ist app/dist aelter als eine Quelldatei, ist das ein FAIL -- ein
#      veralteter Baustand prueft die alte Fassung und sagt es nicht.
#   5  Kann gebaut werden, wird gebaut -- und ein gelungener Bau ist ein PASS.
#   6  Ein gescheiterter Bau ist ein FAIL und nennt, dass ohne ihn nichts
#      geprueft wird.
#
# ISOLATION: Die beiden Funktionen werden aus run-all.sh HERAUSGESCHNITTEN und
# in dieser Shell ausgefuehrt -- run-all.sh selbst wird NIE gestartet. Das ist
# Absicht: ein echter Lauf nimmt die globale Sperre unter ~/.local/state/ und
# faehrt alle Suiten (Minuten), und beides gehoert nicht in eine Suite, die nur
# die Baustufe prueft. Gearbeitet wird ausschliesslich in einem
# Wegwerfverzeichnis mit gestelltem app/, npm ist ein Stellvertreter im PATH.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNALL="$REPO/shell/tests/run-all.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== Die Baustufe von run-all.sh =="
[ -f "$RUNALL" ] || { bad "run-all.sh fehlt"; echo "== $pass ok, $fail FAIL =="; exit 1; }

WEG="$(mktemp -d)"
trap 'rm -rf "$WEG"' EXIT

# Die beiden Funktionen aus run-all.sh schneiden. Beide enden auf einer Zeile,
# die mit '}' in Spalte 1 beginnt -- alle inneren Bloecke sind eingerueckt.
sed -n '/^app_dist_veraltet()/,/^}/p' "$RUNALL" > "$WEG/funktionen.sh"
sed -n '/^run_app_build()/,/^}/p' "$RUNALL" >> "$WEG/funktionen.sh"
grep -q 'run_app_build()' "$WEG/funktionen.sh" \
  && ok "die Baustufe laesst sich aus run-all.sh herausschneiden" \
  || { bad "run_app_build() nicht in run-all.sh gefunden"; echo "== $pass ok, $fail FAIL =="; exit 1; }

# Ein npm-Stellvertreter: er baut nichts, er meldet nur, was der Test will.
mkdir -p "$WEG/bin"
cat > "$WEG/bin/npm" <<'EOF'
#!/usr/bin/env bash
echo "npm-Stellvertreter: $*"
exit "${STELLVERTRETER_NPM_CODE:-0}"
EOF
chmod +x "$WEG/bin/npm"

# $1 = Name des Falls, danach die Lage. Gibt "STATUS|GRUND" zurueck.
stufe() {
  local fallordner="$1" mit_npm="$2"
  (
    set +u
    REPO_ROOT="$fallordner"
    APP_DIR="$fallordner/app"
    APP_STEMPEL="$APP_DIR/dist/main/main.js"
    TIMEOUT_BIN=""
    DEFAULT_TIMEOUT=60
    declare -a NAMES STATUSES DURATIONS REASONS
    PASS_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
    [ "$mit_npm" = "mit-npm" ] && PATH="$WEG/bin:$PATH"
    # shellcheck disable=SC1090
    . "$WEG/funktionen.sh"
    run_app_build >/dev/null 2>&1
    printf '%s|%s\n' "${STATUSES[0]}" "${REASONS[0]}"
  )
}

# Baut eine Lage: $1 = Ordner, $2 = mit dist?, $3 = mit node_modules?
lage() {
  local o="$WEG/$1"
  rm -rf "$o"; mkdir -p "$o/app/src"
  printf 'export const x = 1;\n' > "$o/app/src/quelle.ts"
  [ "$2" = "dist" ] && { mkdir -p "$o/app/dist/main"; printf 'gebaut\n' > "$o/app/dist/main/main.js"; }
  [ "$3" = "module" ] && mkdir -p "$o/app/node_modules"
  echo "$o"
}

# --- 1: ohne app/ --------------------------------------------------------------
rm -rf "$WEG/ohne-app"; mkdir -p "$WEG/ohne-app"
erg="$(stufe "$WEG/ohne-app" ohne-npm)"
case "$erg" in
  SKIP*) ok "ohne app/ ist die Baustufe ein SKIP mit Grund" ;;
  *) bad "ohne app/ kam '$erg' statt SKIP" ;;
esac

# --- 2: nicht baubar, dist fehlt -----------------------------------------------
o="$(lage kein-dist nichts nichts)"
erg="$(stufe "$o" ohne-npm)"
case "$erg" in
  FAIL*fehlt*) ok "fehlt app/dist und laesst sich nicht bauen, ist das ein FAIL" ;;
  *) bad "fehlendes app/dist ergab '$erg' statt FAIL" ;;
esac

# --- 3: nicht baubar, dist aktuell ---------------------------------------------
o="$(lage dist-aktuell dist nichts)"
# Der Baustand muss NEUER sein als die Quelle.
touch "$o/app/dist/main/main.js"
erg="$(stufe "$o" ohne-npm)"
case "$erg" in
  SKIP*aktuell*) ok "ein aktuelles app/dist ohne Baumoeglichkeit ist ein SKIP mit Grund" ;;
  *) bad "aktuelles app/dist ergab '$erg' statt SKIP" ;;
esac

# --- 4: nicht baubar, dist veraltet --------------------------------------------
o="$(lage dist-alt dist nichts)"
touch "$o/app/dist/main/main.js"
sleep 1
printf 'export const y = 2;\n' > "$o/app/src/neuer.ts"
erg="$(stufe "$o" ohne-npm)"
case "$erg" in
  FAIL*aelter*) ok "ein veraltetes app/dist ohne Baumoeglichkeit ist ein FAIL" ;;
  *) bad "veraltetes app/dist ergab '$erg' statt FAIL" ;;
esac

# --- 5/6: gebaut wird, wenn es geht --------------------------------------------
o="$(lage baubar dist module)"
erg="$(STELLVERTRETER_NPM_CODE=0 stufe "$o" mit-npm)"
case "$erg" in
  PASS*) ok "ist ein Bau moeglich, wird gebaut -- und ein gelungener Bau ist ein PASS" ;;
  *) bad "der gelungene Bau ergab '$erg' statt PASS" ;;
esac
erg="$(STELLVERTRETER_NPM_CODE=1 stufe "$o" mit-npm)"
case "$erg" in
  FAIL*"pruefen die App-Suiten nichts"*) ok "ein gescheiterter Bau ist ein FAIL und sagt, was daran haengt" ;;
  *) bad "der gescheiterte Bau ergab '$erg' statt FAIL mit Begruendung" ;;
esac

echo "== $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
