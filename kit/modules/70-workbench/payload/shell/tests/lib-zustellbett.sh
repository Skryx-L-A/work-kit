# lib-zustellbett.sh -- der gemeinsame Aufbau der vier Zustell-Stresstests.
# Zum Sourcen gedacht, wie lib-testwerkzeuge.sh daneben.
#
# ANLASS (2026-08-20, Stresstest der Zustellung). Vier Suiten pruefen denselben
# Weg unter verschiedenen Lasten -- Last, Grenzfaelle, Zeitstempel, Schalter --
# und brauchen dafuer alle denselben Aufbau: ein eigener tmux-Server, ein
# eigenes HOME, eine eigene Registry, ein Orchestrator-Pane und ein
# Stellvertreter als 'claude'. Viermal dieselben sechzig Zeilen waeren viermal
# dieselbe Gelegenheit, die Isolation an einer Stelle falsch abzuschreiben --
# und eine Suite, die versehentlich laufende des Nutzers Sitzung anfasst, ist der
# schlimmste Fehler, den ein Stresstest machen kann.
#
# ISOLATION, an EINER Stelle: eigener tmux-Socket mit PID im Namen, eigenes
# HOME aus mktemp, eigene Registry aus models.default.json, keine Live-Sitzung,
# kein Netz, kein Modell. Der Aufrufer muss dafuer nichts tun ausser
# `zustellbett_start` und `trap zustellbett_ende EXIT`.
#
# Der Aufrufer definiert ok() und bad() (wie in allen Suiten hier) und ruft:
#   zustellbett_start                      Aufbau, setzt TESTHOME/SHIM/MARKE/...
#   zustellbett_ende                       Abbau, prueft dass der Server weg ist
#   zustellbett_panes_weg                  alle Worker-Panes schliessen
#   zustellbett_leeren <verzeichnis>       Inhalt eines Ordners IM Testbett weg
#
# LOESCHEN UND TMUX GEHEN NIE UEBER EINE UNGEPRUEFTE VARIABLE (2026-08-20,
# Beanstandung waehrend genau dieses Auftrags). Ein Aufraeumen laeuft auch dann,
# wenn der AUFBAU vorher gescheitert ist -- und genau dann sind die Variablen
# leer. `rm -rf "$RAWROOT"/*.bin` mit leerem RAWROOT loescht in /roh statt im
# Testbett, und `tmux -L "" kill-server` traefe im schlimmsten Fall einen
# fremden Server. Deshalb gilt hier ohne Ausnahme:
#   * jede Loeschung geht durch zustellbett_leeren() bzw. zustellbett_ende(),
#     und beide brechen bei leerer Variablen ab, statt zu loeschen
#     (${VAR:?...}), und pruefen zusaetzlich, dass der Pfad WIRKLICH unter
#     $TESTHOME oder $SOCKDIR liegt,
#   * jeder tmux-Aufruf geht durch tm(), und tm() fuehrt nichts aus, wenn der
#     Socketname nicht dem Testmuster 'wbtest-*' entspricht.
# Ein Test, der beim Aufraeumen danebengreift, ist schlimmer als der Fehler,
# den er finden soll.
#   zustellbett_claude_inbox <modus> [status] [delay]   'claude' = Sitzung mit Inbox
#   zustellbett_claude_tui   <kind> [busy]              'claude' = Agenten-TUI
#   pi_lauf <auto|socket|paste|-> <name> <task>         ein pi-worker-Lauf
#   worker_pane <name>                     Pane-Kennung eines Workers
#   zustellweg <ausgabe>                   SOCKET | PASTE | FEHLSCHLAG
#   zustellbett_umgebung_pruefen <name...> das echte HOME blieb unberuehrt

unset TMUX TMUX_PANE

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-testwerkzeuge.sh"

# zustellbett_kill_ohne_reste -- wie tm() dieselbe Praefix-Pruefung (SOCKET muss
# 'wbtest-*' heissen), aber statt eines blossen kill-server der reapende Helfer
# aus lib-testwerkzeuge.sh (Auftrag "413 verwaiste Shells", 2026-08-22). Ersetzt
# jedes `tm kill-server`, das wirklich lebende Panes beendet -- nicht die
# Wiederholung in der Warteschleife von zustellbett_ende, die nur noch den
# schon reaptem Server abfragt.
zustellbett_kill_ohne_reste() {
    case "${SOCKET:-}" in
        wbtest-*) : ;;
        *) echo "zustellbett_kill_ohne_reste: '${SOCKET:-<leer>}' ist kein Testsocket (erwartet: wbtest-*) -- nicht ausgefuehrt" >&2
           return 1 ;;
    esac
    tmux_socket_beenden_ohne_reste "$SOCKET"
}

