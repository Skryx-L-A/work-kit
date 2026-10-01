#!/usr/bin/env bash
# test-check-resources-ollama.sh -- die drei Faelle, die shell/check-resources bei
# Ollama unterscheiden muss (Nachtrag vom 16.08. zum wb-belegung-Umbau).
#
# ANLASS: `wb-belegung` liest seit diesem Umbau `ollama_loaded` aus dieser Datei,
# um Ollama-Ladungen als Belegung zu fuehren. Vorher galt: OLLAMA_LOADED_JSON wird
# leer, egal ob wirklich nichts geladen ist oder ob die Abfrage nur gescheitert
# ist -- ununterscheidbar. Genau das ist der Fehler, den die Kontextwache lehrt:
# unbekannt wird zu frei. Gemessen wird hier, ob check-resources die drei Faelle
# sauber trennt:
#   1  Ollama nicht installiert            -> ollama_note gesetzt, KEIN unbekannt.
#   2  Ollama installiert, Server tot      -> ollama_note gesetzt, KEIN unbekannt
#      (ein toter Server haelt sicher nichts -- kein Rateversuch gegen den Port).
#   3  Server antwortet auf 'ollama ps',
#      aber /api/ps nicht                  -> ollama_loaded_note gesetzt: genau
#      der Fall, der vorher lautlos als "nichts geladen" durchging.
#   4  Beides antwortet                    -> echte Groesse in MiB, expires_at
#      durchgereicht (die maschinenlesbare UNTIL-Spalte fuer wb-belegung).
#
# ATTRAPPEN, NIE DER ECHTE DAEMON: 'ollama' und 'curl' kommen aus einem eigenen
# Verzeichnis vorn im PATH, das reale Homebrew-'ollama' (/opt/homebrew/bin) bleibt
# aussen vor. Kein Modell wird geladen, kein Port angesprochen.
set -uo pipefail

TOOL="${CHECK_RESOURCES:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/check-resources}"
echo "Geprueft: $TOOL"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

STUB="$(mktemp -d)"
trap 'rm -rf "$STUB"' EXIT
# Minimaler System-PATH ohne Homebrew: dort und nur dort sitzt das echte 'ollama'
# auf dieser Maschine (which ollama -> /opt/homebrew/bin/ollama). jq, curl, vm_stat,
# sysctl, ioreg, awk, sed, head, hostname, date, uname liegen alle unter /usr oder
# /bin und bleiben verfuegbar -- reine Systemabfragen, kein Modell, kein Daemon.
SYSTEM_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

lauf() {   # <path> -> stdout von check-resources, rc in $RC
    RC=0
    OUT="$(PATH="$1" "$TOOL" 2>/dev/null)" || RC=$?
}

# Vorgabe-Attrappe fuer 'ps': KEIN lokaler Modell-Laeufer. Ab Abschnitt 6 fragt
# check-resources bei einem fremden Portnamen zusaetzlich 'ps' (siehe dort,
# ollama_lokale_laeufer_lage), um Bedarfsschaltung von Portforward zu
# unterscheiden -- und diese Attrappe muss von Anfang an stehen, sonst wuerde
# Abschnitt 5 ("ssh-Portforward -> fremd") die ECHTE Prozessliste dieser
# Maschine befragen und waere gruen oder rot, je nachdem, was hier gerade
# laeuft (auf dieser Maschine z.B. ein echter Homebrew-ollama mit eigenen
# llama-server-Prozessen). Eine leere Liste ist die sichere Vorgabe.
cat > "$STUB/ps" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$STUB/ps"

