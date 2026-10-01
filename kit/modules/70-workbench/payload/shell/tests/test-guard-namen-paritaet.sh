#!/usr/bin/env bash
# Die Guard-Namen stehen an ZWEI Stellen, und sie sind am 2026-08-16 auseinander
# gelaufen: `hooks/bash-guard.py` fuehrt sie in GUARD_NAMES, `shell/wb-state`
# noch einmal in der BEKANNT-Liste von `guard set/get/list`. Dort fehlten
# `pane-write` (seit dem 2026-08-06) und `git-add` (seit heute) — mit der Folge,
# dass `wb-state guard set pane-write aus --grund '…'` die beiden als unbekannt
# ABLEHNTE. Ein Guard, den niemand abschalten kann, ist kein strengerer Guard,
# sondern einer ohne Notausgang; und gemerkt haette es niemand, weil beide
# Seiten fuer sich genommen fehlerfrei laufen.
#
# Diese Suite vergleicht die beiden Listen und nennt die Abweichung beim Namen.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== Guard-Namen: bash-guard.py gegen wb-state =="

PY="hooks/bash-guard.py"
ST="shell/wb-state"
[ -f "$PY" ] || { echo "  FAIL  $PY fehlt"; exit 1; }
[ -f "$ST" ] || { echo "  FAIL  $ST fehlt"; exit 1; }

# Beide Listen aus dem Quelltext lesen, nicht aus einer dritten Quelle: es geht
# genau darum, ob die zwei Stellen im Code dasselbe sagen.
namen() {  # $1 = Datei, $2 = Variablenname
  python3 - "$1" "$2" <<'PY'
import ast, re, sys
quelle, var = sys.argv[1], sys.argv[2]
text = open(quelle, encoding='utf-8').read()
# Die Zuweisung samt (mehrzeiliger) Liste herausschneiden und als Literal lesen.
m = re.search(rf'^\s*{re.escape(var)}\s*=\s*(\[.*?\])', text, re.S | re.M)
if not m:
    sys.exit(f'{var} in {quelle} nicht gefunden')
for n in ast.literal_eval(m.group(1)):
    print(n)
PY
}

A="$(namen "$PY" GUARD_NAMES)" || { echo "  FAIL  GUARD_NAMES nicht lesbar: $A"; exit 1; }
B="$(namen "$ST" BEKANNT)"     || { echo "  FAIL  BEKANNT nicht lesbar: $B"; exit 1; }

[ -n "$A" ] && ok "GUARD_NAMES gelesen ($(printf '%s\n' "$A" | wc -l | tr -d ' ') Namen)" \
            || bad "GUARD_NAMES ist leer"
[ -n "$B" ] && ok "BEKANNT gelesen ($(printf '%s\n' "$B" | wc -l | tr -d ' ') Namen)" \
            || bad "BEKANNT ist leer"

NUR_A="$(comm -23 <(printf '%s\n' "$A" | sort) <(printf '%s\n' "$B" | sort))"
NUR_B="$(comm -13 <(printf '%s\n' "$A" | sort) <(printf '%s\n' "$B" | sort))"

[ -z "$NUR_A" ] && ok "jeder Guard aus bash-guard.py ist in wb-state abschaltbar" \
                || bad "in bash-guard.py, aber nicht in wb-state (nicht abschaltbar): $(printf '%s' "$NUR_A" | tr '\n' ' ')"
[ -z "$NUR_B" ] && ok "wb-state kennt keinen Guard, den bash-guard.py nicht fuehrt" \
                || bad "in wb-state, aber nicht in bash-guard.py (Name geht ins Leere): $(printf '%s' "$NUR_B" | tr '\n' ' ')"

echo
echo "guard-namen-paritaet: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