zustellbett_start() {
    ZB_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"        # …/shell
    ZB_TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    FAKE_TUI="$ZB_TESTS/fake-tui.py"
    FAKE_CC="$ZB_TESTS/fake-claude-inbox.py"
    TMUX_REAL="$(command -v tmux 2>/dev/null)"
    SOCKET="wbtest-zustell-$$"
    TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-zustell-test.XXXXXX")" && pwd)"
    SHIM="$TESTHOME/.shim"
    MARKE="z$$$RANDOM"
    ECHTHOME="$HOME"
    # Die Sockets der Stellvertreter liegen NICHT unter $TESTHOME: ein
    # AF_UNIX-Pfad darf auf macOS rund 104 Zeichen lang sein, und ein
    # mktemp-Pfad unter $TMPDIR frisst davon schon die Haelfte (gemessen).
    SOCKDIR="/tmp/wb-zustell-socks-$$"
    RECV="$TESTHOME/empfangen"
    RAWROOT="$TESTHOME/roh"
    export HOME="$TESTHOME"
    export WB_NO_DISCOVER=1
    zustellbett_wie_stellvertreter

    mkdir -p "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/.local/bin" \
             "$TESTHOME/arbeit" "$SOCKDIR" "$RECV" "$RAWROOT"

    cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
    chmod +x "$SHIM/tmux"

    local leer w
    for leer in wb-grid context-guard; do
        printf '#!/bin/sh\nexit 0\n' > "$TESTHOME/.local/bin/$leer"
        chmod +x "$TESTHOME/.local/bin/$leer"
    done
    for w in wb-state wb-mensch wb-rolle wb-harness-run wb-pane-write wb-inbox \
             wb-ereignisse wb-verzeichniswache wb-result; do
        cp "$ZB_REPO/$w" "$TESTHOME/.local/bin/$w" || return 1
        chmod +x "$TESTHOME/.local/bin/$w"
    done
    mkdir -p "$TESTHOME/.claude/hooks/lib"
    cp "$ZB_REPO/../hooks/lib/rollen.py" "$TESTHOME/.claude/hooks/lib/rollen.py" 2>/dev/null || true
    cp "$ZB_REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json" || return 1

    tm -f /dev/null new-session -d -s "wb-$MARKE" -x 200 -y 60 || return 1
    tm set-option -p -t "wb-$MARKE" @wb_role orchestrator
}

# Jeder tmux-Aufruf dieser Suiten. Der Socketname wird VOR dem Ausfuehren
# geprueft: ohne 'wbtest-'-Praefix passiert nichts. Damit kann weder ein
# leeres $SOCKET noch ein versehentlich ueberschriebenes je den umgebenden
# tmux-Server treffen -- auch nicht aus einem Aufraeumen heraus, das nach einem
# gescheiterten Aufbau laeuft.
tm() {
    case "${SOCKET:-}" in
        wbtest-*) : ;;
        *) echo "tm: '${SOCKET:-<leer>}' ist kein Testsocket (erwartet: wbtest-*) -- nicht ausgefuehrt: tmux $*" >&2
           return 1 ;;
    esac
    "${TMUX_REAL:?tm: TMUX_REAL ist leer -- kein tmux-Aufruf}" -L "$SOCKET" "$@"
}