# LEHRE DIESER WOCHE: eine Werkzeugsuche kann eine Attrappe still aushebeln
# (etwa durch ein umgelenktes HOME, das vor dem PATH-Verzeichnis rangiert), und
# ein Test, der dann trotzdem gruen meldet, hat nichts geprueft. Deshalb hier
# und an jeder Stelle unten, an der eine neue Attrappe entsteht, der
# Gegencheck: unter genau dem PATH, den 'lauf()' an check-resources
# durchreicht, muss das Werkzeug auf die Attrappe in $STUB aufloesen, nicht
# auf ein echtes Systemprogramm. Eine kleine Helferfunktion, weil derselbe
# Check unten fuer 'ollama', 'curl', 'lsof'/'ss' und noch einmal fuer 'ps'
# (mit geaendertem Inhalt) wiederkehrt.
pruefe_attrappe_greift() {   # <werkzeugname>
    local gefunden
    gefunden="$(PATH="$STUB:$SYSTEM_PATH" command -v "$1" 2>/dev/null || true)"
    if [ "$gefunden" = "$STUB/$1" ]; then
        ok "'$1' loest unter dem Test-PATH auf die Attrappe auf, nicht die echte Maschine"
    else
        bad "'$1' loest auf '$gefunden' auf statt auf '$STUB/$1' -- der Test wuerde die echte Maschine befragen"
    fi
}
pruefe_attrappe_greift ps

echo
echo "== 1  Ollama nicht installiert: sicher leer, kein 'unbekannt' =="
lauf "$SYSTEM_PATH"
if [ "$RC" = "0" ]; then ok "check-resources laeuft auch ganz ohne ollama im PATH"
else bad "check-resources brach ab (rc=$RC)"; fi
if printf '%s' "$OUT" | jq -e '.ollama_note == "ollama not installed"' >/dev/null 2>&1; then
    ok "ollama_note nennt 'ollama not installed'"
else
    bad "ollama_note fehlt oder falsch: $(printf '%s' "$OUT" | jq -c '.ollama_note' 2>&1)"
fi
if printf '%s' "$OUT" | jq -e '.ollama_loaded == [] and .ollama_loaded_note == ""' >/dev/null 2>&1; then
    ok "ollama_loaded ist leer, ohne 'unbekannt'-Vermerk"
else
    bad "ollama_loaded/ollama_loaded_note falsch: $(printf '%s' "$OUT" | jq -c '{l:.ollama_loaded,n:.ollama_loaded_note}' 2>&1)"
fi

echo
echo "== 2  Ollama installiert, Server tot: sicher leer, kein Rateversuch =="
cat > "$STUB/ollama" <<'EOF'
#!/bin/sh
# Kein Server erreichbar -- wie ein totes 'ollama ps'.
exit 1
EOF
chmod +x "$STUB/ollama"
lauf "$STUB:$SYSTEM_PATH"
if printf '%s' "$OUT" | jq -e '.ollama_note == "ollama server not running"' >/dev/null 2>&1; then
    ok "ollama_note nennt 'ollama server not running'"
else
    bad "ollama_note falsch: $(printf '%s' "$OUT" | jq -c '.ollama_note' 2>&1)"
fi
if printf '%s' "$OUT" | jq -e '.ollama_loaded == [] and .ollama_loaded_note == ""' >/dev/null 2>&1; then
    ok "ein toter Server gilt als sicher leer, nicht als 'unbekannt'"
else
    bad "ein toter Server wurde faelschlich als unbekannt gefuehrt: $(printf '%s' "$OUT" | jq -c '.ollama_loaded_note' 2>&1)"
fi

echo
echo "== 3  Server antwortet auf 'ollama ps', /api/ps aber nicht: UNBEKANNT =="
cat > "$STUB/ollama" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "ps" ]; then
    printf 'NAME\tID\tSIZE\tPROCESSOR\tUNTIL\n'
    printf 'lmalpha:9b\tdeadbeef\t6.4 GB\t100%% GPU\t4 minutes from now\n'
    exit 0
fi
exit 0
EOF
chmod +x "$STUB/ollama"
cat > "$STUB/curl" <<'EOF'
#!/bin/sh
# /api/ps nicht erreichbar -- der genaue Fehler, den vorher niemand sah.
exit 7
EOF
chmod +x "$STUB/curl"
lauf "$STUB:$SYSTEM_PATH"
if printf '%s' "$OUT" | jq -e '.ollama_note == ""' >/dev/null 2>&1; then
    ok "der Server gilt als erreichbar (ollama_note leer, 'ollama ps' antwortete ja)"
