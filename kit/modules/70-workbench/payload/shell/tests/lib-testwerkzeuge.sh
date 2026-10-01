# Werkzeuge aus dem Arbeitsbaum in ein Test-HOME legen. Zum Sourcen gedacht.
#
# Warum es das braucht (2026-08-06): Seit der Abschirmung geht jeder Tastendruck durch
# `wb-pane-write`, und dieses Werkzeug erkennt den context-guard daran, dass die
# KANONISCHE Guard-Datei ($HOME/.local/bin/context-guard) in der Ahnenreihe steht --
# verglichen ueber Geraet und Inode. Ein Test mit eigenem HOME hat dort nichts liegen,
# also wuerde der Guard in seinem eigenen Test abgelehnt.
#
# Ein SYMLINK auf die Fassung im Arbeitsbaum loest das, ohne die Pruefung aufzuweichen:
# er zeigt auf DIESELBE Datei, hat also dieselbe Inode. Geprueft wird damit weiterhin
# genau das, was im Betrieb gilt -- nur zeigt der kanonische Pfad hier eben in den
# Arbeitsbaum. Eine Ausnahme fuer Tests gibt es in `wb-pane-write` deshalb nicht, und
# es soll auch keine geben: eine Sicherung mit Testklausel prueft am Ende die Klausel.
# Keine Live-Umgebung (AWB_*/WB_*) in den Test -- siehe lib-testumgebung.sh (27.09.2026).
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testumgebung.sh"

# Agentenmarker des aufrufenden Harness gehoeren nicht in einen isolierten
# Oberflaechentest. Die Herkunftspruefung lehnt absichtlich jeden heutigen und
# kuenftigen CLAUDE_CODE_*/WB_AGENT*-Marker ab; deshalb muss die Abschirmung
# dieselbe Namensregel verwenden statt einer mit jedem neuen Marker veraltenden
# festen Liste.
test_agenten_marker_leeren() {
    local name
    while IFS= read -r name; do
        case "$name" in
            CLAUDECODE|CLAUDE_CODE_*|PI_AGENT|WB_AGENT*) unset "$name" ;;
        esac
    done < <(compgen -e)
}

werkzeuge_installieren() {   # <test-home> [werkzeug...] -- ohne Angabe: die drei noetigen
    local home="${1:?werkzeuge_installieren <test-home> [werkzeug...]}"; shift
    local repo w
    repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    mkdir -p "$home/.local/bin" || return 1
    if [ "$#" -eq 0 ]; then
        set -- wb-pane-write wb-mensch context-guard
    fi
    for w in "$@"; do
        [ -e "$repo/$w" ] || { echo "werkzeuge_installieren: $repo/$w fehlt" >&2; return 1; }
        ln -sf "$repo/$w" "$home/.local/bin/$w" || return 1
    done
}

# mit_test_aufbau <suite-home> <befehl...>
# Fuehrt genau einen Fixture-Aufbau mit der eingeschraenkten Herkunft `aufbau`
# aus. Das eigene Unter-HOME liegt neben dem Demo-Ziel: demo-welt behaelt damit
# seine Sperre gegen Ziele unter HOME, waehrend agents_data den Beleg weiterhin
# unter dem HOME des aufgerufenen Prozesses prueft.
test_aufbau_beleg_anlegen() { # <privates-home> -> Pfad
    local beleg_home="${1:?test_aufbau_beleg_anlegen <privates-home>}"
    mkdir -p "$beleg_home" || return 1
    chmod 0700 "$beleg_home" || return 1
    python3 - "$beleg_home" <<'PY'
import os
import sys
import tempfile

home = os.path.abspath(sys.argv[1])
descriptor, path = tempfile.mkstemp(prefix=".wb-test-aufbau-", dir=home)
try:
    os.fchmod(descriptor, 0o600)
    os.write(descriptor, os.urandom(32))
finally:
    os.close(descriptor)
print(path)
PY
}