# Liegt dieser Pfad wirklich im Testbett? Beide Wurzeln muessen gesetzt sein --
# bei einer leeren wuerde das Muster "$TESTHOME"/* zu /* und damit auf alles
# passen. ${VAR:?} bricht deshalb ab, statt weiterzumachen.
zustellbett_pfad_pruefen() {   # <pfad>
    local pfad="${1:-}" wurzel
    [ -n "$pfad" ] || { echo "zustellbett: leerer Pfad -- es wird nichts geloescht" >&2; return 1; }
    # Eine LEERE Wurzel deckt nichts ab und wird uebersprungen -- nicht als
    # Muster benutzt. Genau daran haengt alles: "$TESTHOME"/* wuerde bei leerem
    # TESTHOME zu /* und damit auf jeden Pfad der Maschine passen. Ausgelassen
    # statt erzwungen, damit eine halb aufgebaute Umgebung die andere, wirklich
    # gesetzte Wurzel noch aufraeumen kann.
    for wurzel in "${TESTHOME:-}" "${SOCKDIR:-}"; do
        [ -n "$wurzel" ] || continue
        case "$pfad" in
            "$wurzel"|"$wurzel"/*) return 0 ;;
        esac
    done
    echo "zustellbett: '$pfad' liegt unter keiner gesetzten Testwurzel (TESTHOME='${TESTHOME:-<leer>}', SOCKDIR='${SOCKDIR:-<leer>}') -- es wird nichts geloescht" >&2
    return 1
}

# Einen Ordner IM Testbett leeren, ohne Glob im rm-Aufruf. `find … -mindepth 1`
# trifft genau die Kinder dieses einen Ordners; ein Muster wie "$X"/*.bin im
# rm-Aufruf wuerde bei leerem $X dagegen in /*.bin auflaufen.
zustellbett_leeren() {   # <verzeichnis im Testbett>
    local verzeichnis="${1:?zustellbett_leeren: kein Verzeichnis angegeben}"
    zustellbett_pfad_pruefen "$verzeichnis" || return 1
    [ -d "$verzeichnis" ] || return 0
    find "$verzeichnis" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null
}

zustellbett_ende() {
    zustellbett_kill_ohne_reste
    local d=$((SECONDS + 5))
    while [ $SECONDS -lt $d ] && tm list-sessions >/dev/null 2>&1; do
        tm kill-server 2>/dev/null; sleep 0.3
    done
    tm list-sessions >/dev/null 2>&1 \
        && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
    # Die Socketdatei liegt AUSSERHALB des Testbetts, dort greift die
    # Pfadpruefung nicht -- also entscheidet hier der Name: nur ein
    # 'wbtest-'-Socket wird angefasst.
    case "${SOCKET:-}" in
        wbtest-*) rm -f -- "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET" ;;
        *) echo "WARNUNG: Socketname '${SOCKET:-<leer>}' passt nicht zum Testmuster -- Socketdatei nicht geloescht" >&2 ;;
    esac
    local pfad
    for pfad in "${TESTHOME:-}" "${SOCKDIR:-}"; do
        zustellbett_pfad_pruefen "$pfad" || continue
        rm -rf -- "$pfad"
    done
}

zustellbett_panes_weg() {
    local p
    for p in $(tm list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null | awk '$2!=""{print $1}'); do
        tm kill-pane -t "$p" 2>/dev/null
    done
}

# 'claude' ist ab jetzt eine SITZUNG MIT INBOX (fake-claude-inbox.py).
#
# Jede Sitzung bekommt ihren EIGENEN Empfangsordner ($RECV/<pid>). Ein
# gemeinsamer waere ein Messfehler und kein Sparen: jeder Stellvertreter zaehlt
# seine Nachrichten selbst ab 0001, vier gleichzeitige Sitzungen wuerden also
# vier Dateien '0001.txt' schreiben und einander ueberschreiben -- gemessen beim
# ersten Lauf dieser Suite, drei von vier Auftraegen galten als nie angekommen,
# obwohl alle vier zugestellt waren.
# Die Ready-Zeile ist genau '❯' und nichts weiter: das readyPattern des
# claude-Harness ist '❯|░|●', und ein Wort dahinter saehe fuer die
# Eingabezeilen-Pruefung des Tippwegs wie liegengebliebener Text aus.
zustellbett_claude_inbox() {   # <modus> [status] [verzoegerung] [schluck-schalter]
    cat > "$TESTHOME/.local/bin/claude" <<CCEOF
#!/bin/sh
FAKE_CC_SOCK=$SOCKDIR/\$\$.sock \\
FAKE_CC_NAME=fake-\$\$ \\
FAKE_CC_MODE=${1:-normal} \\
FAKE_CC_STATUS=${2:-idle} \\
FAKE_CC_DELAY=${3:-0} \\
FAKE_CC_SCHLUCK=${4:-} \\
FAKE_CC_ALT=${ZB_ALT:-} \\
FAKE_CC_ARBEIT=${ZB_ARBEIT:-0} \\
FAKE_CC_TRANSCRIPT_NACH=${ZB_TRANSCRIPT_NACH:-0} \\
FAKE_CC_RECV=$RECV/\$\$ \\
FAKE_CC_READY='❯' \\
exec /usr/bin/python3 "$FAKE_CC"
CCEOF
    chmod +x "$TESTHOME/.local/bin/claude"
}

# Die drei Eigenschaften, die den Fehlalarm vom 20.08. ausmachen, als Schalter
# fuer die naechste zustellbett_claude_inbox-Sitzung (2026-08-20, zweite Runde):
#   ZB_ALT=1               Alternate Screen -- tmux fuehrt dort keinen Verlauf.
#   ZB_ARBEIT=<n>          n Zeilen Arbeit nach der Anzeige, die den Marker aus
#                          dem sichtbaren Bild schieben.
#   ZB_TRANSCRIPT_NACH=<s> die Gespraechsdatei entsteht erst nach s Sekunden --
#                          der frische Spawn, bei dem sie noch nicht da ist.
zustellbett_wie_claude_code() {   # ohne Argumente: die gemessene Wirklichkeit
    ZB_ALT=1
    ZB_ARBEIT=${1:-60}
    ZB_TRANSCRIPT_NACH=${2:-0}
}
zustellbett_wie_stellvertreter() {   # zurueck auf den einfachen Stellvertreter
    ZB_ALT=""
    ZB_ARBEIT=0
    ZB_TRANSCRIPT_NACH=0
}

# 'claude' ist ab jetzt eine AGENTEN-TUI (fake-tui.py). FAKE_RAW haelt jedes
# gelesene Byte fest -- die einzige Quelle, an der Wortgleichheit pruefbar ist.
zustellbett_claude_tui() {   # <kind> [busy-sekunden]
    cat > "$TESTHOME/.local/bin/claude" <<CCEOF
#!/bin/sh
FAKE_KIND=${1:-korrekt} \\
FAKE_BUSY=${2:-8} \\
FAKE_PROMPT='❯' \\
FAKE_LOG=$TESTHOME/enter.log \\
FAKE_RAW=$RAWROOT/\$\$.bin \\
exec /usr/bin/python3 "$FAKE_TUI"
CCEOF
    chmod +x "$TESTHOME/.local/bin/claude"
}

pi_lauf() {   # <auto|socket|paste|-> <name> <task>
    local weg="$1"; shift
    if [ "$weg" = "-" ]; then
        env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" TMUX= TMUX_PANE= \
            bash "$ZB_REPO/pi-worker" "$1" claude-haiku45 "$TESTHOME/arbeit" "$2" 2>&1
    else
        env WB_ZUSTELLUNG="$weg" HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
            TMUX= TMUX_PANE= \
            bash "$ZB_REPO/pi-worker" "$1" claude-haiku45 "$TESTHOME/arbeit" "$2" 2>&1
    fi
}

worker_pane() {
    tm list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null \
        | awk -v n="$1" '$2==n{print $1; exit}'
}

# Wie viele Nachrichten sind insgesamt angekommen -- ueber alle Sitzungen.
zustellbett_empfang_zahl() {
    find "$RECV" -type f -name '*.txt' 2>/dev/null | wc -l | tr -d ' '
}

# Die n-te empfangene Nachricht. Sinnvoll nur, wo GENAU EINE Sitzung empfaengt
# (die Reihenfolge ist eine Aussage ueber einen Empfaenger, nicht ueber viele).
zustellbett_empfang_datei() {   # <n>
    find "$RECV" -type f -name "$(printf '%04d.txt' "$1")" 2>/dev/null | head -1
}

ergebnisdatei() {
    printf '%s\n' "$1" | sed -n 's/^Ergebnis-Datei: \([^ ]*\).*/\1/p' | tail -1
}