else
    bad "ollama_note haette leer sein muessen: $(printf '%s' "$OUT" | jq -c '.ollama_note' 2>&1)"
fi
if printf '%s' "$OUT" | jq -e '.ollama_loaded == [] and (.ollama_loaded_note | length) > 0' >/dev/null 2>&1; then
    ok "genau DIESER Fall wird als UNBEKANNT markiert (ollama_loaded_note gesetzt), nicht als leer"
else
    bad "der gescheiterte /api/ps-Aufruf wurde stillschweigend zu 'nichts geladen': $(printf '%s' "$OUT" | jq -c '{l:.ollama_loaded,n:.ollama_loaded_note}' 2>&1)"
fi

echo
echo "== 4  Beides antwortet: echte Groesse und expires_at kommen durch =="
# Ab hier gehoert auch der Portbesitzer zur Fixture. Ohne ihn haenge das
# Ergebnis an der Maschine, auf der die Suite gerade laeuft: auf dem Mac
# lauscht ein echter ollama auf 11434, auf host2 ein ssh-Portforward -- dieselbe
# Suite waere hier gruen und dort rot, ohne dass sich am Pruefling etwas
# aendert. Beide Werkzeuge werden gestellt, damit die Fixture unter Darwin
# (lsof) und unter Linux (ss) dieselbe Aussage macht.
portbesitzer() {   # <befehlsname>
    cat > "$STUB/lsof" <<EOF
#!/bin/sh
echo "p1234"
echo "c$1"
EOF
    cat > "$STUB/ss" <<EOF
#!/bin/sh
echo 'LISTEN 0 128 127.0.0.1:11434 0.0.0.0:* users:(("$1",pid=1234,fd=4))'
EOF
    chmod +x "$STUB/lsof" "$STUB/ss"
}
portbesitzer ollama
cat > "$STUB/curl" <<'EOF'
#!/bin/sh
cat <<'JSON'
{"models":[{"name":"lmalpha:9b","size":4294967296,"expires_at":"2026-08-16T21:12:00Z"}]}
JSON
EOF
chmod +x "$STUB/curl"
lauf "$STUB:$SYSTEM_PATH"
if printf '%s' "$OUT" | jq -e '.ollama_loaded_note == ""' >/dev/null 2>&1; then
    ok "kein 'unbekannt'-Vermerk, wenn beide Aufrufe gelingen"
else
    bad "ollama_loaded_note haette leer sein muessen: $(printf '%s' "$OUT" | jq -c '.ollama_loaded_note' 2>&1)"
fi
if printf '%s' "$OUT" | jq -e '.ollama_loaded[0].name == "lmalpha:9b" and .ollama_loaded[0].size_mib == 4096' >/dev/null 2>&1; then
    ok "4294967296 Bytes werden zu 4096 MiB -- echte Groesse, nicht die formatierte CLI-Spalte"
else
    bad "Name/Groesse falsch: $(printf '%s' "$OUT" | jq -c '.ollama_loaded' 2>&1)"
fi
if printf '%s' "$OUT" | jq -e '.ollama_loaded[0].expires_at == "2026-08-16T21:12:00Z"' >/dev/null 2>&1; then
    ok "expires_at (die maschinenlesbare UNTIL-Spalte) wird durchgereicht"
else
    bad "expires_at fehlt oder falsch: $(printf '%s' "$OUT" | jq -c '.ollama_loaded' 2>&1)"
fi

echo
echo "== 5  Wem gehoert Port 11434? Fremd wird nie zu eigen =="
# ANLASS (16.08.2026, gemessen): auf host2 bedient ein ssh-Portforward den Port
# 11434, damit die Scout-Agenten das Embedding-Modell des Macs erreichen.
# `ollama ps` und /api/ps antworten dort also bereitwillig -- nur beschreiben
# sie die GPU einer ANDEREN Maschine. Aufgefallen ist es daran, dass beide
# Maschinen dieselbe Ladung mit demselben expires_at auf die Mikrosekunde
# meldeten. Ohne die Herkunftspruefung haette wb-belegung auf host2 fremde
# Ladungen als lokale Belegung verrechnet: derselbe Fehlertyp wie "unbekannt
# wird zu frei", nur andersherum.
if printf '%s' "$OUT" | jq -e '.ollama_local == true' >/dev/null 2>&1; then
    ok "lauscht ollama selbst, gilt der Port als lokal (ollama_local: true)"