mit_test_aufbau() {
    local suite_home="${1:?mit_test_aufbau <suite-home> <befehl...>}"; shift
    [ "$#" -gt 0 ] || { echo "mit_test_aufbau: Befehl fehlt" >&2; return 2; }
    local aufbau_home="$suite_home/.aufbau-home" beleg
    mkdir -p "$aufbau_home" || return 1
    chmod 0700 "$aufbau_home" || return 1
    # Die bewusst menschlichen Demo-Handlungen benutzen weiterhin wb-mensch.
    # Beim umgebogenen HOME muss deshalb derselbe echte Pruefer erreichbar sein;
    # seine Messung wird nicht gepatcht und bleibt unter einem Agenten fail-closed.
    werkzeuge_installieren "$aufbau_home" wb-mensch || return 1
    beleg="$(test_aufbau_beleg_anlegen "$aufbau_home")" || return 1
    HOME="$aufbau_home" WB_TEST_AUFBAU_BELEG="$beleg" "$@"
}

# Auftrag falschrot (2026-08-09): der wöchentliche Gesamtlauf meldete rote
# Suiten, die einzeln grün laufen -- Ursache war kein Code- oder Umgebungsfehler,
# sondern das Wartemuster selbst: eine Deadline lief unter Last ab, die Schleife
# brach STILL ab, und die Zusagen dahinter verglichen gegen eine halbfertige
# oder leere Datei. Aus einem Zeitproblem wurde eine Falschaussage ueber den
# Code. Diese zwei Helfer ersetzen das Muster ueberall: ein abgelaufenes
# Zeitlimit ist ab jetzt sein EIGENER, lauter Fehlschlag (ruft bad() selbst
# auf, mit Wortlaut, wie lange gewartet wurde und was zuletzt in der Ausgabe
# stand) -- nie mehr ein stiller Uebergang zum Lesen von Bruchstuecken.
# Setzt voraus, dass die sourcende Datei bereits ok()/bad() definiert hat.

# warte_auf_datei <erwartete-datei> <sekunden> <beschreibung> [<inhalt-datei>]
# Wartet, bis <erwartete-datei> existiert, hoechstens <sekunden> Sekunden.
# <inhalt-datei> (Default: <erwartete-datei> selbst) liefert bei Zeitlimit die
# letzten Bytes fuer die Meldung -- meist die Ausgabedatei, deren ".done"-
# Marke nicht rechtzeitig erschien.
# Rueckgabe: 0 = Datei da, 1 = Zeitlimit (bad() wurde bereits aufgerufen).
warte_auf_datei() {
    local datei="$1" sekunden="$2" beschreibung="$3" inhaltsdatei="${4:-$1}"
    local start=$SECONDS deadline=$((SECONDS+sekunden))
    until [ -f "$datei" ] || [ $SECONDS -ge $deadline ]; do sleep 0.3; done
    [ -f "$datei" ] && return 0
    local inhalt
    inhalt="$(tail -c 300 "$inhaltsdatei" 2>/dev/null | tr '\n' ' ')"
    bad "ZEITLIMIT: $beschreibung nach $((SECONDS-start))s abgelaufen (Deadline ${sekunden}s)${inhalt:+, zuletzt in der Ausgabe: $inhalt}"
    return 1
}

# warte_auf_bedingung <sekunden> <beschreibung> <bedingung> [<inhalt-datei>]
# Wartet, bis <bedingung> (ein Ausdruck, per eval geprueft -- z.B. ein Test
# wie '[ -s "$WORK/guard.pid" ]' oder 'grep -q MUSTER "$LOG"') wahr wird,
# hoechstens <sekunden> Sekunden. Fuer Wartemuster ohne feste .done-Datei
# (PID-Dateien, Log-Marker, tmux-Zustand).
# Rueckgabe: 0 = Bedingung erfuellt, 1 = Zeitlimit (bad() wurde bereits
# aufgerufen).
warte_auf_bedingung() {
    local sekunden="$1" beschreibung="$2" bedingung="$3" inhaltsdatei="${4:-}"
    local start=$SECONDS deadline=$((SECONDS+sekunden))
    until eval "$bedingung"; do
        if [ $SECONDS -ge $deadline ]; then
            local inhalt=""
            [ -n "$inhaltsdatei" ] && inhalt="$(tail -c 300 "$inhaltsdatei" 2>/dev/null | tr '\n' ' ')"
            bad "ZEITLIMIT: $beschreibung nach $((SECONDS-start))s abgelaufen (Deadline ${sekunden}s)${inhalt:+, zuletzt in der Ausgabe: $inhalt}"
            return 1
        fi
        sleep 0.3
    done
    return 0
}

