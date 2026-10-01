# lib-parallel-sicher.sh -- die Isolations-Pruefung fuer den Parallel-Pool von
# run-all.sh, ausgelagert zum Sourcen (Auftrag 2026-08-22).
#
# Auftrag 2026-08-19 (Ursprung dieser Pruefung): "Pruef das je Suite nach,
# statt es anzunehmen." Diese Funktion laeuft bei JEDEM Aufruf gegen den
# AKTUELLEN Quelltext jeder Suite -- kein einmaliger, veraltender Handaudit,
# sondern eine Pruefung, die mit der Suite mitgeht, wenn sie sich aendert.
#
# GESCHAERFT 2026-08-22, nach einem Vorfall vom 21.08.: wb-notbremse hat den
# Modellserver einer Nachbarsuite erschossen, obwohl beide Suiten diese
# Pruefung (damals nur die $HOME-Achse) bestanden hatten. Der Eingriff ging
# ueber den eigenen Prozessbaum hinaus -- eine Achse, die die reine
# $HOME-Pruefung nicht kennt: eine Suite kann $HOME sauber umlenken und
# trotzdem, ueber pkill/killall oder ein Werkzeug wie wb-notbremse, in die
# Prozessliste der GANZEN Maschine greifen.
#
# WARUM NUR DIESE ZWEI ACHSEN DAZUKOMMEN UND NICHT MEHR: beim Nachsehen
# standen fuenf moegliche Achsen zur Wahl (Auftrag, siehe dortige Liste).
# Gemessen gegen den echten Suiten-Bestand (2026-08-22) hielten nur zwei einer
# ehrlichen Textpruefung stand -- die anderen drei waeren entweder blind fuer
# den echten Fall oder haetten saubere Suiten faelschlich eingesammelt. Die
# Begruendung je Achse steht unten bei der jeweiligen Funktion; der volle
# Befund steht im Ergebnisbericht dieses Auftrags.

# --- Ausschlussregel (Basis), in dieser Reihenfolge:
#   1. Name auf der Verbotsliste -- feste Ausnahmen, siehe unten.
#   2. Kein $HOME-/~/.claude-/~/.local-/~/work/brain-Bezug im Quelltext -- dann
#      gibt es nichts Gemeinsames, das zwei gleichzeitige Laeufe stoeren
#      koennten (die meisten test-app-*.sh: reine Umformung von Daten, kein
#      Home, kein tmux, kein Netz).
#   3. Eine `HOME=`-Zuweisung im Quelltext (egal ob `export HOME=`, ein
#      Praefix `HOME="$X" tool ...` oder eine Variable, die spaeter per
#      `mktemp -d` gefuellt wird) -- das ist das Isolations-Muster, das jede
#      geprueft-sichere Suite in diesem Repo traegt (Kopfkommentare: "eigenes
#      HOME, eigener tmux-Socket").
#   4. Name auf der Lese-Erlaubnisliste -- Suiten, die den echten $HOME oder
#      den Live-tmux-Server anfassen, aber NUR LESEND (per Hand geprueft, mit
#      Fundstelle, siehe die Kommentare an den Listen unten).
# Trifft nichts davon zu: sicherheitshalber NICHT parallel -- eine unbekannte,
# ungeprüfte Suite bekommt keinen Vertrauensvorschuss.
#
# Was das bei diesem Audit (2026-08-19) NICHT erwischt hat, weil es keine
# Isolation braucht: der tmux-Achse nimmt sich zusaetzlich `shell/wb-consistency`
# Check 8 an (TEST-LIVE-SOCKET/TEST-SOCKET-OFFEN, laeuft bei jedem Lauf als
# eigene Stufe unten) -- diese Funktion deckt nur die $HOME-Achse ab, die Check 8
# nicht prueft.
NICHT_PARALLEL_NAMEN=" test-contradiction-queue.sh test-knopf-tastendruck.py test-app-welten.sh "
# test-contradiction-queue.sh: schreibt bei echtem Ollama in ECHTES
#   $HOME/.local/bin/brain, $HOME/.local/state/brain-maintain.log und den
#   echten Kbase unter $HOME/work/brain -- kein mktemp-HOME irgendwo im Skript.
# test-knopf-tastendruck.py: haengt sich per pty an den EINEN angehefteten
#   tmux-Client (siehe skip_reason_for oben) -- ein gemeinsam genutzter Client
#   lässt sich nicht sinnvoll parallelisieren, unabhaengig vom Ergebnis.
# test-app-welten.sh: haelt einen Electron-Prozess aus app/dist am Leben und
#   fuehrt selbst einen Build aus. Ein paralleler App-Build kann genau diesen
#   gemeinsam gelesenen dist-Baum waehrend Punkt 14/15 austauschen.