else
    bad "ollama_local haette true sein muessen: $(printf '%s' "$OUT" | jq -c '.ollama_local' 2>&1)"
fi

portbesitzer ssh
# 'ps' steht hier noch auf der Vorgabe von ganz oben (leere Prozessliste) --
# genau der zweite Fall aus dem Auftrag vom 21.08.: fremder Portname UND kein
# lokaler Modell-Laeufer. Das haelt den Portforward-Fall FREMD, auch nachdem
# Abschnitt 6 unten denselben Zweig um die Laeufer-Suche erweitert.
lauf "$STUB:$SYSTEM_PATH"
if printf '%s' "$OUT" | jq -e '.ollama_local == false' >/dev/null 2>&1; then
    ok "lauscht ein ssh-Portforward, ist der Port bestaetigt FREMD (ollama_local: false)"
else
    bad "ollama_local haette false sein muessen: $(printf '%s' "$OUT" | jq -c '.ollama_local' 2>&1)"
fi
if printf '%s' "$OUT" | jq -e '(.ollama_loaded | length) == 1' >/dev/null 2>&1; then
    ok "die Ladung bleibt SICHTBAR -- verschwiegen wird sie nicht, nur nicht mitgezaehlt"
else
    bad "die fremde Ladung wurde verschluckt: $(printf '%s' "$OUT" | jq -c '.ollama_loaded' 2>&1)"
fi
if printf '%s' "$OUT" | jq -e '.ollama_loaded_note | test("ssh")' >/dev/null 2>&1; then
    ok "der Vermerk nennt den Bediener beim Namen, statt nur 'nicht lokal' zu sagen"
else
    bad "ollama_loaded_note nennt den Bediener nicht: $(printf '%s' "$OUT" | jq -c '.ollama_loaded_note' 2>&1)"
fi

# Nicht ermittelbar ist der dritte Fall, und er wird nie stillschweigend zum
# ersten -- dieselbe Haltung wie bei ollama_loaded_note weiter oben.
cat > "$STUB/lsof" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$STUB/ss" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$STUB/lsof" "$STUB/ss"
lauf "$STUB:$SYSTEM_PATH"
if printf '%s' "$OUT" | jq -e '.ollama_local == null' >/dev/null 2>&1; then
    ok "laesst sich der Bediener nicht ermitteln, bleibt es bei null -- nicht bei true"
else
    bad "ollama_local haette null sein muessen: $(printf '%s' "$OUT" | jq -c '.ollama_local' 2>&1)"
fi
if printf '%s' "$OUT" | jq -e '(.ollama_loaded_note | length) > 0' >/dev/null 2>&1; then
    ok "und der Fall wird benannt, statt als 'alles in Ordnung' zu lesen"
else
    bad "kein Vermerk zum unermittelbaren Bediener: $(printf '%s' "$OUT" | jq -c '.ollama_loaded_note' 2>&1)"
fi

echo
echo "== 6  Bedarfsschaltung: fremder Portname, aber ein lokaler Ollama-Laeufer laeuft -> LOKAL (Nachtrag 21.08.2026) =="