# tmux_live_hooks_kappen <socket>
# Ein eigener `tmux -L <socket>`-Server ist KEINE Isolationsgrenze: ein frisch
# gestarteter Server laedt trotzdem ~/.tmux.conf, und drei GLOBALE Hooks darin
# rufen per ABSOLUTEM Pfad die echten Werkzeuge der lebenden Maschine auf --
# unabhaengig vom Socket:
#   after-split-window / pane-exited -> echtes $HOME/.local/bin/wb-grid
#   pane-died                        -> echtes $HOME/.local/bin/wb-autorevive
# Gefunden 2026-08-20 (Auftrag dienstprobe) an test-doctor-betriebs-befunde.sh:
# der Test stubt wb-grid sorgfaeltig in seinem eigenen $WORK/.local/bin, um
# wb-doctors EIGENEN --fix-Aufruf abzufangen -- der Hook lief am Stub komplett
# vorbei und startete das ECHTE wb-grid ohnehin, eine Sekunde nach jedem
# `split-window`. Es verschob den Test-Pane wirklich, zwischen zwei Messpunkten
# des Tests, und machte ihn sporadisch rot. Belegt mit einem Kontrollexperiment
# OHNE jede Systemlast (nur `sleep 1.5` nach dem Split, um absichtlich ueber die
# Ein-Sekunden-Verzoegerung hinauszugehen): unrepariert 3/3 rot, repariert 3/3
# gruen -- Ursache und Wirkung sauber getrennt, keine blosse Korrelation mit Last.
#
# Betroffen ist jeder Test, der nach einem `split-window` (oder dem Sterben
# eines Panes) einen Pane- oder Fensterzustand prueft, den wb-grid/wb-autorevive
# beeinflussen koennten -- @wb_role, Fensternamen wie 'workers'/'workers-2',
# Pane-Platzierung, Wiederbelebung. Ein Test, der split-window nur benutzt, um
# irgendeinen zweiten Pane zu erzeugen, ohne das danach zu pruefen, braucht den
# Aufruf nicht zwingend, nimmt aber keinen Schaden davon.
#
# Bewusst NICHT `-f /dev/null` (die ganze Konfiguration verwerfen): ~/.tmux.conf
# setzt u.a. `base-index 1`, `pane-base-index 1`, `renumber-windows on`,
# `exit-empty off` -- Annahmen, auf die sich ein Test stillschweigend verlassen
# koennte. Das gezielte `set-hook -gu` trifft nur die drei Leitungen zur
# lebenden Maschine und laesst den Rest der Konfiguration unangetastet. Wirkt
# ausschliesslich auf dem hier genannten Socket -- eine echte, laufende Sitzung
# der Maschine benutzt ihn nie und bleibt unberuehrt.
tmux_live_hooks_kappen() {
    local socket="${1:?tmux_live_hooks_kappen <socket>}"
    tmux -L "$socket" set-hook -gu after-split-window 2>/dev/null
    tmux -L "$socket" set-hook -gu pane-exited 2>/dev/null
    tmux -L "$socket" set-hook -gu pane-died 2>/dev/null
}