# Welchen Weg hat pi-worker WIRKLICH genommen? Nicht was bestellt war, sondern
# was die Erfolgsmeldung sagt -- das ist der Unterschied, den der Schaltertest
# messen muss.
zustellweg() {
    case "$1" in
        *"Sitzungs-Inbox zugestellt"*) echo SOCKET ;;
        *"Submission verifiziert"*)    echo PASTE ;;
        *)                             echo FEHLSCHLAG ;;
    esac
}

zustellbett_platzhalter() {   # <worker-name> -> "steht" | "weg"
    [ -e "$TESTHOME/.pi-workers/results/$1/.laufend.md" ] && echo steht || echo weg
}

# Die Gegenprobe, die jede Suite hier am Ende zieht: nichts von alldem darf im
# ECHTEN HOME gelandet sein.
zustellbett_umgebung_pruefen() {   # <worker-name...>
    local n uebrig=0
    for n in "$@"; do
        [ -e "$ECHTHOME/.pi-workers/results/$n" ] && uebrig=$((uebrig+1))
    done
    [ "$uebrig" -eq 0 ] \
        && ok "kein Ergebnisordner unter dem echten HOME" \
        || bad "$uebrig Ergebnisordner im ECHTEN ~/.pi-workers -- Testisolation gebrochen"
    if [ -e "$ECHTHOME/.claude/sessions" ] \
       && grep -q "$SOCKDIR" "$ECHTHOME/.claude/sessions"/*.json 2>/dev/null; then
        bad "das ECHTE Sitzungsregister traegt Eintraege der Stellvertreter -- Testisolation gebrochen"
    else
        ok "das echte Sitzungsregister blieb ohne Test-Eintraege"
    fi
}