# ANLASS (21.08.2026, gemessen auf dieser Maschine): 'wb-modell-proxy' (ein
# Python-Prozess) ist die VORGESEHENE Vordertuer auf :11434 der Bedarfsschaltung
# und heisst nie 'ollama'. Vor diesem Nachtrag fiel das in denselben Zweig wie
# der ssh-Portforward oben -- 'ollama_local' wurde false, obwohl 'ollama ps'
# gleichzeitig echte Ladungen meldete UND echte llama-server-Prozesse aus dem
# ollama-Verzeichnis liefen (gemessen: 6321 MiB RSS). Der Portname allein traegt
# die Entscheidung nicht mehr -- siehe check-resources, ollama_lokale_laeufer_lage.
portbesitzer python
cat > "$STUB/ps" <<'EOF'
#!/bin/sh
echo "/opt/homebrew/Cellar/ollama/0.32.5/libexec/lib/ollama/llama-server --model x --port 59601"
EOF
chmod +x "$STUB/ps"
pruefe_attrappe_greift ps
lauf "$STUB:$SYSTEM_PATH"
if printf '%s' "$OUT" | jq -e '.ollama_local == true' >/dev/null 2>&1; then
    ok "ein fremder Portname mit echtem lokalen Ollama-Laeufer gilt als LOKAL (ollama_local: true)"
else
    bad "ollama_local haette trotz fremdem Portnamen true sein muessen: $(printf '%s' "$OUT" | jq -c '.ollama_local' 2>&1)"
fi
if printf '%s' "$OUT" | jq -e '.ollama_loaded_note | test("python")' >/dev/null 2>&1; then
    ok "der Vermerk nennt weiterhin, wer den Port bedient, obwohl die Ladung lokal zaehlt"
else
    bad "ollama_loaded_note nennt den Portbediener nicht mehr: $(printf '%s' "$OUT" | jq -c '.ollama_loaded_note' 2>&1)"
fi

# Derselbe fremde Portname, aber diesmal ein Laeufer, der NICHT zu ollama
# gehoert (ein fremder llama-server-Stub ohne 'ollama' im Kommando -- genau die
# Kollision, die beim Bau dieser Pruefung live auf dieser Maschine auftrat:
# ein anderer, gleichzeitig laufender Testlauf hatte eigene 'llama-server'-
# Attrappen in fremden Test-HOMEs). Der bleibt FREMD.
cat > "$STUB/ps" <<'EOF'
#!/bin/sh
echo "/bin/bash /var/tmp/irgendein-test-home/bin/llama-server --port 60001"
EOF
chmod +x "$STUB/ps"
pruefe_attrappe_greift ps
lauf "$STUB:$SYSTEM_PATH"
if printf '%s' "$OUT" | jq -e '.ollama_local == false' >/dev/null 2>&1; then
    ok "ein llama-server-Prozess OHNE 'ollama' im Kommando zaehlt nicht als Ollama-Laeufer -- bleibt FREMD"
else
    bad "ein fremder llama-server-Stub wurde faelschlich als Ollama-Laeufer gewertet: $(printf '%s' "$OUT" | jq -c '.ollama_local' 2>&1)"
fi

echo
echo "== 7  Scheitert die Laeufer-Suche selbst, bleibt es UNBEKANNT -- nie stillschweigend lokal oder fremd =="

# Vierter Fall aus dem Auftrag: nichts zu ermitteln -> unbekannt, zaehlt mit
# 0,0 GiB, nie als frei. Hier scheitert nicht der Portbesitzer (der ist
# ermittelt: 'python'), sondern die Laeufer-Suche selbst -- 'ps' liefert
# keinen Exit-Code 0.
cat > "$STUB/ps" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$STUB/ps"
pruefe_attrappe_greift ps
lauf "$STUB:$SYSTEM_PATH"
if printf '%s' "$OUT" | jq -e '.ollama_local == null' >/dev/null 2>&1; then
    ok "scheitert 'ps' selbst, bleibt ollama_local null -- nicht stillschweigend lokal"
else
    bad "eine gescheiterte Laeufer-Suche haette null ergeben muessen: $(printf '%s' "$OUT" | jq -c '.ollama_local' 2>&1)"
fi
if printf '%s' "$OUT" | jq -e '(.ollama_loaded_note | length) > 0' >/dev/null 2>&1; then
    ok "und der Fall wird benannt, statt als 'alles in Ordnung' zu lesen"
else
    bad "kein Vermerk zur gescheiterten Laeufer-Suche: $(printf '%s' "$OUT" | jq -c '.ollama_loaded_note' 2>&1)"
fi

echo
echo "Ergebnis: $pass ok, $fail FAIL"
[ "$fail" -eq 0 ]