# tmux_socket_beenden_ohne_reste <socket> [tmux-vorargument...]
# Ersetzt das blosse `tmux -L <socket> kill-server 2>/dev/null` am Ende jeder
# Suite: das allein laesst PANES manchmal zurueck, weil das SIGHUP, das der
# Server beim Sterben an seine Panes schickt, sie nicht immer noch erreicht,
# BEVOR der Server selbst schon weg ist -- ein Rennen zwischen dem Sterben des
# Servers und der (asynchronen) Zustellung des Hangup, keine Ausnahme.
# Gemessen (eigener tmux-Testsocket, zehn Panes, `kill-server` sofort danach):
# 0, 4, 4, 6, 0 Ueberlebende in fuenf Laeufen, in zwei davon auch noch nach
# drei Sekunden -- also nicht bloss ein kurzes Aufholen. Anlass: 413 solcher
# Shells hielten 430 von 511 PTYs (kern.tty.ptmx_max) nach einer Nacht mit
# mehreren Volllaeufen (Auftrag "413 verwaiste Shells, und ein Waechter, der
# sie nicht sah", 2026-08-22) -- unbemerkt, weil keine Suite ihre eigenen
# Panes je gegenpruefte.
#
# Die Abhilfe: die Panes VOR dem kill-server einsammeln, danach kurz nachsehen
# und jeden, der den Server ueberlebt hat, DIREKT beenden -- nicht auf das
# SIGHUP verlassen, das schon einmal ausgeblieben ist. Reine Ersetzung fuer
# `tmux -L <socket> kill-server 2>/dev/null` in cleanup(); ein Server, der
# danach (z.B. durch einen wartenden Client) neu hochkommt, ist ein
# ANDERES, bereits geloestes Problem (siehe "HARTNAECKIG AUFRAEUMEN,
# Befund 21.08." in test-app-startweg.sh/test-wb-nohup-eigentuemer.sh) und
# bleibt Sache der jeweiligen Suite, falls sie das betrifft.
#
# NICHT NUR DIE PANE-LISTE, SONDERN DIE KINDER DES SERVERS (2026-08-24,
# Auftrag "was bei zwanzig gleichzeitig passiert"). Die Pane-Liste ist die
# BUCHFUEHRUNG von tmux, und die kennt nicht jede Shell, die noch lebt: wer
# mitten im Test ein `kill-session` oder `kill-window` absetzt, dessen
# Pane-Shell kann dasselbe SIGHUP-Rennen ueberleben -- sie verliert dann ihren
# Eintrag bei tmux, bleibt aber ein KIND DES SERVERPROZESSES und haelt ihr
# Pseudoterminal. Am Ende sah `list-panes -a` sie nicht mehr, der kill-server
# nahm ihr den Vater, und sie stand als verwaiste Login-Shell da. Gemessen an
# einem vollen Lauf mit 20 gleichzeitigen Suiten (23.08., Spur an genau dieser
# Funktion): Socket wbtest-session-close-10589 meldete
# `list-panes -a` = 23449 23449 10608 10608 18920 10622, der Serverprozess
# hatte aber sieben Kinder (10608 10622 12136 18920 19459 19764 23449) -- und
# genau die drei, die in keiner Pane-Zeile standen (12136 19459 19764), waren
# hinterher die Waisen. Deshalb wird jetzt die VEREINIGUNG beider Mengen
# beendet.
#
# UND SIE SCHWEIGT NICHT MEHR, WENN ES NICHT KLAPPT. Bis zum 24.08. war jeder
# Ausgang derselbe: die Funktion kam zurueck, ob sie aufgeraeumt hatte oder
# nicht. Wer nach dem Lauf Waisen fand, konnte nicht sehen, welche Suite sie
# hinterlassen hat. Ein Rest nach `kill -9` ist ab jetzt eine Zeile auf
# stderr, mit Socket und PIDs -- sie landet in der Ausgabe der Suite und damit
# im aufgehobenen Protokoll des roten Laufs.
#
# Die Vorargumente (z.B. `-f /dev/null`) reisen mit, damit auch die Suiten
# diese Funktion benutzen koennen, die ihren Socket mit eigenem TMUX_TMPDIR
# und ohne Konfiguration fahren -- sie hatten dieselbe Schleife bis dahin von
# Hand nachgebaut, mitsamt derselben Luecke.
tmux_socket_beenden_ohne_reste() {
    local socket="${1:?tmux_socket_beenden_ohne_reste <socket> [tmux-vorargument...]}"; shift
    # Kein leerer und kein voreingestellter Socket: diese Funktion beendet
    # Prozesse, und ein Fehlgriff traefe die lebende Sitzung der Maschine.
    case "$socket" in ''|default) echo "tmux_socket_beenden_ohne_reste: '$socket' ist kein Testsocket" >&2; return 2 ;; esac
    local panes p rest deadline srv kinder alle uebrig
    panes="$(tmux -L "$socket" "$@" list-panes -a -F '#{pane_pid}' 2>/dev/null)"
    # Die Kinder des Serverprozesses -- die zweite, groessere Menge. Der Server
    # ist der tmux-Prozess mit `-L <socket>` in der Befehlszeile, dessen Vater
    # der init-Prozess ist; kurzlebige Clients haben einen anderen Vater und
    # fallen damit heraus.
    srv="$(ps -eo pid=,ppid=,command= 2>/dev/null \
        | awk -v s="$socket" '$2==1 && ($3=="tmux" || $3 ~ /\/tmux$/) { for (i=4;i<NF;i++) if ($i=="-L" && $(i+1)==s) { print $1; break } }')"
    kinder=""
    for p in $srv; do kinder="$kinder $(pgrep -P "$p" 2>/dev/null | tr '\n' ' ')"; done
    tmux -L "$socket" "$@" kill-server 2>/dev/null
    # Vereinigung ohne Doppelte -- dieselbe PID steht in der Pane-Liste einmal
    # je Sitzung, in der ihr Fenster haengt.
    alle="$(printf '%s\n%s\n' "$panes" "$kinder" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ')"
    [ -n "${alle// /}" ] || return 0
    panes="$alle"
    deadline=$((SECONDS + 2))
    while [ $SECONDS -lt $deadline ]; do
        rest=""
        for p in $panes; do
            ps -o pid= -p "$p" >/dev/null 2>&1 && rest="$rest $p"
        done
        [ -z "$rest" ] && return 0
        panes="$rest"
        sleep 0.2
    done
    for p in $panes; do
        ps -o pid= -p "$p" >/dev/null 2>&1 && kill "$p" 2>/dev/null
    done
    sleep 0.3
    for p in $panes; do
        ps -o pid= -p "$p" >/dev/null 2>&1 && kill -9 "$p" 2>/dev/null
    done
    sleep 0.3
    uebrig=""
    for p in $panes; do
        ps -o pid= -p "$p" >/dev/null 2>&1 && uebrig="$uebrig $p"
    done
    if [ -n "${uebrig// /}" ]; then
        echo "WARNUNG: auf Socket '$socket' ueberlebte(n) auch kill -9:$uebrig" >&2
        return 1
    fi
    return 0
}