LESEND_LIVE_ALLOWLIST=" test-context-guard-live-socket-unberuehrt.sh test-wb-budget-echte-quellen.sh test-belegung-spiegel.sh "
# test-context-guard-live-socket-unberuehrt.sh: ruft auf dem Live-Socket
#   ausschliesslich list-sessions/list-panes/capture-pane (Zeilen 99f, 115f
#   dieser Datei) -- nie send-keys/kill/set/new-session. Beweist per Kennzeichen
#   und PID-Abgleich, dass sie selbst nichts anfasst; siehe ihr eigener
#   Kopfkommentar.
# test-wb-budget-echte-quellen.sh: liest reale Pfade unter $HOME (ls, find,
#   grep) gegen `wb-budget --json` -- keine einzige Schreiboperation im
#   Quelltext.
# test-belegung-spiegel.sh: liest nur $HOME/.local/bin/wb-belegung (diff -q
#   gegen den Worktree) -- keine einzige Schreiboperation im Quelltext, genau
#   der Pfad, den wb-kontext fest verdrahtet aufruft.

# --- Achse 1: pkill/killall auf ein UNGEBUNDENES Muster ---------------------
# pkill/killall wirken IMMER ueber die Prozessliste der ganzen Maschine, nie
# nur ueber den eigenen Baum -- das unterscheidet sie grundsaetzlich von
# `kill $EIGENE_PID`. Das macht sie nicht per se verboten: eine echte Suite in
# diesem Bestand bindet ihr Muster an etwas, das nur DIESEM Lauf gehoert (der
# eigene Socket-Name, der eigene mktemp-Pfad, `-P $EIGENE_PID` fuer den
# Eltern-Riegel) -- geprueft an den sieben echten Aufrufen im Bestand vom
# 2026-08-22, alle sieben binden so. Ein Aufruf OHNE jede Variable im Muster
# (ein woertlicher Name wie `pkill -f ollama`) trifft dagegen jeden Prozess
# mit diesem Namen auf der ganzen Maschine, unabhaengig vom eigenen Lauf --
# das ist die Form, die den Vorfall vom 21.08. ausgemacht haette.
#
# Bewusst nur der ERSTE Befehlston der Zeile (Kommentare vorher entfernt):
# eine Suite kann "pkill" auch als reinen TEXT fuehren (ein Beispiel-Logeintrag
# als Testdaten, siehe test-ereignisse.sh: `"command":"pkill x"` mitten in
# einer JSON-Zeile) -- das ist kein Aufruf, und eine Pruefung, die das
# trotzdem als Fund zaehlt, waere die Art blinder Treffer, vor der der Auftrag
# ausdruecklich warnt. Ein `kill` ohne pkill/killall bleibt hier aussen vor:
# `kill $VAR` auf eine Variable ist im ganzen Bestand die uebliche, akzeptierte
# Form fuer die eigene, selbst gestartete PID (Beispiel aus dem Auftrag selbst:
# "kill -9 $APPPID ... ist sauber") -- ob die Variable wirklich selbst
# gestartet wurde, laesst sich ohne Datenfluss-Verfolgung nicht ehrlich pruefen,
# und genau das zu behaupten waere die Art Pruefung, die nur so tut.
pkill_ungebunden_gefunden() {
    local pfad="$1"
    grep -vE '^[[:space:]]*#' "$pfad" \
        | grep -E '^[[:space:]]*(pkill|killall)\b' \
        | grep -qvF '$'
}

