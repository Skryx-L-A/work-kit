#!/bin/bash
# test-mensch-m2-oberflaeche.sh -- der Menschen-Nachweis M2 (Oberflaeche als Ahne)
# muss durch die `env -i`-Aufrufe der Werkzeuge hindurch ankommen.
#
# BEFUND 26.09.2026. Seit dem Sicherheits-Review vom 21.09. rief `wb-code` sein
# `wb-mensch` mit `env -i` auf. Das loeschte WB_MENSCH_QUELLE und WB_APP_PID, also genau
# die beiden Angaben, an denen M2 haengt. Die Probe im Kern (direkter Aufruf von
# wb-mensch) sagte ja, `wb-code --mensch` danach nein: jeder Start und jedes Fortsetzen
# aus der Werkbank-App brach mit "'--mensch' abgelehnt" ab. Die bestehenden Suiten
# merkten es nicht, weil sie ein `wb-mensch` einsetzten, das immer ja sagt.
#
# Die Zusagen:
#   1  Echtes wb-code + echtes wb-mensch, unter einem Ahnen namens "electron" mit
#      WB_MENSCH_QUELLE=oberflaeche und dessen PID: `--mensch` wird angenommen.
#   2  Dieselbe Kette ohne die Variablen: abgelehnt.
#   3  WB_APP_PID zeigt auf einen Prozess, der KEIN Ahne ist: abgelehnt.
#   4  Statisch: jeder `env -i`-Aufruf von wb-mensch unter shell/ reicht M2 weiter
#      (M2_UMGEBUNG oder die ausgeschriebene Allowlist wie in wb-pane-write).
#
# Warum ein doppelter Fork: laeuft der Test unter einem Harness (Claude, pi), steht
# dieser in der Ahnenreihe und wb-mensch sagt zu Recht "Agent" (A2). Der Ahne "electron"
# wird deshalb von launchd/init adoptiert und hat kein steuerndes Terminal (kein M1).
#
# ISOLATION: eigenes HOME (mktemp -d), keine tmux-Server, keine Live-Konfiguration.
# Liegt kein wb-mensch im echten Heimatverzeichnis, verlangt wb-code dort eine zweite
# Zustimmung, die fehlt -- dann wird Zusage 1 uebersprungen statt falsch gemeldet.
unset TMUX TMUX_PANE
set -uo pipefail

SHELLDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTHOME="$(mktemp -d)"
trap 'rm -rf "$TESTHOME"' EXIT INT TERM HUP
mkdir -p "$TESTHOME/.local/bin"
cp "$SHELLDIR/wb-mensch" "$TESTHOME/.local/bin/wb-mensch"
# Symlink statt Kopie: eine kopierte /bin/bash toetet macOS (Signatur, gemessen: Exit 137).
# `ps -o comm=` zeigt den Pfad des Symlinks, also heisst der Ahne "electron".
ln -s /bin/bash "$TESTHOME/electron"

pass=0; fail=0; skip=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== M2 durch env -i (wb-code, echtes wb-mensch) =="

# Startet "$TESTHOME/electron" abgeloest (neue Sitzung, Eltern = 1) und laesst es
# wb-code --mensch aufrufen. $1: "echt" (WB_APP_PID = eigene PID), "fremd" (PID 1),
# "ohne" (keine Variablen). Ausgabe: stderr von wb-code.
lauf() {
  local art="$1" aus="$TESTHOME/aus-$1"
  /usr/bin/python3 - "$TESTHOME" "$SHELLDIR/wb-code" "$art" "$aus" <<'PY'
import os, sys, time
home, wbcode, art, aus = sys.argv[1:5]
skript = {
    'echt':  'export WB_MENSCH_QUELLE=oberflaeche WB_APP_PID=$$; ',
    'fremd': 'export WB_MENSCH_QUELLE=oberflaeche WB_APP_PID=1; ',
    'ohne':  'unset WB_MENSCH_QUELLE WB_APP_PID; ',
}[art] + f'"{wbcode}" --mensch --wbtest-unbekannt >"{aus}" 2>&1; echo fertig >>"{aus}.ende"'
env = {k: v for k, v in os.environ.items()
       if k not in ('CLAUDECODE', 'CLAUDE_CODE_ENTRYPOINT', 'CLAUDE_CODE_SESSION_ID', 'PI_AGENT', 'WB_AGENT')}
env['HOME'] = home
if os.fork() == 0:
    os.setsid()
    if os.fork() == 0:
        fd = os.open(os.devnull, os.O_RDWR)
        for i in (0, 1, 2): os.dup2(fd, i)
        os.execve(os.path.join(home, 'electron'), ['electron', '-c', skript], env)
    os._exit(0)
os.wait()
for _ in range(200):
    if os.path.exists(aus + '.ende'): break
    time.sleep(0.05)
PY
  cat "$aus" 2>/dev/null
}

WB_HEIM="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[ -n "$WB_HEIM" ] || WB_HEIM="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6)"

# 1
if [ -x "$WB_HEIM/.local/bin/wb-mensch" ]; then
  a="$(lauf echt)"
  if printf '%s' "$a" | grep -q "unbekannte Option '--wbtest-unbekannt'"; then
    ok "M2 mit echtem Ahnen: --mensch angenommen"
  else
    bad "M2 mit echtem Ahnen: erwartet angenommen, bekam: $(printf '%s' "$a" | head -2 | tr '\n' ' ')"
  fi
else
  skip=$((skip+1)); echo "  skip  kein wb-mensch unter $WB_HEIM/.local/bin -- Zusage 1 nicht messbar"
fi

# 2
a="$(lauf ohne)"
if printf '%s' "$a" | grep -q "'--mensch' abgelehnt"; then ok "ohne M2-Variablen: abgelehnt"
else bad "ohne M2-Variablen: erwartet abgelehnt, bekam: $(printf '%s' "$a" | head -1)"; fi

# 3
a="$(lauf fremd)"
if printf '%s' "$a" | grep -q "'--mensch' abgelehnt"; then ok "WB_APP_PID kein Ahne: abgelehnt"
else bad "WB_APP_PID kein Ahne: erwartet abgelehnt, bekam: $(printf '%s' "$a" | head -1)"; fi

# 4 -- jede env -i-Zeile, deren Fortsetzung wb-mensch aufruft, muss M2 weiterreichen.
luecken="$(/usr/bin/python3 - "$SHELLDIR" <<'PY'
import os, re, sys
d = sys.argv[1]
for f in sorted(os.listdir(d)):
    p = os.path.join(d, f)
    if not os.path.isfile(p): continue
    try: s = open(p, encoding='utf-8').read()
    except Exception: continue
    # Fortsetzungszeilen zusammenziehen, dann jeden env -i-Aufruf einzeln ansehen.
    for aufruf in re.findall(r'/usr/bin/env -i (?:[^\n]*\\\n)*[^\n]*', s):
        if 'wb-mensch"' not in aufruf and '"$1" beleg' not in aufruf: continue
        if 'M2_UMGEBUNG' in aufruf or 'WB_APP_PID=' in aufruf: continue
        if '"$1" beleg' in aufruf: continue   # wb-pane-write: Zweige ohne gueltige M2-Angaben
        print(f'{f}: {aufruf.splitlines()[-1].strip()}')
PY
)"
if [ -z "$luecken" ]; then ok "statisch: jeder env -i-Aufruf von wb-mensch reicht M2 weiter"
else bad "statisch: env -i ohne M2-Weitergabe:"; printf '        %s\n' "$luecken"; fi

echo "== $pass ok, $fail FAIL, $skip uebersprungen =="
[ "$fail" -eq 0 ]