# prozessbaum <pid>
# Der GANZE Nachkommenbaum von <pid>, nicht nur seine direkten Kinder
# (Pruefer-Befund 6, 04.09.2026). Electron haengt seine Helfer (GPU-,
# Renderer-, Utility-Prozess) unter den HAUPTPROZESS, nicht unter das
# startende `node .../electron` -- sie sind also ENKEL der PID, nicht Kinder,
# und `pgrep -P <pid>` allein sieht nur die erste Ebene. Genau das liess beim
# Pruefer ein verwaistes `electron --headless` mit neun Kindern zurueck: die
# eine Ebene, die die alte Pruefung erreichte, war die des Wrappers, nicht
# die der Helfer darunter. Bis 2026-09-04 stand diese Funktion wortgleich in
# `test-app-flaeche.sh` (Commit 2028fde) sowie -- unrepariert, als blosses
# `pgrep -P $APPPID` -- in ueber fuenfzig weiteren `test-app-*.sh`-Suiten;
# `app_electron_beenden` unten ist der geteilte Nachfolger fuer alle.
prozessbaum() {
    local wurzel="$1" queue="$1" gefunden="" kinder k
    while [ -n "$queue" ]; do
        kinder="$(pgrep -P "$(printf '%s' "$queue" | tr ' ' ',')" 2>/dev/null | tr "\n" " ")"
        queue=""
        for k in $kinder; do
            case " $gefunden " in
                *" $k "*) ;;
                *) gefunden="$gefunden $k"; queue="$queue $k" ;;
            esac
        done
    done
    printf '%s' "$gefunden"
}