# --- Achse 2: wb-notbremse ohne den eigenen Zaun -----------------------------
# Genau der Notbremsen-Fall vom 21.08.: wb-notbremse beendet per Bauart ueber
# die Prozessliste der GANZEN Maschine (siehe dessen eigener Kopfkommentar,
# Abschnitt "DER ZAUN") -- kein Muster in dieser Datei kann das auf den
# eigenen Baum eingrenzen, weil das Werkzeug selbst gar nicht nach einem Baum
# fragt, sondern nach der Kommandozeile. Der einzige bekannte Weg, es fuer
# einen Testlauf einzugrenzen, ist sein EIGENER Zaun (`WB_NOTBREMSE_NUR_MUSTER`,
# vom Werkzeug selbst angeboten) -- fehlt der, gilt die Suite als unsicher.
#
# Bewusst NAMENTLICH, nicht als allgemeine "ruft irgendein Werkzeug, das
# irgendwo toetet"-Regel: eine solche allgemeine Regel liesse sich nicht
# ehrlich pruefen (siehe wb-inbox unten, verworfen), waehrend dieser eine
# Name bekannt und sein Zaun-Mechanismus dokumentiert ist. Neue Werkzeuge mit
# derselben Reichweite gehoeren hier als eigene Zeile dazu, sobald sie
# bekannt sind -- nicht vorab erraten.
#
# NUR EIN AUFRUF ZAEHLT, NICHT DAS WORT (03.09.2026). Bis dahin genuegte das
# Vorkommen von `wb-notbremse` irgendwo in einer nicht auskommentierten Zeile.
# `test-belegung.sh` nennt das Werkzeug seit dem 27.08. in einem MELDETEXT --
# `ok "... wb-notbremse ist der Ersatz"` -- und fiel dadurch aus dem
# Parallel-Pool, obwohl es die Notbremse nie aufruft; im vollen Lauf war das
# eine rote Suite (`test-parallel-sicher-achsen.sh`, Punkt 4). Gesucht wird
# deshalb dieselbe Form wie bei pkill: der erste Befehlston einer Zeile,
# gegebenenfalls hinter einer Umgebung (`env`), einem Praefix wie
# `sudo`/`timeout` oder einem Pfad -- ODER die ZUWEISUNG eines Pfades, der auf
# das Werkzeug zeigt (`TOOL="$REPO/wb-notbremse"`), denn genau so rufen die
# Suiten es im Bestand auf. Ein Name in einer Zeichenkette ist dagegen kein
# Aufruf, und eine Pruefung, die das trotzdem zaehlt, ist der blinde Treffer,
# vor dem der Kopf dieser Datei warnt.
#
# ERWEITERT 03.09.2026 (Nachlese, Pruefer-Befund 2): vier gaengige Aufrufformen
# fielen durch den ersten Ausdruck. `if wb-notbremse ...`, `then wb-notbremse
# ...` und `do wb-notbremse ...` beginnen mit einem Schluesselwort der Shell
# selbst, nicht mit `env`/`sudo`/`timeout`/`exec` -- der alte Ausdruck kannte
# nur die vier Umgebungs-Praefixe. `xargs wb-notbremse` ist derselbe Fall:
# `xargs` startet den Aufruf genauso wie `env`, nur als eigenes Werkzeug statt
# als Umgebung. Und ein Aufruf in Rueckwaertsapostrophen (`` `wb-notbremse
# ...` ``) begann fuer den alten Ausdruck mit einem Zeichen, das keine der
# bekannten Grenzen (`;&|(`, Zeilenanfang, `&&`/`||`) war. Alle vier Faelle
# sind echte Aufrufe, keine blossen Erwaehnungen -- Fall 1e in
# test-parallel-sicher-achsen.sh haelt sie fest.
notbremse_ohne_zaun_gefunden() {
    local pfad="$1"
    grep -vE '^[[:space:]]*#' "$pfad" \
        | grep -qE '(^|[;&|(`]|&&|\|\|)[[:space:]]*"?[A-Za-z0-9_/.$-]*wb-notbremse\b|(^|[;&|(`]|&&|\|\||[[:space:]])[[:space:]]*(env|sudo|timeout|exec|if|then|do|xargs)[[:space:]]+"?[A-Za-z0-9_/.$-]*wb-notbremse\b|^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*wb-notbremse\b' \
        || return 1
    grep -q 'WB_NOTBREMSE_NUR_MUSTER' "$pfad" && return 1
    return 0
}