# app_electron_beenden <pid-oder-pid-datei> [gnadenfrist_sekunden]
# Die App-Haelfte der `app_beenden`-Kopie, die bis zum 04.09.2026 wortgleich
# in ueber fuenfzig `test-app-*.sh`-Suiten stand (Pruefer-Befund 6, siehe
# test-app-flaeche.sh vor Commit 2028fde): ein einzelner Schnappschuss ueber
# `pgrep -P $APPPID`, VOR dem Signal genommen. Stirbt Electron innerhalb der
# Gnadenfrist, haengt macOS seine Kinder SOFORT auf launchd (PID 1) um --
# ein Schnappschuss von DANACH findet sie ueber die alte Elternschaft nicht
# mehr, obwohl die PID selbst gueltig bleibt und sich direkt beenden laesst.
# Zwei Schnappschuesse des ganzen Baums (`prozessbaum`, s.o.) beheben das:
# einer vor dem Signal, einer nach der Gnadenfrist -- ihre Vereinigung wird
# am Ende gezielt beendet.
#
# Das erste Argument ist entweder die PID direkt oder der Pfad zu einer
# Datei, die sie enthaelt (fuer Suiten, die ihre Electron-PID in einer Datei
# statt in einer Shell-Variable halten).
app_electron_beenden() {
    local ziel="${1-}" frist="${2:-8}" pid
    case "$ziel" in
        '') return 0 ;;
        *[!0-9]*) pid="$(cat "$ziel" 2>/dev/null)" ;;
        *) pid="$ziel" ;;
    esac
    case "$pid" in ''|*[!0-9]*) return 0 ;; esac
    local baum1 baum2 alle
    baum1="$(prozessbaum "$pid")"
    kill "$pid" 2>/dev/null
    local deadline=$((SECONDS + frist))
    while [ $SECONDS -lt $deadline ] && kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
    baum2="$(prozessbaum "$pid")"
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    alle="$(printf '%s\n%s\n' "$baum1" "$baum2" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ')"
    if [ -n "${alle// /}" ]; then
        kill $alle 2>/dev/null
        sleep 0.5
        kill -9 $alle 2>/dev/null
    fi
}

# tmux_socket_restlos_beenden <socket> [tmux-vorargument...]
# Die Cleanup-Haelfte derselben Kopie: bis zum 04.09.2026 pruefte jede Suite
# nur `tmux -L <socket> list-sessions` und loeschte danach unbedingt die
# Socketdatei (Pruefer-Befund 6). Unter Last verweigert der Server neue
# Verbindungen oft, bevor sein eigener Prozess wirklich beendet ist --
# `list-sessions` meldete dann faelschlich "weg", die Schleife endete
# zufrieden, und das anschliessende `rm -f` schnitt den noch laufenden
# Server endgueltig von seinem eigenen Socketpfad ab, ohne ihn zu beenden.
# Ruft zuerst `tmux_socket_beenden_ohne_reste` fuer Panes und Server-Kinder
# auf, prueft den Serverprozess danach ueber seine PID statt ueber
# Erreichbarkeit, und schlaegt zuletzt ueber den PID-tragenden Socketnamen in
# der Befehlszeile jedes Prozesses nach -- unabhaengig von Abstammung, damit
# auch ein Kontrollclient der Anwendung gefunden wird (`tmux -C
# attach-session`), der beim Sterben seines Elternprozesses schon auf
# launchd umgehaengt sein kann und ueber `pgrep -P` nicht mehr auffindbar
# ist. Loescht am Ende die Socketdatei unter beiden bekannten Pfaden.
#
# Vorargumente (z.B. `-f /dev/null`) reisen wie bei
# `tmux_socket_beenden_ohne_reste` mit durch, fuer Suiten mit eigenem
# TMUX_TMPDIR und ohne geladene Konfiguration.
tmux_socket_restlos_beenden() {
    local socket="${1:?tmux_socket_restlos_beenden <socket> [tmux-vorargument...]}"; shift
    case "$socket" in
        ''|default) echo "tmux_socket_restlos_beenden: '$socket' ist kein Testsocket" >&2; return 2 ;;
    esac
    tmux_socket_beenden_ohne_reste "$socket" "$@"
    local srv deadline
    srv="$(ps -eo pid=,ppid=,command= 2>/dev/null \
        | awk -v s="$socket" '$2==1 && ($3=="tmux" || $3 ~ /\/tmux$/) { for (i=4;i<NF;i++) if ($i=="-L" && $(i+1)==s) { print $1; break } }')"
    deadline=$((SECONDS + 5))
    while [ -n "$srv" ] && [ $SECONDS -lt $deadline ] && kill -0 "$srv" 2>/dev/null; do
        tmux -L "$socket" "$@" kill-server 2>/dev/null
        kill "$srv" 2>/dev/null
        sleep 0.3
    done
    if [ -n "$srv" ] && kill -0 "$srv" 2>/dev/null; then
        kill -9 "$srv" 2>/dev/null
        sleep 0.3
        kill -0 "$srv" 2>/dev/null \
            && echo "WARNUNG: tmux-Server (PID $srv) auf Socket '$socket' laeuft noch, auch nach kill -9" >&2
    fi
    local reste
    reste="$(ps -eo pid=,command= 2>/dev/null | awk -v s="$socket" '{
        for (i=1;i<=NF;i++) if ($i=="-L" && $(i+1)==s) { print $1; break }
    }')"
    if [ -n "$reste" ]; then
        kill $reste 2>/dev/null
        sleep 0.3
        kill -9 $reste 2>/dev/null
    fi
    rm -f "/private/tmp/tmux-$(id -u)/$socket" "/tmp/tmux-$(id -u)/$socket"
}

# Das Mac-Buendel ist veraltet, wenn eine Quelle unter mac/Sources oder mac/Package.swift
# juenger ist als das Binary (Befund 14.09.2026: nach einem Merge lief die Suite gegen ein
# Binary von 12:52 bei Quellen von 14:22 und meldete sechs falsche Fehler). Ohne Quellordner
# gilt das Buendel als aktuell, damit ein Checkout ohne mac/ nicht baut.
mac_buendel_veraltet() {   # $1 = Binary, $2 = mac-Ordner; Exit 0 = veraltet
  local binary="$1" mac="$2"
  [ -x "$binary" ] || return 0
  [ -d "$mac/Sources" ] || return 1
  [ -n "$(find "$mac/Sources" "$mac/Package.swift" -newer "$binary" -type f 2>/dev/null | head -1)" ]
}

# awb-ctl mit derselben Umgebung rufen, mit der der Kern gestartet wurde.
#
# ANLASS (21.09.2026, Gesamtlauf auf b7630ff4): sieben App-Suiten starteten den
# Kern mit eigenem AWB_STATE_DIR -- seit 262fc545 haengt sein Vorgabe-Socket an
# diesem Verzeichnis --, riefen `awb-ctl` aber ohne. Der Client rechnete den
# Pfad ohne Zustandsverzeichnis, fand nichts ("connect ENOENT") und meldete
# danach nur noch "<unlesbar>". Vor dem Fix passten beide Rechnungen zufaellig
# zusammen, weil keine von beiden das Verzeichnis kannte.
#
# Diese Hilfe gibt es, damit die achte Suite es nicht wieder vergisst: sie
# reicht Zustandsverzeichnis, HOME und XDG_RUNTIME_DIR geschlossen weiter. Der
# Socketpfad selbst wird NICHT hier gerechnet -- awb-ctl und der Kern leiten ihn
# aus derselben Formel ab, und test-app-socket-isolation.sh Punkt 2b fuehrt
# beide Ableitungen aus und vergleicht sie.
#
#   ctl_aufruf <test-home> <state-dir> <app-verzeichnis> [argument...]
ctl_aufruf() {
  local home="$1" statedir="$2" app="$3"
  shift 3
  env HOME="$home" XDG_RUNTIME_DIR="$home" AWB_STATE_DIR="$statedir" \
    node "$app/bin/awb-ctl" "$@" 2>&1
}