# --- Achse 3: bekannte, suiten-uebergreifende Umgebungsvariablen ------------
# Eine Handvoll Namen, von denen bekannt ist, dass sie Identitaet ueber einen
# Lauf hinaus tragen (WB_EIGENTUEMER_WERKBANK: der bekannte Fall aus dem
# Auftrag) -- eine Suite, die eine ECHTE, unveraenderte Erweiterung dieser
# Variable liest (kein Backslash davor -- der stuende fuer ein Heredoc-Literal,
# das erst SPAETER in einem eigenen, isolierten Kindprozess gilt, siehe
# test-app-mensch-sitzungsstart.sh), ohne sie im selben Quelltext entweder
# selbst zu setzen (`VAR=...`) oder auszuschliessen (`env -u VAR`), erbt den
# Wert eines Nachbarlaufs. Bewusst eine kurze, benannte Liste statt eines
# Musters ueber "sieht aus wie eine Umgebungsvariable": welche Variablen
# lauf-uebergreifende Identitaet tragen, ist Wissen ueber DIESES Repo, keine
# Textform, die sich generisch erkennen liesse.
BEKANNTE_LAUFUEBERGREIFENDE_VARS="WB_EIGENTUEMER_WERKBANK"

env_var_ungebunden_gefunden() {
    local pfad="$1" var
    for var in $BEKANNTE_LAUFUEBERGREIFENDE_VARS; do
        grep -vE '^[[:space:]]*#' "$pfad" \
            | grep -qE "(^|[^\\\\])\\\$\\{?${var}\\b" || continue
        grep -qE "(^|[^A-Za-z_])${var}=" "$pfad" && continue
        grep -qE -- "-u[[:space:]]+${var}\\b" "$pfad" && continue
        return 0
    done
    return 1
}

# --- Was NICHT dazukam, und warum (2026-08-22) ------------------------------
# * tmux-Server ohne eigenen Socket: im Bestand traegt "tmux" oft NUR eine
#   Kopfzeile ("kein tmux" als Prosa, siehe test-app-chat.sh) oder eine echte
#   Isolation OHNE das Wort "-L" im Text (ein per PATH vorgeschalteter
#   Tmux-Stellvertreter, siehe test-session-delete.sh: `cat > "$BIN/tmux"`).
#   Eine Pruefung "kein -L im Text -> unsicher" haette rund 20 tatsaechlich
#   saubere Suiten faelschlich eingesammelt, gemessen am selben Bestand.
# * wb-inbox ohne WB_TMUX_SOCKET: die eigentliche Zustellung laeuft bei den
#   meisten Aufrufern nicht direkt, sondern durch `pi_lauf`/pi-worker als
#   eigenen Prozess (siehe lib-zustellbett.sh) -- eine Pruefung des
#   Suiten-Quelltexts sieht dort nicht, was pi-worker intern setzt, und haette
#   test-zustellung-grenzfaelle.sh und test-zustellung-last.sh faelschlich
#   eingesammelt, obwohl beide sauber sind. Das eigentliche Sicherheitsnetz
#   liegt bereits im Werkzeug selbst (WB_TMUX_SOCKET + Ahnenreihen-Pruefung +
#   `--pid`-Riegel, siehe shell/wb-inbox, Stand 2026-08-20).
# * feste Ports/Socket-Pfade: keine ehrliche Unterscheidung zwischen einer
#   bereits isolierten Portnummer und einer geteilten ohne eine gepflegte
#   Liste bekannter Produktionsports -- und ohne einen belegten Vorfall, an
#   dem sich eine solche Pruefung ueberhaupt messen liesse.

ist_parallel_sicher() {
    local pfad="$1" name
    name="$(basename "$pfad")"
    case "$NICHT_PARALLEL_NAMEN" in *" $name "*) return 1 ;; esac
    pkill_ungebunden_gefunden "$pfad" && return 1
    notbremse_ohne_zaun_gefunden "$pfad" && return 1
    env_var_ungebunden_gefunden "$pfad" && return 1
    grep -qE '\$HOME|~/\.claude|~/\.local|~/work/brain' "$pfad" || return 0
    grep -qE '(^|[^A-Za-z_])HOME=' "$pfad" && return 0
    case "$LESEND_LIVE_ALLOWLIST" in *" $name "*) return 0 ;; esac
    return 1
}
