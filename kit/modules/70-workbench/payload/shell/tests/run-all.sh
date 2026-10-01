#!/usr/bin/env bash
# run-all.sh -- the caller every shell test suite was missing.
#
# Anlass (2026-08-04): mindestens zehn Testskripte unter shell/tests/ und
# ~/.claude/hooks/tests/, jedes einzeln von Hand gestartet. "Ein Werkzeug ohne
# Aufrufer ist kein Werkzeug" -- selbe Lehre wie bei wb-hygiene, hier auf die
# Testsuiten selbst angewandt.
#
# Was dieses Skript tut:
#   * fuehrt jede shell/tests/test-*.{sh,py}-Suite aus, dazu (falls vorhanden)
#     jede hooks/tests/test-*.sh-Suite dieses Repos (seit 2026-09-11; fehlt
#     der Ordner, die unter ~/.claude/hooks/tests/), ein gemeinsamer Lauf
#     (Punkt 4 der Aufgabe).
#   * baut app/ als eigene Zeile, BEVOR die App-Suiten laufen (2026-08-15).
#     Ohne diesen Schritt ueberspringen sich alle test-app-*.sh still, sobald
#     app/dist fehlt oder veraltet ist -- Exit-Code 0 fuer eine halbe
#     Testerfassung, die nie gelaufen ist. Laesst sich hier nicht bauen (kein
#     npm, kein app/node_modules), entscheidet der Zustand von app/dist: aktuell
#     ist ein SKIP mit Grund, fehlend oder veraltet ein FAIL.
#   * haengt npm run check im extension/-Ordner als eigene Zeile an, damit EIN
#     Aufruf (dieses Skript) sowohl Shell- als auch Extension-Suiten prueft und
#     eine gemeinsame Tabelle ausgibt (Punkt 2 der Aufgabe).
#   * faengt Fehlschlaege ab statt beim ersten abzubrechen (kein `set -e`,
#     jede Suite laeuft unabhaengig von den anderen).
#   * erkennt Suiten, die eine besondere Umgebung brauchen (bisher: das lokale
#     Ollama-Modell fuer test-contradiction-queue.sh) und weist sie als
#     "SKIP -- <Grund>" aus, statt sie stillschweigend als bestanden oder als
#     Fehlschlag zu zaehlen. Alle anderen Suiten hier sind auf jeder Maschine
#     ohne Netz/host2/KDE lauffaehig -- geprueft per Kopfkommentar und Grep nach
#     echten Netz-/Fernzugriffen (siehe Session-Notiz 2026-08-04); nur die
#     Suiten, die tatsaechlich ein externes Backend ansprechen, tragen einen
#     Skip-Check unten in `skip_reason_for`.
#   * ruft am Ende shell/wb-consistency einmal gegen die LEBENDE Maschine auf.
#     Anlass 2026-08-04: auf host2 standen 27 unbemerkte Abweichungen, darunter
#     zehn Effort-Caps, die der Nutzer laengst geaendert hatte. Einen Aufrufer
#     GAB es (wb-hygiene --report, montags per launchd) -- nur lag dessen
#     Bericht in ~/.local/state/wb-hygiene-report.md, wo ihn niemand liest,
#     und auf host2 gibt es den Job ueberhaupt nicht. Hier zaehlt ein
#     Exit-Code ungleich 0 als FAIL und landet damit ueber wb-testsuite-run
#     in der Statusdatei, die der SessionStart-Hook tatsaechlich anschaut.
#
# Isolation: dieses Skript selbst fasst nichts an -- jede Suite bringt ihre
# eigene Isolation mit (eigener tmux-Socket via `-L`, eigenes HOME via
# `mktemp -d`, siehe deren Kopfkommentare). Dieses Skript startet nur den
# jeweiligen Interpreter auf die Datei, sonst nichts. Eine Ausnahme davon:
# shell/wb-consistency bringt bewusst KEINE eigene Isolation mit -- es prueft
# per Definition, ob Regeldateien, Rollendateien und Werkzeugbeschreibungen
# mit der Wirklichkeit GENAU DIESER Maschine uebereinstimmen (Effort-Caps
# gegen die Registry, genannte Werkzeuge gegen PATH). Gegen ein `mktemp -d`-
# HOME liefe es leer oder falsch -- es ist rein lesend (kein Schreiben, kein
# tmux, kein Netz), deshalb ist der Aufruf gegen die lebende Konfiguration
# hier zulaessig, obwohl das jeder anderen Suite verboten waere.
#
# Exit-Code: 0 nur, wenn keine Suite FAIL ist, keine Suite "nur unter Last rot"
# war UND kein Punkt uebersprungen wurde. Ausgenommen ist genau eine Art Skip:
# der, dessen Voraussetzung einer ANDEREN Maschine gehoert (Linux/host2, KDE,
# fremde Hardware, eine Gegenstelle im Netz). Diese Suiten melden
# "UEBERSPRUNGEN: nicht auf dieser Maschine: <Grund>" und stehen in der
# Schlusszeile als eigene Kategorie; sie zaehlen nicht gegen den Exit-Code.
# JEDER andere Skip zaehlt wie ein Fehlschlag -- wer das Kennzeichen nicht
# traegt, zaehlt mit (fail-closed). Anlass: Satz des Nutzers vom 2026-09-20
# ("kein einziger darf rot sein oder geskippt"), Entscheidung ai-78 vom 21.09.
#
# Run:  shell/tests/run-all.sh                       (Shell-Suiten + Extension)
#       shell/tests/run-all.sh --shell-only           (nur Shell-Suiten, kein npm)
#       shell/tests/run-all.sh --nur registry         (nur Suiten, deren Name "registry" enthaelt)
#       shell/tests/run-all.sh --schnell              (nur Suiten, die beim letzten Lauf < 15s brauchten)
#       shell/tests/run-all.sh --geaendert            (nur Suiten, die zu geaenderten Dateien gehoeren)
#       shell/tests/run-all.sh --geaendert --geaendert-gegen origin/main
#       shell/tests/run-all.sh --jobs 4               (Parallelitaet begrenzen; Default: min(8, CPU-Kerne))
#       shell/tests/run-all.sh --mac-jobs 4            (Parallelitaet der test-mac-*.sh; Default: 4)
#       shell/tests/run-all.sh --sequenziell           (alter Ein-Prozess-Modus, zum Vergleichen/Debuggen)
#       shell/tests/run-all.sh --ziel lokal-modell     (nur die Suiten, die ein GELADENES lokales Modell brauchen)
#
# --- Parallellauf (Auftrag 2026-08-19: 2466s ueber 186 Suiten sequenziell war
# Ausgangsbefund des Nutzers) ------------------------------------------------
#
# STAND DER TECHNIK, zuerst nachgesehen statt selbst erfunden: bats-core und
# shellspec loesen genau dieses Problem beide auf dieselbe Art -- Parallelitaet
# auf Ebene der DATEI, nicht innerhalb einer Datei ("it is necessary to
# separate the specfile for effective parallel execution", shellspec-Doku;
# bats-core warnt im selben Atemzug: "ordering of parallelised tests is not
# guaranteed, so this mode may break suites with dependencies between tests").
# Uebertragen auf dieses Repo: die Datei-Grenze ist schon lange die
# Isolations-Grenze (eigener tmux-Socket per `-L`, eigenes HOME per
# `mktemp -d`, siehe die Kopfkommentare der einzelnen Suiten) -- das macht
# Parallelitaet hier zulaessig, WENN eine Suite diese Grenze tatsaechlich
# einhaelt. Das wird unten je Suite GEPRUEFT (`ist_parallel_sicher`), nicht
# angenommen: der Vorfall vom 04.08. (eine Testsuite tippte ungeflaggt in
# laufende des Nutzers Sitzung) ist genau der Fehler, den eine blinde Annahme
# hier reproduzieren wuerde.
#
# CI-Praxis fuer Auswahl nach geaenderten Dateien (Playwright `--only-changed`,
# Jest `--onlyChanged`/`--findRelatedTests`, Vitest `--changed`) traegt dieselbe
# bekannte Einschraenkung: sie kann eine Suite uebersehen, die ein Test tatsaechlich
# bricht, weil die Abhaengigkeit nicht im Dateinamen steht. `--geaendert` unten
# uebernimmt das bewusst mit derselben Grenze (Heuristik: Suite-Pfad selbst
# geaendert ODER referenziert den Basisnamen einer geaenderten Datei im eigenen
# Quelltext) -- fuer den Alltag ("laeuft mein Umbau noch?") ausreichend, kein
# Ersatz fuer den vollen Lauf vor einem Merge.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Hook-Suiten relativ zum geprueften Repo (2026-09-11): fest unter
# $HOME/.claude/hooks/tests/ fand ein frischer Worktree seine eigenen
# Hook-Suiten nie ("0 von N ausgewaehlt") und lief stattdessen die
# installierten. Fehlt hooks/tests im Repo, bleibt der alte Ort der Rueckfall.
HOOKS_TESTS_DIR="$REPO_ROOT/hooks/tests"
[ -d "$HOOKS_TESTS_DIR" ] || HOOKS_TESTS_DIR="$HOME/.claude/hooks/tests"
EXTENSION_DIR="$REPO_ROOT/extension"
WB_CONSISTENCY="$REPO_ROOT/shell/wb-consistency"

SHELL_ONLY=0
NUR=""
SCHNELL=0
SCHNELL_SCHWELLE=15
GEAENDERT=0
GEAENDERT_REF=""
SEQUENZIELL=0
ZIEL=standard
# Aus einem Terminal der laufenden Mac-Werkbank traegt die Umgebung Mantel- und
# Steuerkanal des LEBENDEN Kerns (AWB_MANTEL_SOCKET, AWB_MANTEL_TOKEN,
# AWB_CONTROL_SOCKET). Jede Electron-Suite, die sie erbt, haengt sich an diesen
# Kern statt an ihren eigenen und scheitert mit "Steuerkanal ... ist bereits
# belegt" (15.09.2026: 64 von 388 Suiten rot, allein mit `env -u` gruen). Einzelne
# Suiten raeumen das selbst ab (test-app-agents, test-mac-start); hier gilt es
# fuer alle, weil kein Pruefling den lebenden Kern meint.
unset AWB_MANTEL_SOCKET AWB_MANTEL_TOKEN AWB_CONTROL_SOCKET
JOBS=""
MAC_JOBS=""
ZEIGE_JOBS=0
BESTAETIGEN=1
BESTAETIGEN_MAX=6

while [ $# -gt 0 ]; do
  case "$1" in
    --shell-only) SHELL_ONLY=1; shift ;;
    --nur) NUR="${2:-}"; [ -n "$NUR" ] || { echo "--nur braucht ein Muster" >&2; exit 2; }; shift 2 ;;
    --nur=*) NUR="${1#--nur=}"; shift ;;
    --schnell) SCHNELL=1; shift ;;
    --schnell-schwelle) SCHNELL_SCHWELLE="${2:-}"; shift 2 ;;
    --geaendert) GEAENDERT=1; shift ;;
    --geaendert-gegen) GEAENDERT_REF="${2:-}"; shift 2 ;;
    --jobs|-j) JOBS="${2:-}"; shift 2 ;;
    --mac-jobs) MAC_JOBS="${2:-}"; shift 2 ;;
    --mac-jobs=*) MAC_JOBS="${1#--mac-jobs=}"; shift ;;
    --sequenziell) SEQUENZIELL=1; shift ;;
    --ziel) ZIEL="${2:-}"; [ -n "$ZIEL" ] || { echo "--ziel braucht einen Namen (standard|lokal-modell)" >&2; exit 2; }; shift 2 ;;
    --ziel=*) ZIEL="${1#--ziel=}"; shift ;;
    --zeige-jobs) ZEIGE_JOBS=1; shift ;;
    --ohne-bestaetigung) BESTAETIGEN=0; shift ;;
    --hilfe|--help|-h)
      sed -n '63,73p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unbekannte Option: $1 (--hilfe fuer die Liste)" >&2; exit 2 ;;
  esac
done

case "$ZIEL" in
  standard|lokal-modell) : ;;
  *) echo "unbekanntes --ziel: $ZIEL (bekannt: standard, lokal-modell)" >&2; exit 2 ;;
esac

# --- freier Speicher, fuer die Drosselung unten -------------------------------
# Bewusst ohne fremdes Werkzeug: 'check-resources' fragt unter anderem Ollama ab
# und kann haengen, und 'timeout' gehoert auf macOS nicht zum Grundsystem. Ein
# Testlaeufer darf an seiner eigenen Vorpruefung nicht steckenbleiben.
#
# "Frei" heisst hier das, was ohne Auslagern verfuegbar waere: auf macOS die
# freien plus die inaktiven, spekulativen und aufgebbaren Seiten -- 'free' allein
# ist dort irrefuehrend, weil der Kernel Speicher als Cache haelt. Auf Linux ist
# es MemAvailable, das dieselbe Frage bereits beantwortet.
freier_speicher_mib() {
  # Einspeisepunkt fuer den Test: eine Drosselung, die sich nur bei wirklich
  # vollem Speicher zeigt, laesst sich sonst nicht pruefen -- und eine
  # ungepruefte Drosselung ist genau so viel wert wie die Handarbeit, die sie
  # ersetzt. Im Betrieb ist die Variable nie gesetzt.
  if [ -n "${WB_FREI_MIB_TEST:-}" ]; then
    printf '%s' "$WB_FREI_MIB_TEST"
    return
  fi
  if [ -r /proc/meminfo ]; then
    awk '/^MemAvailable:/ { print int($2 / 1024); found = 1 } END { if (!found) print "" }' \
      /proc/meminfo 2>/dev/null
    return
  fi
  command -v vm_stat >/dev/null 2>&1 || { printf ''; return; }
  local seitengroesse
  seitengroesse="$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)"
  vm_stat 2>/dev/null | awk -v seite="$seitengroesse" '
    /^Pages free:/                 { frei      = $3 }
    /^Pages inactive:/             { inaktiv   = $3 }
    /^Pages speculative:/          { spekulativ = $3 }
    /^Pages purgeable:/            { aufgebbar = $3 }
    END {
      gsub(/\./, "", frei); gsub(/\./, "", inaktiv)
      gsub(/\./, "", spekulativ); gsub(/\./, "", aufgebbar)
      summe = frei + inaktiv + spekulativ + aufgebbar
      if (summe > 0) print int(summe * seite / 1048576)
    }'
}

# Groesster Arbeitsspeicher-Anteil eines einzelnen Prozesses, in MiB. Ein
# geladener Modellserver faellt hier sofort auf, egal wie er heisst -- nach dem
# Namen zu suchen waere hier der falsche Griff, weil 'pgrep -f' auf den eigenen
# Rollen-Prompt trifft und weil jeder neue Motor einen neuen Namen mitbringt.
groesster_prozess_mib() {
  if [ -n "${WB_GROESSTER_MIB_TEST:-}" ]; then
    printf '%s' "$WB_GROESSTER_MIB_TEST"
    return
  fi
  ps -eo rss= 2>/dev/null | awk 'BEGIN { max = 0 }
    { if ($1 + 0 > max) max = $1 + 0 }
    END { if (max > 0) print int(max / 1024) }'
}

# --- Parallelitaet: wie viele Suiten gleichzeitig -----------------------------
if [ -z "$JOBS" ]; then
  JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
  case "$JOBS" in ''|*[!0-9]*) JOBS=4 ;; esac
  # KEIN DECKEL BEI ACHT MEHR (2026-08-22, Wort des Nutzers: "es ist noch lange nicht
  # ausgereizt"). Die Acht stammt aus einer Zeit vor dieser Maschine. Gemessen am 22.08. auf
  # 18 Kernen mit --jobs 14: Last 4,0, 27 GiB frei, voller Lauf in rund 9 statt 20 Minuten --
  # die Maschine war nicht annaehernd am Anschlag. Die Zahl der Kerne bleibt die Grenze, denn
  # mehr Suiten als Kerne ist die VORGABE, nicht die Grenze: wer `--jobs` ausdruecklich
  # hoeher setzt, bekommt es. Die meisten Suiten warten naemlich, statt zu rechnen
  # (Prozessstarts, tmux, Fristen), und dabei liegen Kerne brach. Was wirklich begrenzt,
  # ist der Speicher -- bei 14 gleichzeitigen blieben 27 GiB frei, also rund ein halbes
  # Gigabyte je Suite.
  #
  # WAS DABEI ZU BEDENKEN IST, und was am 21.08. wirklich passiert ist: der Mac blieb an jenem
  # Tag bei ACHT gleichzeitigen Suiten stehen -- neben einem geladenen Modellserver von
  # 28 GiB, mit 3,8 GiB frei. Das lag am Speicher, nicht an der Suitenzahl.
  #
  # Bis zum 2026-08-29 stand hier, wer die Suite neben einem grossen lokalen Modell fahre,
  # drossele "von Hand". Diese Handarbeit ist an diesem Tag ausgefallen: ein voller Lauf
  # startete neben dem geladenen lmgamma-27B (rund 16 GiB) samt Entwerfer und einem Worker
  # mit 262k Kontext. Vier Minuten spaeter stand die Maschine, und der Watchdog erzwang einen
  # harten Neustart -- "watchdog timeout: no checkins from watchdogd in 91 seconds". Die Regel
  # war notiert und wurde trotzdem nicht befolgt; also misst das Skript jetzt selbst, statt
  # sich auf das Gedaechtnis des Aufrufers zu verlassen.
  #
  # Der Verbrauch je Suite stammt aus der Messung oben: bei 14 gleichzeitigen blieben 27 GiB
  # frei, also rund ein halbes Gigabyte je Suite. Mit 4 GiB Reserve fuer das System heisst das
  # JOBS <= (frei - 4) / 0,5. Die Kernzahl bleibt die Obergrenze.
  frei_mib="$(freier_speicher_mib)"
  if [ -n "$frei_mib" ] && [ "$frei_mib" -gt 0 ] 2>/dev/null; then
    speicher_grenze=$(( (frei_mib - 4096) / 512 ))
    [ "$speicher_grenze" -lt 1 ] && speicher_grenze=1
    # Die 0,5 GiB je Suite stammen aus einem Lauf, bei dem 27 GiB frei BLIEBEN --
    # sie beschreiben den Ruhezustand, nicht die Spitze. Fuer den Fall, der die
    # Maschine zweimal gestellt hat, reicht das nachweislich nicht: am 29.08.
    # waren nach dem Laden des Modells noch rund 20 GiB frei, und diese Rechnung
    # allein haette daraus weiterhin volle Parallelitaet gemacht.
    #
    # Der gemeinsame Nenner beider Abstuerze war nicht eine Zahl, sondern ein
    # geladenes grosses Modell (21.08.: 28 GiB, 29.08.: lmgamma-27B mit rund
    # 16 GiB). Deshalb zaehlt zusaetzlich, ob gerade ein solcher Brocken laeuft --
    # gemessen am groessten Arbeitsspeicher-Anteil eines einzelnen Prozesses, was
    # MLX, Ollama, llama.cpp und vLLM gleichermassen erfasst, ohne Namen zu raten.
    groesster_mib="$(groesster_prozess_mib)"
    if [ -n "$groesster_mib" ] && [ "$groesster_mib" -gt 8192 ] 2>/dev/null; then
      [ "$speicher_grenze" -gt 4 ] && speicher_grenze=4
      printf 'run-all: ein Prozess haelt %d MiB -- vermutlich ein grosses lokales Modell.\n' \
        "$groesster_mib" >&2
    fi
    if [ "$speicher_grenze" -lt "$JOBS" ]; then
      printf 'run-all: %d MiB frei -- Parallelitaet auf %d gedrosselt (statt %d).\n' \
        "$frei_mib" "$speicher_grenze" "$JOBS" >&2
      printf '         Grund: ein voller Lauf neben einem grossen lokalen Modell hat den Mac\n' >&2
      printf '         am 21.08. und am 29.08. zum Stehen gebracht. Mehr Suiten mit\n' >&2
      printf '         "wb-mlx-server stop" (oder "ollama stop <modell>") und erneutem Aufruf.\n' >&2
      JOBS="$speicher_grenze"
    fi
  else
    printf 'run-all: freier Speicher nicht messbar -- Parallelitaet bleibt bei %d.\n' "$JOBS" >&2
  fi
else
  # Ein ausdruecklich genanntes --jobs wird NICHT ueberstimmt: wer die Zahl tippt,
  # bekommt sie (dieselbe Linie wie ueberall im Haus -- warnen ja, den Start eines
  # Menschen verhindern nein). Gewarnt wird trotzdem, denn genau dieser Weg fuehrt
  # sonst an der Drosselung vorbei, und der Absturz vom 29.08. kam aus einem Lauf,
  # bei dem niemand auf den Speicher gesehen hat.
  frei_mib="$(freier_speicher_mib)"
  if [ -n "$frei_mib" ] && [ "$frei_mib" -gt 0 ] 2>/dev/null; then
    empfohlen=$(( (frei_mib - 4096) / 512 ))
    [ "$empfohlen" -lt 1 ] && empfohlen=1
    if [ "$empfohlen" -lt "$JOBS" ]; then
      printf 'run-all: WARNUNG -- nur %d MiB frei; zu --jobs %d passen rechnerisch %d.\n' \
        "$frei_mib" "$JOBS" "$empfohlen" >&2
      printf '         Der Lauf startet trotzdem, weil die Zahl ausdruecklich genannt wurde.\n' >&2
      printf '         Laeuft ein grosses lokales Modell, erst "wb-mlx-server stop".\n' >&2
    fi
  fi
fi
[ "$SEQUENZIELL" -eq 1 ] && JOBS=1

# --- Parallelitaet der Mac-Suiten (2026-09-06, Auftrag 4.2) ------------------
# Der Vorgabewert steht hier als ZAHL und nicht als Rechnung, weil das, was
# diese Suiten begrenzt, sich nicht aus freiem Speicher ableiten laesst: jede
# startet einen Electron-Kern und eine AppKit-App, und was unter Last zuerst
# reisst, sind ihre Zeitfristen (15 s auf die Verbindung zum Kern, 15 s auf
# den ersten Terminaltext), nicht der Arbeitsspeicher. Die Zahl ist gemessen,
# nicht geraten -- der Messwert steht im Kommentar bei `ist_mac_suite`. Sie
# folgt trotzdem einer engeren Deckelung nach unten: wer den ganzen Lauf wegen
# Speichermangels auf zwei drosselt, will hier keine vier.
if [ -z "$MAC_JOBS" ]; then
  MAC_JOBS=4
  [ "$MAC_JOBS" -gt "$JOBS" ] 2>/dev/null && MAC_JOBS="$JOBS"
fi
[ "$SEQUENZIELL" -eq 1 ] && MAC_JOBS=1

# Nur die ermittelte Parallelitaet nennen und aufhoeren -- bewusst VOR der
# Laufsperre weiter unten, damit ein Test diese Rechnung pruefen kann, ohne dem
# laufenden Vollauf die Sperre wegzunehmen. Fuer den Menschen ist es die Antwort
# auf "wie viele wuerdest Du jetzt starten", ohne etwas zu starten.
if [ "$ZEIGE_JOBS" -eq 1 ]; then
  printf '%s\n' "$JOBS"
  exit 0
fi

# --- Zeitverlauf je Suite, fuer --schnell -------------------------------------
# Anlass (2026-08-19): "eine schnelle Teilmenge fuer den Alltag" braucht eine
# Schwelle, die nicht im Code veraltet. Statt einer im Quelltext eingefrorenen
# Liste schwerer Suiten (die beim naechsten Umbau falsch wird, ohne dass es
# auffaellt) merkt sich JEDER Lauf die real gemessene Dauer je Suite hier drin
# -- `--schnell` liest das beim naechsten Mal wieder. Eine Suite ohne Eintrag
# (neu, oder nie in diesem Modus gelaufen) zaehlt als "schnell genug" und laeuft
# mit -- eine neue Suite darf nie durch fehlende Historie verschwinden.
TIMING_FILE="$HOME/.local/state/wb-run-all-tests.timings.tsv"
THIS_RUN_TIMINGS="$(mktemp "${TMPDIR:-/tmp}/wb-run-all-timings.XXXXXX")"

TIMEOUT_BIN=""
command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN="timeout"
DEFAULT_TIMEOUT=300

# --- Verhindert zwei gleichzeitige Laeufe -----------------------------------
# Anlass (04.08., Abnahme des vorigen Auftrags): zwei run-all.sh aus zwei
# verschiedenen Arbeitsbaeumen liefen gleichzeitig, und test-doctor-betriebs-
# befunde.sh wurde dadurch grundlos rot. Der Fehler lag nicht in der Suite,
# sondern in der Kontention um GEMEINSAMEN Zustand: den tmux-Socket-Namensraum
# unter /tmp/tmux-<uid>/, den `prune_dead_test_sockets`-Schritt am Ende dieses
# Skripts, die lebende Maschine, gegen die wb-consistency prueft. Die Sperre
# ist deshalb GLOBAL fuer den Benutzer (unter $HOME/.local/state/), nicht pro
# Arbeitsbaum -- ein Sperrpfad unterhalb des eigenen Arbeitsbaums haette genau
# den Fall aus zwei VERSCHIEDENEN Arbeitsbaeumen gar nicht verhindert.
#
# PID-Lebendigkeit statt Verfallsfrist: die mkdir-Sperre fuer settings.json
# (shell/wb-state) nimmt eine feste Zehn-Sekunden-Schwelle, weil deren
# Schreibvorgang selbst nur Millisekunden dauert -- dort ist "aelter als zehn
# Sekunden" ein brauchbarer Anhaltspunkt fuer "der Halter ist abgestuerzt".
# Ein echter run-all.sh-Lauf dagegen dauert regulaer mehrere Minuten. Eine
# feste Schwelle muesste hier entweder kurz genug sein, um einen noch
# laufenden, legitimen Lauf faelschlich fuer abgestuerzt zu halten -- also
# denselben Fehler nur andersherum -- oder so lang, dass ein wirklich
# abgestuerzter Lauf minutenlang blockiert. Eine Pruefung auf die lebende PID
# hat dieses Dilemma nicht: sie beantwortet "lebt der Halter noch?" exakt,
# unabhaengig davon, wie lange ein legitimer Lauf schon dauert. `ps -p <pid>`
# reicht dafuer aus (kein `kill -0` noetig, es wird nichts signalisiert) --
# zusaetzlich wird der Kommandoname verglichen, damit eine seit dem Absturz
# wiederverwendete PID nicht faelschlich als "noch derselbe Lauf" gilt.
#
# Abbruch statt Warten: ein run-all.sh, das bis zu zehn Minuten auf einen
# fremden, ebenfalls bis zu zehn Minuten laufenden Lauf wartet, haengt in
# einem Terminal unvorhersehbar lange, ohne dass ohne staendiges Mitlesen
# erkennbar waere, ob es haengt oder nur wartet. Ein sofortiger, lauter
# Abbruch mit PID, Startzeit und Arbeitsbaum des Halters gibt die Entscheidung
# an die aufrufende Seite zurueck (Mensch oder Worker) -- eine Warteschleife
# mit fest eingebauter Politik waere hier eine Annahme, die nicht fuer jeden
# Aufrufer stimmt; wer warten will, kann das trivial selbst um den Aufruf
# legen. Exit-Code 2, damit er sich vom Exit-Code 1 echter Testfehlschlaege
# unterscheiden laesst.
RUN_LOCK_DIR="$HOME/.local/state/wb-run-all-tests.lock.d"
RUN_LOCK_INFO="$RUN_LOCK_DIR/info"
RUN_LOCK_HELD=0

acquire_run_lock() {
  mkdir -p "$HOME/.local/state"
  local attempt held_pid held_epoch held_iso held_repo held_comm now_comm now dur
  for ((attempt = 1; attempt <= 100; attempt++)); do
    if mkdir "$RUN_LOCK_DIR" 2>/dev/null; then
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$$" "$(date +%s)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$REPO_ROOT" \
        "$(ps -p $$ -o comm= 2>/dev/null | tr -d ' ')" > "$RUN_LOCK_INFO"
      RUN_LOCK_HELD=1
      return 0
    fi
    if [ ! -s "$RUN_LOCK_INFO" ]; then
      sleep 0.1   # jemand ist gerade mitten im Erwerb -- den Info-Schreibvorgang abwarten
      continue
    fi
    IFS=$'\t' read -r held_pid held_epoch held_iso held_repo held_comm < "$RUN_LOCK_INFO" 2>/dev/null
    if [ -z "$held_pid" ]; then
      sleep 0.1
      continue
    fi
    now_comm="$(ps -p "$held_pid" -o comm= 2>/dev/null | tr -d ' ')"
    if [ -n "$now_comm" ] && [ "$now_comm" = "$held_comm" ]; then
      case "$held_epoch" in ''|*[!0-9]*) held_epoch=0 ;; esac
      now=$(date +%s)
      dur=$((now - held_epoch))
      echo "run-all.sh laeuft bereits -- kein gleichzeitiger zweiter Lauf." >&2
      echo "  Halter-PID: $held_pid" >&2
      echo "  laeuft seit: $held_iso (vor $((dur/60))m $((dur%60))s)" >&2
      echo "  Arbeitsbaum: $held_repo" >&2
      echo "Bitte warten, bis dieser Lauf fertig ist, und dann erneut starten." >&2
      return 1
    fi
    # Halter-PID ist tot, oder wurde seither von einem anderen Prozess
    # wiederverwendet -- liegengebliebene Sperre eines abgestuerzten oder
    # abgebrochenen Laufs. Uebernehmen statt ewig blockieren.
    echo "Uebernehme liegengebliebene run-all.sh-Sperre (Halter-PID $held_pid laeuft nicht mehr)." >&2
    rm -rf "$RUN_LOCK_DIR" 2>/dev/null
  done
  echo "run-all.sh-Sperre liess sich nach mehreren Versuchen nicht erwerben (Wettlauf?) -- Abbruch." >&2
  return 1
}

release_run_lock() {
  [ "$RUN_LOCK_HELD" -eq 1 ] && rm -rf "$RUN_LOCK_DIR" 2>/dev/null
  # Nur noch das Netz fuer einen ABGEBROCHENEN Lauf (Ctrl-C, Absturz): ein
  # normal durchgelaufenes Skript hat POOL_DIR am Ende schon selbst geleert
  # oder nach $HOME/.local/state/wb-run-all-letzter-roter-lauf verschoben
  # (siehe dort, 2026-08-22) -- hier greift dann nichts mehr.
  [ -n "${POOL_DIR:-}" ] && rm -rf "$POOL_DIR" 2>/dev/null
  [ -n "${MAC_POOL_DIR:-}" ] && rm -rf "$MAC_POOL_DIR" 2>/dev/null
  [ -n "${THIS_RUN_TIMINGS:-}" ] && rm -f "$THIS_RUN_TIMINGS" 2>/dev/null
}
trap release_run_lock EXIT

if ! acquire_run_lock; then
  exit 2
fi

# Testhaken fuer shell/tests/test-run-all-lock.sh: die Sperre wirklich zu
# pruefen braucht zwei echte, gleichzeitige run-all.sh-Prozesse -- ohne diesen
# Haken muesste jeder Testlauf auf einen vollen, mehrminuetigen Lauf warten,
# nur um die paar Zeilen rund um acquire_run_lock zu treffen. Ausserhalb
# dieser einen Suite bleibt die Variable unter Standardbedingungen unbesetzt
# und aendert nichts (RUN_ALL_LOCK_SELFTEST=1 muss explizit gesetzt werden).
if [ "${RUN_ALL_LOCK_SELFTEST:-0}" = "1" ]; then
  echo "RUN_ALL_LOCK_SELFTEST: Sperre erworben (PID $$), halte sie ${RUN_ALL_LOCK_SELFTEST_HOLD:-2}s."
  sleep "${RUN_ALL_LOCK_SELFTEST_HOLD:-2}"
  exit 0
fi

declare -a NAMES STATUSES DURATIONS REASONS
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FREMD_COUNT=0
# Eine Baustufe, deren Gegenstand es in diesem Baum gar nicht gibt (kein app/,
# kein mac/). Das ist weder ein Fehlschlag noch ein Maschinenunterschied: wo
# app/ fehlt, fehlen auch die test-app-*.sh, es bleibt also keine Zusage
# ungeprueft. Der Fall kommt im echten Baum nicht vor -- er trifft die
# Miniatur-Baeume, mit denen die Laeufer-Suiten selbst arbeiten, und die
# Klone ohne App, fuer die diese Stufe seit dem 15.08.2026 ausdruecklich
# "kein Fehlschlag" sagt (shell/tests/test-run-all-appbau.sh, Fall 1).
KEIN_GEGENSTAND_COUNT=0
# Die zaehlenden Skips im Klartext. Eine eigene Liste statt eines Filters ueber
# STATUSES: in der Tabelle steht "SKIP" auch bei den Baustufen ohne Gegenstand
# (siehe oben), und eine Klartextliste, die mehr Zeilen zeigt als die Zahl in
# der Schlusszeile, waere genau die Art Ungereimtheit, die niemand mehr liest.
declare -a ZAEHLENDE_SKIPS

# --- Welcher Skip ist zulaessig, welcher ist ein Fehlschlag? ---------------
# Auflage des Nutzers vom 2026-09-20: ein Gesamtlauf hat "keinen einzigen roten
# und keinen geskippten" Punkt. Ein Skip laesst sich davon nur ausnehmen, wenn
# seine Voraussetzung auf DIESER Maschine gar nicht herstellbar ist, weil sie
# einer anderen gehoert -- Linux/host2, KDE, fremde Hardware, eine Gegenstelle
# im Netz. Alles andere (ein fehlendes Werkzeug, ein nicht gebautes Paket, ein
# nicht geladenes lokales Modell) ist herstellbar und damit ein Befund.
#
# Das Kennzeichen ist ABSICHTLICH ein Klartext-Praefix im Skip-Grund und keine
# zweite Exit-Nummer: eine Suite sagt ihren Grund ohnehin im Klartext, und der
# Mensch im Terminal liest dieselbe Zeile wie dieses Skript. Wer es fuehrt,
# schreibt ihn so:
#
#     echo "UEBERSPRUNGEN: nicht auf dieser Maschine: <Grund>"; exit 77
#
# FAIL-CLOSED: eine bestehende Suite mit dem alten Muster "UEBERSPRUNGEN: ..."
# ohne dieses Kennzeichen erscheint als ZAEHLENDER Skip. Das ist die richtige
# Richtung -- ein vergessenes Kennzeichen macht den Lauf laut, ein zu grosszuegig
# gesetztes macht ihn still.
SKIP_FREMD_KENNZEICHEN='nicht auf dieser Maschine'
skip_ist_maschinenfremd() {   # $1 = Skip-Grund (eine oder mehrere Zeilen)
  case "$1" in
    *"$SKIP_FREMD_KENNZEICHEN"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Status und Zaehler fuer einen Skip, aus seinem Grund abgeleitet. Gibt
# "FREMD" oder "SKIP" aus -- die Zaehler ruehrt der Aufrufer an, weil im
# Parallel-Pool ein Hintergrundprozess sie ohnehin nur fuer sich selbst
# aendern wuerde.
skip_status_fuer() {   # $1 = Skip-Grund
  if skip_ist_maschinenfremd "$1"; then echo "FREMD"; else echo "SKIP"; fi
}

# --- Umgebungspruefungen fuer bekannte Sonderfaelle ------------------------

ollama_up() {
  curl -s -m 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1
}

# Die Warteschlangen-Suite braucht ausser dem Modell auch die Unterbefehle
# `brain contradict --queue-add/--queue`. Die kamen erst am 2026-08-04 in die
# braincli im Kbase; eine Maschine mit aelterem ~/work/brain hat sie nicht.
# Ohne diese Pruefung meldete host2 acht rote Zeilen fuer eine Faehigkeit, die
# dort schlicht noch nicht installiert ist -- ein FAIL, wo ein SKIP hingehoert.
brain_has_queue() {
  local brain="${BRAIN_BIN:-$HOME/.local/bin/brain}"
  [ -x "$brain" ] || return 1
  "$brain" contradict --help 2>&1 | grep -q -- '--queue-add'
}

# DIE MAC-NATIVE WERKBANK GIBT ES NUR AUF DEM MAC (2026-09-06, Auftrag 4.2).
# `mac/` ist ein SwiftPM-Paket mit SwiftTerm und AppKit; auf host2 fehlt dafuer
# das Toolkit, und die dreiundzwanzig test-mac-*.sh-Suiten koennten dort nicht einmal
# bauen. Ein Skip mit Grund statt dreiundzwanzig roter Zeilen fuer eine Fassung, die
# auf dieser Maschine gar nicht gemeint ist -- derselbe Fall wie
# test-modell-proxy.sh, nur andersherum.
# Der Nicht-Darwin-Fall traegt das Kennzeichen (die Mac-App gehoert einer
# anderen Maschine), der fehlende swift NICHT: auf einem Mac ist das eine
# fehlende Installation, also ein Befund und kein Naturgesetz.
MAC_SKIP_GRUND=""
if [ "$(uname -s)" != "Darwin" ]; then
  MAC_SKIP_GRUND="nicht auf dieser Maschine: die Mac-native Werkbank (mac/) gibt es nur auf macOS -- hier laeuft $(uname -s)"
elif ! command -v swift >/dev/null 2>&1; then
  MAC_SKIP_GRUND="swift nicht im PATH -- ohne Toolkit laesst sich mac/ nicht bauen"
fi

# $1 = Basisname der Suite-Datei. Leere Ausgabe = kein Skip.
skip_reason_for() {
  case "$1" in
    test-mac-*.sh)
      [ -n "$MAC_SKIP_GRUND" ] && echo "$MAC_SKIP_GRUND"
      ;;
    test-modell-proxy.sh)
      # shell/wb-modell-proxy traegt die Shebang '#!/opt/homebrew/bin/python3'
      # -- ein Mac-Homebrew-Pfad, den es auf host2 nicht gibt ("bad interpreter:
      # No such file or directory", gemessen 20260821). Bucket 1 aus Auftrag
      # 20260821-013717: Mac-only von Anfang an, kein Bug hier -- der Test lief
      # bisher trotzdem rot statt sauber uebersprungen zu werden.
      [ -x /opt/homebrew/bin/python3 ] \
        || echo "nicht auf dieser Maschine: shell/wb-modell-proxy hat die Shebang '#!/opt/homebrew/bin/python3' -- ein Mac-Homebrew-Pfad, den es hier nicht gibt"
      ;;
    test-contradiction-queue.sh)
      # KEIN Kennzeichen: ein lokales Modell laesst sich auf dieser Maschine
      # laden, es ist nur gerade keins geladen. Deshalb zaehlt dieser Skip --
      # und deshalb laeuft die Suite im eigenen Ziel `--ziel lokal-modell`,
      # das man mit geladenem Modell faehrt, statt sie im Alltagslauf still
      # durchrutschen zu lassen (siehe `ist_lokal_modell_suite`).
      if ! ollama_up; then
        echo "lokales Modell (Ollama, 127.0.0.1:11434) nicht erreichbar"
      elif ! brain_has_queue; then
        echo "brain kennt 'contradict --queue-add/--queue' nicht -- ~/work/brain ist aelter als 2026-08-04 (git pull im Kbase)"
      fi
      ;;
    test-knopf-tastendruck.py)
      # Haengt sich per pty an einen ECHTEN tmux-Client, um Tastenbindungen zu
      # pruefen (siehe Skript-Kopf) -- das braucht einen bereits angehefteten
      # Client ($TMUX gesetzt). Reproduzierbar geprueft am 2026-08-04: unter
      # `env -i` (wie launchd es faehrt, kein $TMUX, kein TTY) schlaegt es
      # 3/3 fehl bzw. crasht ohne TERM mit OSError EIO; aus einer echten
      # tmux-Sitzung heraus 2/2 bestanden. Kein Bug im Testrunner, sondern
      # eine echte Umgebungs-Voraussetzung wie eine laufende KDE-Sitzung.
      #
      # $TMUX ALLEIN reicht nicht (Befund 2026-08-21): ein Werkbank-Worker
      # laeuft SELBST in einem tmux-Pane, erbt darueber $TMUX, hat aber kein
      # eigenes TTY (`[ -t 0 ]`/`[ -t 1 ]` beide falsch -- sein stdin/stdout
      # sind Pipes des Werkzeugaufrufs, kein Terminal). Genau in dieser Lage
      # blieb 'es leben noch [...]' stehen: die Suite haengte sich an einen
      # Client, der da ist, aber zu keinem echten Terminal gehoert. Verlangt
      # wird deshalb zusaetzlich ein eigenes TTY.
      #
      # NACHTRAG 2026-09-21: das fehlende eigene TTY ist kein Grund mehr zu
      # ueberspringen. Ein Pseudoterminal laesst sich hier herstellen --
      # `script -q /dev/null` gibt dem Lauf genau das, was ihm fehlt, und aus
      # einer Agentensitzung ohne eigenes Terminal lief die Suite damit
      # gemessen durch ("Knopf schliesst die eigene Session samt Sicht --
      # bestanden"). Gestellt wird das in `pty_wrapper_fuer`; hier bleibt nur
      # noch die Voraussetzung, die sich NICHT herstellen laesst: ein
      # angehefteter tmux-Client. Anlass ist Auflage des Nutzers vom 2026-09-20,
      # dass ein Gesamtlauf keinen einzigen uebersprungenen Punkt haben darf.
      #
      # NACHTRAG 2026-09-24: auch der angeheftete Client ist keine Voraussetzung
      # mehr. Seit wb/knopf (26af4261) stellt die Suite eigenen tmux-Socket,
      # HOME und einen echten Client per pty.fork selbst her; eine fehlende
      # Voraussetzung ist dort ein FAIL, nie ein SKIP. Der Gesamtlauf vom
      # 24.09. (bereinigte Umgebung ohne $TMUX) hatte die Suite deshalb noch
      # faelschlich uebersprungen.
      ;;
  esac
}

# --- Isolations-Pruefung: darf eine Suite in den Parallel-Pool? -------------
# Auftrag 2026-08-19: "Pruef das je Suite nach, statt es anzunehmen." Diese
# Funktion laeuft bei JEDEM Aufruf gegen den AKTUELLEN Quelltext jeder Suite --
# kein einmaliger, veraltender Handaudit, sondern eine Pruefung, die mit der
# Suite mitgeht, wenn sie sich aendert. Ausgelagert nach lib-parallel-sicher.sh
# (2026-08-22, geschaerft um die Achsen aus dem Notbremsen-Vorfall vom 21.08.),
# damit shell/tests/test-parallel-sicher-achsen.sh dieselbe Pruefung ohne den
# ganzen Suitenlauf sourcen kann -- Begruendung je Achse steht dort.
# shellcheck source=lib-parallel-sicher.sh
. "$SCRIPT_DIR/lib-parallel-sicher.sh"

# --- Auswahl: soll diese Suite in DIESEM Lauf ueberhaupt starten? -----------
GEAENDERT_TREFFER=""
geaendert_ermitteln() {
  local ref="$GEAENDERT_REF" changed
  if [ -z "$ref" ]; then
    ref="$(git -C "$REPO_ROOT" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@origin/@')"
    [ -z "$ref" ] && ref="main"
  fi
  changed="$( { git -C "$REPO_ROOT" diff --name-only "$ref"...HEAD 2>/dev/null
                git -C "$REPO_ROOT" diff --name-only HEAD 2>/dev/null
                git -C "$REPO_ROOT" status --porcelain 2>/dev/null | awk '{print $2}'
              } | sort -u )"
  echo "== --geaendert gegen $ref: $(printf '%s\n' "$changed" | grep -c .) geaenderte Datei(en) =="
  local cf cb f nm
  while IFS= read -r cf; do
    [ -n "$cf" ] || continue
    cb="$(basename "$cf")"
    for f in "$SCRIPT_DIR"/test-*.sh "$SCRIPT_DIR"/test-*.py "$SCRIPT_DIR"/betriebslauf*.sh "$HOOKS_TESTS_DIR"/test-*.sh; do
      [ -f "$f" ] || continue
      nm="$(basename "$f")"
      case "$GEAENDERT_TREFFER" in *" $nm "*) continue ;; esac
      if [ "$nm" = "$cb" ]; then GEAENDERT_TREFFER="$GEAENDERT_TREFFER $nm "; continue; fi
      grep -qF -- "$cb" "$f" 2>/dev/null && GEAENDERT_TREFFER="$GEAENDERT_TREFFER $nm "
    done
  done <<EOF
$changed
EOF
}
[ "$GEAENDERT" -eq 1 ] && geaendert_ermitteln

suite_ausgewaehlt() {
  local pfad="$1" name letzte
  name="$(basename "$pfad")"
  if [ -n "$NUR" ]; then
    case "$name" in *"$NUR"*) : ;; *) return 1 ;; esac
  fi
  if [ "$SCHNELL" -eq 1 ] && [ -f "$TIMING_FILE" ]; then
    letzte="$(awk -F'\t' -v n="$name" '$1==n{d=$2} END{if(d!="")print d}' "$TIMING_FILE")"
    if [ -n "$letzte" ]; then
      awk -v d="$letzte" -v s="$SCHNELL_SCHWELLE" 'BEGIN{exit !(d>s)}' && return 1
    fi
  fi
  if [ "$GEAENDERT" -eq 1 ]; then
    case "$GEAENDERT_TREFFER" in *" $name "*) : ;; *) return 1 ;; esac
  fi
  return 0
}

# --- eine Suite ausfuehren und Ergebnis merken -----------------------------
# $1 = Pfad zur Suite, $2 = Anzeige-Praefix, $3 = Interpreter ("bash"/"python3")
# Braucht diese Suite ein Pseudoterminal, das diesem Lauf fehlt? (2026-09-21)
# Nur fuer die eine Suite, die nachweislich eines braucht, und nur dann, wenn
# der Lauf selbst keines hat -- laeuft der Gesamtlauf in einem echten Terminal,
# aendert sich nichts. `script` gehoert zum Grundsystem (macOS wie Linux); fehlt
# es doch, bleibt es beim Lauf ohne Pseudoterminal und die Suite meldet ihren
# Fehlschlag selbst, statt still zu verschwinden.
pty_wrapper_fuer() {
  [ "$1" = test-knopf-tastendruck.py ] || return 1
  [ ! -t 0 ] && [ ! -t 1 ] || return 1
  command -v script >/dev/null 2>&1 || return 1
  return 0
}

run_suite() {
  local path="$1" label="$2" interp="$3"; shift 3
  # Weitere Argumente (optional) gehen unveraendert an den Pruefling durch --
  # bisher nur fuer wb-consistency gebraucht (--repo), damit es gegen DIESEN
  # Baum prueft statt gegen den hart verdrahteten Vorgabewert ~/AI/claude-workbench.
  local name display reason start end dur out status
  name="$(basename "$path")"
  display="$label/$name"

  reason="$(skip_reason_for "$name")"
  if [ -n "$reason" ]; then
    local st; st="$(skip_status_fuer "$reason")"
    echo "== $st  $display -- $reason =="
    NAMES+=("$display"); STATUSES+=("$st"); DURATIONS+=("-"); REASONS+=("$reason")
    if [ "$st" = "FREMD" ]; then FREMD_COUNT=$((FREMD_COUNT + 1)); else SKIP_COUNT=$((SKIP_COUNT + 1)); ZAEHLENDE_SKIPS+=("$display  $reason"); fi
    return
  fi

  echo "== RUN   $display =="
  start=$(date +%s)
  local -a PTY=()
  pty_wrapper_fuer "$name" && PTY=(script -q /dev/null)
  if [ -n "$TIMEOUT_BIN" ]; then
    # ${PTY[@]+…}: ein LEERES Feld unter `set -u` ist in bash 3.2 (macOS
    # /bin/bash) ein Abbruch mit "unbound variable" -- hier gemessen, nicht
    # angenommen: genau daran scheiterte der erste Lauf dieser Aenderung.
    out="$(${PTY[@]+"${PTY[@]}"} "$TIMEOUT_BIN" "$DEFAULT_TIMEOUT" "$interp" "$path" "$@" 2>&1)"
  else
    out="$(${PTY[@]+"${PTY[@]}"} "$interp" "$path" "$@" 2>&1)"
  fi
  status=$?
  end=$(date +%s)
  dur="$((end - start))s"
  echo "$out"

  NAMES+=("$display"); DURATIONS+=("$dur")
  # Exit 77 heisst "ich habe mich selbst uebersprungen" (die uebliche
  # Kennzeichnung, auch in autotools). Anlass 2026-08-04, aus einem
  # Reviewer-Pass: `test-app-geruest.sh` ueberspringt sich, wenn
  # `app/node_modules` fehlt, und endete dabei mit 0 -- in der Tabelle stand
  # ein GRUENER Punkt fuer eine Suite, die keine einzige Behauptung geprueft
  # hat. Auf der zweiten Maschine und in jedem frischen Klon ist das der
  # Normalfall, nicht der Sonderfall. `skip_reason_for` kann diesen Fall nicht
  # abdecken: Es entscheidet VOR dem Lauf, und ob die Voraussetzungen fehlen,
  # weiss erst die Suite selbst.
  if [ "$status" -eq 77 ]; then
    skipmsg="$(printf '%s\n' "$out" | grep -iE 'UEBERSPRUNGEN|UEBERSPRINGE|SKIP' | tail -1)"
    [ -n "$skipmsg" ] || skipmsg="Suite hat sich selbst uebersprungen (exit 77)"
    # Gelesen wird die GANZE Ausgabe, nicht nur die letzte Skip-Zeile: eine
    # Suite darf ihren Grund auch in einer Zeile davor nennen. Fehlt das
    # Kennzeichen ueberall, zaehlt der Skip (fail-closed).
    local st; st="$(skip_status_fuer "$out")"
    STATUSES+=("$st"); REASONS+=("$skipmsg")
    if [ "$st" = "FREMD" ]; then FREMD_COUNT=$((FREMD_COUNT + 1)); else SKIP_COUNT=$((SKIP_COUNT + 1)); ZAEHLENDE_SKIPS+=("$display  $skipmsg"); fi
  elif [ "$status" -eq 0 ]; then
    STATUSES+=("PASS"); REASONS+=("")
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    STATUSES+=("FAIL"); REASONS+=("exit $status")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  printf '%s\t%s\n' "$name" "$((end - start))" >> "$THIS_RUN_TIMINGS"
}

# --- dieselbe Suite, aber gepuffert -- fuer den Parallel-Pool ---------------
# $1 = Pfad, $2 = Anzeige-Praefix, $3 = Interpreter, $4 = Ergebnis-Dateipraefix.
# Laeuft im Hintergrundprozess: schreibt NUR in Dateien, ruehrt keine der
# NAMES/STATUSES/...-Arrays des Elternprozesses an (ein Hintergrund-Subshell
# haette dort ohnehin nur seine eigene Kopie geaendert). `_drain_suite_result`
# liest diese Dateien anschliessend im Elternprozess ein -- derselbe Zustand,
# nur einen Schritt spaeter.
run_suite_bg() {
  local path="$1" label="$2" interp="$3" base="$4"
  local name display reason start end dur out status skipmsg
  name="$(basename "$path")"
  display="$label/$name"

  reason="$(skip_reason_for "$name")"
  if [ -n "$reason" ]; then
    local st; st="$(skip_status_fuer "$reason")"
    printf '== %s  %s -- %s ==\n' "$st" "$display" "$reason" > "$base.out"
    printf '%s\t%s\t%s\t%s\n' "$display" "$st" "-" "$reason" > "$base.meta"
    : > "$base.done"
    return
  fi

  start=$(date +%s)
  if [ -n "$TIMEOUT_BIN" ]; then
    out="$("$TIMEOUT_BIN" "$DEFAULT_TIMEOUT" "$interp" "$path" 2>&1)"
  else
    out="$("$interp" "$path" 2>&1)"
  fi
  status=$?
  end=$(date +%s)
  dur="$((end - start))"
  { printf '== RUN   %s ==\n' "$display"; printf '%s\n' "$out"; } > "$base.out"

  if [ "$status" -eq 77 ]; then
    skipmsg="$(printf '%s\n' "$out" | grep -iE 'UEBERSPRUNGEN|UEBERSPRINGE|SKIP' | tail -1)"
    [ -n "$skipmsg" ] || skipmsg="Suite hat sich selbst uebersprungen (exit 77)"
    printf '%s\t%s\t%s\t%s\n' "$display" "$(skip_status_fuer "$out")" "${dur}s" "$skipmsg" > "$base.meta"
  elif [ "$status" -eq 0 ]; then
    printf '%s\t%s\t%s\t%s\n' "$display" "PASS" "${dur}s" "" > "$base.meta"
  else
    printf '%s\t%s\t%s\t%s\n' "$display" "FAIL" "${dur}s" "exit $status" > "$base.meta"
  fi
  printf '%s\t%s\n' "$name" "$dur" >> "$base.timing"
  : > "$base.done"
}

# Liest ein fertiges Pool-Ergebnis in die Tabellen-Arrays des Elternprozesses --
# muss im Elternprozess laufen (nie im Hintergrundjob selbst).
_drain_suite_result() {
  local base="$1" disp stat dur reason
  cat "$base.out"
  IFS=$'\t' read -r disp stat dur reason < "$base.meta"
  NAMES+=("$disp"); STATUSES+=("$stat"); DURATIONS+=("$dur"); REASONS+=("$reason")
  case "$stat" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    SKIP) SKIP_COUNT=$((SKIP_COUNT + 1)); ZAEHLENDE_SKIPS+=("$disp  $reason") ;;
    FREMD) FREMD_COUNT=$((FREMD_COUNT + 1)) ;;
  esac
  [ -f "$base.timing" ] && cat "$base.timing" >> "$THIS_RUN_TIMINGS"
}

# --- der Pool selbst: bis zu $JOBS Suiten gleichzeitig ----------------------
# Bash 3.2 (macOS-System-Bash, kein `wait -n`) -- portabler Ersatz: feste
# Slots, jeder Hintergrundjob meldet sein Ende per Marker-Datei (`.done`), der
# Elternprozess pollt alle 0.2s, welche Slots fertig sind, und fuellt sie sofort
# nach. Kein GNU-parallel-Requirement (bats-core/shellspec brauchen das fuer
# --jobs) -- auf einem frischen Mac ohne Homebrew waere das eine zusaetzliche
# Installation, die dieses Skript nicht braucht.
run_pool() {
  local outdir="$1" n=${#POOL_PATHS[@]}
  [ "$n" -eq 0 ] && return 0
  local -a slot_pid slot_base
  local j next=0 done_count=0 base
  for ((j = 0; j < JOBS; j++)); do slot_pid[j]=0; slot_base[j]=""; done
  while [ "$done_count" -lt "$n" ]; do
    for ((j = 0; j < JOBS; j++)); do
      if [ "${slot_pid[j]:-0}" != 0 ] && [ -e "${slot_base[j]}.done" ]; then
        wait "${slot_pid[j]}" 2>/dev/null
        _drain_suite_result "${slot_base[j]}"
        done_count=$((done_count + 1))
        slot_pid[j]=0
      fi
      if [ "${slot_pid[j]:-0}" = 0 ] && [ "$next" -lt "$n" ]; then
        base="$outdir/job$next"
        run_suite_bg "${POOL_PATHS[$next]}" "${POOL_LABELS[$next]}" "${POOL_INTERPS[$next]}" "$base" &
        slot_pid[j]=$!
        slot_base[j]="$base"
        next=$((next + 1))
      fi
    done
    [ "$done_count" -lt "$n" ] && sleep 0.2
  done
}

# --- Extension-Check als eigene Zeile in derselben Tabelle -----------------
run_extension_check() {
  local display="extension/npm run check" start end dur out status
  if [ ! -d "$EXTENSION_DIR" ] || ! command -v npm >/dev/null 2>&1; then
    echo "== SKIP  $display -- extension/ oder npm nicht gefunden =="
    NAMES+=("$display"); STATUSES+=("SKIP"); DURATIONS+=("-")
    REASONS+=("extension/ oder npm nicht gefunden")
    SKIP_COUNT=$((SKIP_COUNT + 1))   # zaehlt: npm ist herstellbar, kein Maschinenunterschied
    ZAEHLENDE_SKIPS+=("$display  extension/ oder npm nicht gefunden")
    return
  fi

  echo "== RUN   $display =="
  start=$(date +%s)
  if [ -n "$TIMEOUT_BIN" ]; then
    out="$(cd "$EXTENSION_DIR" && "$TIMEOUT_BIN" "$DEFAULT_TIMEOUT" npm run check 2>&1)"
  else
    out="$(cd "$EXTENSION_DIR" && npm run check 2>&1)"
  fi
  status=$?
  end=$(date +%s)
  dur="$((end - start))s"
  echo "$out"

  NAMES+=("$display"); DURATIONS+=("$dur")
  if [ "$status" -eq 0 ]; then
    STATUSES+=("PASS"); REASONS+=("")
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    STATUSES+=("FAIL"); REASONS+=("exit $status")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# --- app/ bauen, BEVOR die App-Suiten laufen -------------------------------
# Anlass (2026-08-15, Reviewer-Pass zur Kontextwache): run-all.sh baute app/
# nicht. Jede der rund dreissig test-app-*.sh-Suiten liest app/dist/test/*.mjs
# und ueberspringt sich per Exit 77, wenn dort nichts liegt -- ein fehlender
# oder veralteter Baustand machte also die halbe Testerfassung still wirkungslos:
# lauter SKIP-Zeilen, Exit-Code 0, und der geprueften Sache war nie jemand
# begegnet. Genau der Fall, den `run_suite` fuer Exit 77 schon einmal geloest
# hat, nur eine Ebene hoeher.
#
# Die Stufe baut selbst, wenn sie kann (npm und app/node_modules vorhanden);
# ein Fehlschlag des Baus ist ein FAIL wie jeder andere. Kann sie nicht bauen,
# entscheidet der Zustand von app/dist: ist er aktuell, ist das ein SKIP mit
# Grund; fehlt er oder ist er aelter als eine Quelldatei, ist es ein FAIL --
# denn dann pruefen die App-Suiten danach nichts, ohne es zu sagen.
APP_DIR="$REPO_ROOT/app"
APP_STEMPEL="$APP_DIR/dist/main/main.js"

app_dist_veraltet() {
  [ -f "$APP_STEMPEL" ] || { echo "app/dist fehlt"; return 0; }
  local neuer
  neuer="$(find "$APP_DIR/src" -type f -newer "$APP_STEMPEL" -print -quit 2>/dev/null)"
  [ -n "$neuer" ] && { echo "app/dist ist aelter als ${neuer#"$REPO_ROOT/"}"; return 0; }
  return 1
}

run_app_build() {
  local display="app/npm run build" start end dur out status grund
  if [ ! -d "$APP_DIR" ]; then
    echo "== SKIP  $display -- app/ nicht gefunden (dann gibt es auch keine App-Suiten) =="
    NAMES+=("$display"); STATUSES+=("SKIP"); DURATIONS+=("-")
    REASONS+=("app/ nicht gefunden -- ohne app/ gibt es auch keine App-Suiten")
    KEIN_GEGENSTAND_COUNT=$((KEIN_GEGENSTAND_COUNT + 1))
    return
  fi
  if ! command -v npm >/dev/null 2>&1 || [ ! -d "$APP_DIR/node_modules" ]; then
    grund="$(app_dist_veraltet)" && {
      echo "== FAIL  $display -- $grund, und hier laesst sich nicht bauen (npm oder app/node_modules fehlt) =="
      echo "         Alle test-app-*.sh-Suiten danach pruefen NICHTS. 'npm ci' in app/ hilft."
      NAMES+=("$display"); STATUSES+=("FAIL"); DURATIONS+=("-")
      REASONS+=("$grund -- npm/node_modules fehlt, App-Suiten pruefen nichts")
      FAIL_COUNT=$((FAIL_COUNT + 1))
      return
    }
    echo "== SKIP  $display -- npm oder app/node_modules fehlt, app/dist ist aber aktuell =="
    NAMES+=("$display"); STATUSES+=("SKIP"); DURATIONS+=("-")
    REASONS+=("nicht gebaut (npm/node_modules fehlt), app/dist ist aktuell")
    SKIP_COUNT=$((SKIP_COUNT + 1))   # zaehlt: 'npm ci' in app/ stellt das her
    ZAEHLENDE_SKIPS+=("$display  nicht gebaut (npm/node_modules fehlt), app/dist ist aktuell")
    return
  fi

  echo "== RUN   $display =="
  start=$(date +%s)
  if [ -n "$TIMEOUT_BIN" ]; then
    out="$(cd "$APP_DIR" && "$TIMEOUT_BIN" "$DEFAULT_TIMEOUT" npm run build 2>&1)"
  else
    out="$(cd "$APP_DIR" && npm run build 2>&1)"
  fi
  status=$?
  end=$(date +%s)
  dur="$((end - start))s"
  [ "$status" -eq 0 ] || echo "$out"

  NAMES+=("$display"); DURATIONS+=("$dur")
  if [ "$status" -eq 0 ]; then
    STATUSES+=("PASS"); REASONS+=("")
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    STATUSES+=("FAIL"); REASONS+=("exit $status -- ohne Bau pruefen die App-Suiten nichts")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

[ "$ZIEL" = "standard" ] && run_app_build

# --- mac/ bauen, BEVOR die Mac-Suiten laufen -------------------------------
# Dieselbe Stufe wie `app/npm run build`, eine Ebene weiter (2026-09-06,
# Auftrag 4.2): jede der dreiundzwanzig test-mac-*.sh-Suiten braucht
# `mac/build/Werkbank.app`. Ohne diese Zeile baute JEDE von ihnen die App
# notfalls selbst -- dreiundzwanzigmal derselbe `swift build`, im Parallel-Pool auch
# noch gleichzeitig auf dasselbe `.build`-Verzeichnis.
#
# Gebaut wird `--debug`: der Lauf prueft Verhalten, nicht Geschwindigkeit, und
# die Debug-Fassung ist im Betrieb schnell genug (mac/PLAN.md, „Offen aus
# Phase 1"). Auf Linux gibt es kein Swift-Toolkit fuer diese App -- dort ist
# das ein SKIP mit Grund, und `skip_reason_for` ueberspringt aus demselben
# Grund die Suiten selbst.
# DIE DREIUNDZWANZIGSTE IST test-mac-unterkante.sh (08.09.2026, Auftrag
# geometrie): sie prueft, dass der Schirm einer Kachel zeichengleich zu
# `capture-pane -p` ihres Panes ist -- die Zusage, an der die Fehler vom 08.09.
# haengen (eine Zeile Unterschied zwischen Buehne und Pane, und Zellen im
# Terminal, die es im Pane nicht gibt). Sie wird wie jede andere ueber den
# Glob unten eingesammelt und braucht keinen eigenen Eintrag; gemessen laeuft
# sie in rund vierzig Sekunden, also weit innerhalb der 300 s je Suite, wenn
# `mac/build` hier schon steht.
MAC_DIR="$REPO_ROOT/mac"

# Der Timeout der gewoehnlichen Suiten (300 s) reicht fuer einen Swift-Bau von
# Grund auf nicht: gemessen am 06.09. rund 100 s inkrementell, ein voller Bau
# mit SwiftTerm deutlich mehr.
MAC_BUILD_TIMEOUT=900

run_mac_build() {
  local display="mac/bin/bauen --debug" start end dur out status
  if [ ! -d "$MAC_DIR" ]; then
    echo "== SKIP  $display -- mac/ nicht gefunden (dann gibt es auch keine Mac-Suiten) =="
    NAMES+=("$display"); STATUSES+=("SKIP"); DURATIONS+=("-")
    REASONS+=("mac/ nicht gefunden -- ohne mac/ gibt es auch keine Mac-Suiten")
    KEIN_GEGENSTAND_COUNT=$((KEIN_GEGENSTAND_COUNT + 1))
    return
  fi
  if [ -n "$MAC_SKIP_GRUND" ]; then
    local st; st="$(skip_status_fuer "$MAC_SKIP_GRUND")"
    echo "== $st  $display -- $MAC_SKIP_GRUND =="
    NAMES+=("$display"); STATUSES+=("$st"); DURATIONS+=("-"); REASONS+=("$MAC_SKIP_GRUND")
    if [ "$st" = "FREMD" ]; then FREMD_COUNT=$((FREMD_COUNT + 1)); else SKIP_COUNT=$((SKIP_COUNT + 1)); ZAEHLENDE_SKIPS+=("$display  $MAC_SKIP_GRUND"); fi
    return
  fi

  echo "== RUN   $display =="
  start=$(date +%s)
  if [ -n "$TIMEOUT_BIN" ]; then
    out="$("$TIMEOUT_BIN" "$MAC_BUILD_TIMEOUT" "$MAC_DIR/bin/bauen" --debug 2>&1)"
  else
    out="$("$MAC_DIR/bin/bauen" --debug 2>&1)"
  fi
  status=$?
  end=$(date +%s)
  dur="$((end - start))s"
  [ "$status" -eq 0 ] || echo "$out"

  NAMES+=("$display"); DURATIONS+=("$dur")
  if [ "$status" -eq 0 ]; then
    STATUSES+=("PASS"); REASONS+=("")
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    STATUSES+=("FAIL"); REASONS+=("exit $status -- ohne Bau pruefen die Mac-Suiten nichts")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

[ "$ZIEL" = "standard" ] && run_mac_build

# --- Suiten einsammeln, auswaehlen, verteilen -------------------------------
# Reihenfolge je Suite: (1) suite_ausgewaehlt? -- sonst ganz uebergangen und nur
# gezaehlt (fuer die VOLLSTAENDIG-Zeile unten). (2) ist_parallel_sicher? -- ja:
# in den Pool, sonst: einzeln, wie bisher, mit `run_suite`.
declare -a POOL_PATHS POOL_LABELS POOL_INTERPS
declare -a MAC_POOL_PATHS MAC_POOL_LABELS MAC_POOL_INTERPS
SUITEN_ENTDECKT=0
SUITEN_NICHT_AUSGEWAEHLT=0

# --- Die Mac-Suiten sind eine eigene Klasse (2026-09-06, Auftrag 4.2) -------
# Jede test-mac-*.sh startet einen ganzen Electron-Kern UND die Mac-App -- zwei
# Prozessbaeume, wo eine gewoehnliche Suite ein paar Shell-Aufrufe macht.
#
# GEMESSEN am 06.09.2026 auf dieser Maschine (M5 Pro, 48 GiB), 21 Mac-Suiten,
# jeweils der ganze Block von `run-all.sh --nur test-mac-`:
#   --mac-jobs 8   109 s, aber test-mac-fernsitzung.sh rot ("die Sitzung ist
#                  nicht gestartet") und einzeln wieder gruen -- eine Frist,
#                  die unter Last reisst, kein Fehler in der Sache.
#   --mac-jobs 4   138 s und 141 s in zwei Laeufen, beide vollstaendig gruen.
#   --mac-jobs 2   243 s, gruen.
# Was hier begrenzt, sind also die Zeitfristen der Suiten (15 s auf die
# Verbindung zum Kern, 15 s auf den ersten Terminaltext) und nicht der
# Arbeitsspeicher -- deshalb steht die Vorgabe unten als gemessene Zahl und
# nicht als Rechnung ueber freien Speicher.
#
# Sie laufen deshalb in einem ZWEITEN Pool mit eigener Parallelitaet, NACH dem
# ersten: so bekommen sie die Maschine fuer sich, statt mit dreissig
# gewoehnlichen Suiten um dieselben Kerne zu streiten. `--jobs` gilt weiter
# fuer den ersten Pool; `--mac-jobs` setzt diesen hier.
ist_mac_suite() {
  case "$(basename "$1")" in test-mac-*.sh) return 0 ;; *) return 1 ;; esac
}

# --- Suiten, die ein GELADENES lokales Modell brauchen (2026-09-21) ---------
# Eine Suite gehoert hierher, wenn ihre Voraussetzung ein laufender Modell-
# server mit geladenen Gewichten ist -- also gerade NICHT, wenn sie das Modell
# nur per Attrappe, Registry-Eintrag oder Umgebungsvariable erwaehnt. Der
# Unterschied ist der ganze Punkt: auf dem Mac ist ein lokales Modell
# herstellbar, das Laden kostet aber Speicher und muss mit `wb-belegung` und
# der laufenden Werkbank-Sitzung abgestimmt sein. So eine Suite darf deshalb
# weder im Alltagslauf still uebersprungen werden noch ihn rot faerben: sie
# bekommt ein eigenes Ziel, das man mit geladenem Modell faehrt.
#
# Die Liste steht hier als NAMEN und nicht als Grep ueber den Quelltext: ein
# Grep auf "ollama"/"mlx" trifft rund siebzig Suiten, von denen fast alle nur
# Attrappen benutzen (gemessen 2026-09-21) -- eine Heuristik, die dreiundsechzig
# Suiten falsch einsortiert, ist keine.
ist_lokal_modell_suite() {
  case "$(basename "$1")" in
    test-contradiction-queue.sh) return 0 ;;   # braucht Ollama auf 127.0.0.1:11434 MIT Modell
    *) return 1 ;;
  esac
}

LOKAL_MODELL_UEBERGANGEN=0

sammle_suite() {   # $1 = Pfad, $2 = Anzeige-Praefix, $3 = Interpreter
  local f="$1" label="$2" interp="$3"
  [ -f "$f" ] || return 0
  SUITEN_ENTDECKT=$((SUITEN_ENTDECKT + 1))
  # Das Ziel entscheidet VOR jeder anderen Auswahl: im Standardlauf bleiben die
  # Modell-Suiten aussen vor (und werden unten laut gezaehlt), im Ziel
  # `lokal-modell` laufen ausschliesslich sie.
  if ist_lokal_modell_suite "$f"; then
    if [ "$ZIEL" != "lokal-modell" ]; then
      LOKAL_MODELL_UEBERGANGEN=$((LOKAL_MODELL_UEBERGANGEN + 1))
      SUITEN_NICHT_AUSGEWAEHLT=$((SUITEN_NICHT_AUSGEWAEHLT + 1))
      return 0
    fi
  elif [ "$ZIEL" = "lokal-modell" ]; then
    SUITEN_NICHT_AUSGEWAEHLT=$((SUITEN_NICHT_AUSGEWAEHLT + 1))
    return 0
  fi
  if ! suite_ausgewaehlt "$f"; then
    SUITEN_NICHT_AUSGEWAEHLT=$((SUITEN_NICHT_AUSGEWAEHLT + 1))
    return 0
  fi
  if [ "$SEQUENZIELL" -eq 1 ] || ! ist_parallel_sicher "$f"; then
    run_suite "$f" "$label" "$interp"
  elif ist_mac_suite "$f"; then
    MAC_POOL_PATHS+=("$f"); MAC_POOL_LABELS+=("$label"); MAC_POOL_INTERPS+=("$interp")
  else
    POOL_PATHS+=("$f"); POOL_LABELS+=("$label"); POOL_INTERPS+=("$interp")
  fi
}

for f in "$SCRIPT_DIR"/test-*.sh; do sammle_suite "$f" "shell/tests" bash; done
for f in "$SCRIPT_DIR"/test-*.py; do sammle_suite "$f" "shell/tests" python3; done

# Der Betriebslauf (2026-08-04): kein 'test-*', prueft kein einzelnes Werkzeug,
# sondern die Kette der Handgriffe -- Session anlegen, Worker-Tab, Layoutwechsel,
# Ueberlauf, Schliessen, Loeschen, Verwaisung -- gegen wb-doctor. Isoliert wie
# jede andere Suite (eigener tmux-Socket, eigenes HOME), darum genauso durch
# `sammle_suite` statt fest sequenziell.
sammle_suite "$SCRIPT_DIR/betriebslauf.sh" "shell/tests" bash
sammle_suite "$SCRIPT_DIR/betriebslauf2.sh" "shell/tests" bash

if [ -d "$HOOKS_TESTS_DIR" ]; then
  for f in "$HOOKS_TESTS_DIR"/test-*.sh; do sammle_suite "$f" "hooks/tests" bash; done
else
  echo "== SKIP  hooks/tests -- Verzeichnis $HOOKS_TESTS_DIR nicht gefunden =="
fi

if [ "${#POOL_PATHS[@]}" -gt 0 ]; then
  echo
  echo "== Pool: ${#POOL_PATHS[@]} Suite(n) auf bis zu $JOBS gleichzeitig =="
  POOL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wb-run-all-pool.XXXXXX")"
  run_pool "$POOL_DIR"
  # KEIN rm -rf hier mehr (2026-08-22, siehe unten am Skriptende): FAIL_COUNT
  # steht erst fest, nachdem wb-consistency und der Extension-Check gelaufen
  # sind -- ob dieser Pool-Lauf aufgehoben wird, entscheidet sich also am
  # Skriptende, nicht hier.
fi

# Der zweite Pool: die Mac-Suiten, gedrosselt und fuer sich (siehe
# `ist_mac_suite`). Er benutzt dieselbe `run_pool`-Mechanik ueber dieselben
# Arrays -- sie werden dafuer umgehaengt, statt eine zweite Fassung derselben
# Schleife zu pflegen.
if [ "${#MAC_POOL_PATHS[@]}" -gt 0 ]; then
  echo
  echo "== Mac-Pool: ${#MAC_POOL_PATHS[@]} Suite(n) auf bis zu $MAC_JOBS gleichzeitig =="
  POOL_PATHS=("${MAC_POOL_PATHS[@]}"); POOL_LABELS=("${MAC_POOL_LABELS[@]}"); POOL_INTERPS=("${MAC_POOL_INTERPS[@]}")
  JOBS="$MAC_JOBS"
  MAC_POOL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wb-run-all-macpool.XXXXXX")"
  run_pool "$MAC_POOL_DIR"
  # Beide Poollaeufe landen in EINEM Verzeichnis: `pool_aufheben_oder_loeschen`
  # am Skriptende hebt bei einem roten Lauf genau eines auf, und zwei Aufrufe
  # haetten das erste durch das zweite ersetzt. Die Namen bekommen ein
  # Praefix, weil beide Laeufe bei job0 anfangen.
  if [ -n "${POOL_DIR:-}" ] && [ -d "${POOL_DIR:-}" ]; then
    for f in "$MAC_POOL_DIR"/*; do
      [ -e "$f" ] && mv "$f" "$POOL_DIR/mac-$(basename "$f")" 2>/dev/null
    done
    rmdir "$MAC_POOL_DIR" 2>/dev/null
  else
    POOL_DIR="$MAC_POOL_DIR"
  fi
  MAC_POOL_DIR=""
fi

# --- wb-consistency gegen die lebende Maschine -----------------------------
# Siehe Kopfkommentar zur Isolations-Ausnahme. Laeuft ohne --base/--config,
# also gegen ~/.claude & Co dieser Maschine, nicht gegen eine Test-Fixture.
# --repo "$REPO_ROOT": wb-consistency vergleicht sonst gegen seinen fest
# verdrahteten Vorgabewert ~/AI/claude-workbench (Befund 2026-08-21) -- fuer
# einen Lauf aus einem anderen Worktree (wie diesem hier) meldete das die
# frisch ausgerollten Werkzeuge faelschlich als KOPIE-EIGENMAECHTIG, nur weil
# der Hauptbaum selbst noch nicht auf demselben Stand war. run-all.sh soll
# gegen SEINEN EIGENEN Baum pruefen, nicht gegen einen anderen, den es nie
# anfassen darf.
#
# NACHTRAG (2026-08-22): den EIGENEN Baum zu treffen war nur die halbe Miete
# -- ist dieser eigene Baum selbst ein Worker-Worktree, kennt seine Branch-
# Historie nicht jeden Stand, den der Hauptbaum inzwischen unabhaengig
# ausgerollt hat, und derselbe KOPIE-EIGENMAECHTIG-Fund kam trotzdem zurueck.
# Behoben ist das jetzt IN wb-consistency selbst (ist_worktree(),
# kopie_vergleiche()) -- diese Zeile hier bleibt unveraendert richtig, das
# Werkzeug dahinter weiss inzwischen nur mehr.
if [ "$ZIEL" != "standard" ]; then
  :   # ein Ziel prueft seine Suiten, nicht die Maschinenkonsistenz
elif [ -f "$WB_CONSISTENCY" ]; then
  run_suite "$WB_CONSISTENCY" "shell" python3 --repo "$REPO_ROOT"
else
  echo "== SKIP  shell/wb-consistency -- $WB_CONSISTENCY nicht gefunden =="
fi

if [ "$SHELL_ONLY" -eq 0 ] && [ "$ZIEL" = "standard" ]; then
  run_extension_check
fi

# --- Liegengebliebene Test-Sockets ------------------------------------------
# Ein tmux-Server raeumt seine Socketdatei beim Beenden nicht ab. Nach zwei
# vollen Laeufen lagen am 2026-08-04 auf host2 33 tote Sockets, auf dem Mac 3 —
# und vorher schon einmal 49, die von Hand weggeraeumt wurden. `wb-hygiene`
# MELDET sie, entfernt sie aber nicht; der Auslaeser fehlte, nicht die
# Faehigkeit. Hier ist er richtig: Der Lauf weiss, dass er die Suiten gerade
# beendet hat. Angefasst wird ausschliesslich, was auf wbtest*/wbprobe* passt
# UND auf dessen Socket kein Server mehr antwortet — ein lebender Server bleibt
# unberuehrt, und 'default' faellt schon durch das Namensmuster heraus.
prune_dead_test_sockets() {
  local sockdir="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
  [ -d "$sockdir" ] || return 0
  local sock tot=0 lebendig=0
  for sock in "$sockdir"/wbtest* "$sockdir"/wbprobe*; do
    [ -S "$sock" ] || continue
    if tmux -S "$sock" list-sessions >/dev/null 2>&1; then
      lebendig=$((lebendig + 1))
    else
      rm -f "$sock" && tot=$((tot + 1))
    fi
  done
  if [ "$tot" -gt 0 ] || [ "$lebendig" -gt 0 ]; then
    echo
    echo "Test-Sockets: $tot tote entfernt, $lebendig lebende unberuehrt gelassen."
  fi
}
prune_dead_test_sockets

# --- Tabelle ----------------------------------------------------------------
echo
echo "======================================================================"
# --- Bestaetigungslauf: ist eine rote Suite wirklich rot? -------------------
# ANLASS 2026-09-04: zwei volle Laeufe hintereinander meldeten je zwei bis drei
# rote Suiten -- und JEDES Mal andere. Einzeln nachgefahren war jede einzelne
# gruen. Die Ursache ist immer dieselbe Bauart: eine Zusage liest einen Wert,
# waehrend er sich noch bewegt, und unter achtfacher Parallelitaet dauert die
# Bewegung laenger als die feste Wartezeit davor. Ein roter Punkt aus dem
# Gesamtlauf ist damit ohne Nacharbeit nicht zu deuten -- und die Nacharbeit
# hat bis heute ein Mensch von Hand gemacht, jedes Mal.
#
# Das macht der Laeufer jetzt selbst: jede gefallene Suite laeuft danach EINMAL
# allein, ohne Parallelitaet. Bleibt sie rot, heisst sie "bestaetigt rot" und
# zaehlt weiter als Fehlschlag. Wird sie allein gruen, heisst sie "nur unter
# Last rot" und zaehlt in einer eigenen Spalte -- sie ist damit nicht erledigt,
# sondern benannt: eine Zusage, die auf Wartezeit statt auf einen Zustand
# baut, gehoert repariert. Aber sie stellt nicht mehr den ganzen Lauf rot.
#
# Gedeckelt auf $BESTAETIGEN_MAX Suiten: bei einem wirklich kaputten Baum
# faellt vieles, und dann ist ein serieller Nachlauf ueber dreissig Suiten
# keine Hilfe, sondern eine zweite Wartezeit. Abschaltbar mit
# --ohne-bestaetigung.
NURLAST_COUNT=0
if [ "$BESTAETIGEN" = "1" ] && [ "$FAIL_COUNT" -gt 0 ] && [ "$FAIL_COUNT" -le "$BESTAETIGEN_MAX" ]; then
  echo
  echo "== Bestaetigungslauf: $FAIL_COUNT rote Suite(n) einzeln, ohne Parallelitaet =="
  for i in "${!NAMES[@]}"; do
    [ "${STATUSES[$i]}" = "FAIL" ] || continue
    _d="${NAMES[$i]}"
    case "$_d" in
      *.sh) _interp=bash ;;
      *.py) _interp=python3 ;;
      *) continue ;;   # "app/npm run build" und Geschwister haben keinen Pfad
    esac
    _p="$REPO_ROOT/$_d"
    [ -f "$_p" ] || continue
    _s=0
    if [ -n "$TIMEOUT_BIN" ]; then
      "$TIMEOUT_BIN" "$DEFAULT_TIMEOUT" "$_interp" "$_p" >/dev/null 2>&1 || _s=$?
    else
      "$_interp" "$_p" >/dev/null 2>&1 || _s=$?
    fi
    if [ "$_s" -eq 0 ]; then
      STATUSES[$i]="LAST"
      REASONS[$i]="${REASONS[$i]} -- einzeln GRUEN, nur unter Parallelitaet rot"
      FAIL_COUNT=$((FAIL_COUNT - 1))
      NURLAST_COUNT=$((NURLAST_COUNT + 1))
      echo "  nur unter Last rot:  $_d"
    else
      REASONS[$i]="${REASONS[$i]} -- einzeln BESTAETIGT (exit $_s)"
      echo "  bestaetigt rot:      $_d"
    fi
  done
  echo
fi

printf '%-42s %-6s %-8s %s\n' "Suite" "Status" "Dauer" "Grund"
printf '%-42s %-6s %-8s %s\n' "------------------------------------------" "------" "--------" "-----"
for i in "${!NAMES[@]}"; do
  printf '%-42s %-6s %-8s %s\n' "${NAMES[$i]}" "${STATUSES[$i]}" "${DURATIONS[$i]}" "${REASONS[$i]}"
done
echo "======================================================================"
# Die Schlusszeile beginnt IMMER mit "PASS: n  FAIL: n  SKIP: n" -- genau in
# dieser Reihenfolge und mit genau zwei Leerzeichen, weil shell/wb-testsuite-run
# sie so liest ('^PASS: [0-9]+  FAIL: [0-9]+  SKIP: [0-9]+'). Alles Weitere
# haengt HINTEN an. (Seit dem Einbau von NUR-UNTER-LAST am 21.09. stand die
# Zahl zwischen FAIL und SKIP und liess das Muster ins Leere greifen, sobald
# eine Suite nur unter Last rot war -- deshalb hier die feste Reihenfolge.)
_schluss="PASS: $PASS_COUNT  FAIL: $FAIL_COUNT  SKIP: $SKIP_COUNT"
[ "${NURLAST_COUNT:-0}" -gt 0 ] && _schluss="$_schluss  NUR-UNTER-LAST: $NURLAST_COUNT"
_schluss="$_schluss  nicht auf dieser Maschine: $FREMD_COUNT"
[ "$KEIN_GEGENSTAND_COUNT" -gt 0 ] && _schluss="$_schluss  ohne Gegenstand in diesem Baum: $KEIN_GEGENSTAND_COUNT"
echo "$_schluss  (gesamt ${#NAMES[@]})"

# --- Ergebnisprotokoll, damit ein Lauf nicht zweimal noetig ist -------------
# ANLASS 2026-08-20: ein voller Lauf dauert rund zehn Minuten und meldete am
# Ende nur "PASS: 221  FAIL: 2". WELCHE zwei, stand nirgends -- die .meta-Dateien
# je Suite liegen im Pool-Verzeichnis, und das wird direkt nach dem Pool-Lauf
# mit `rm -rf` entfernt. Wer die Namen wollte, musste den ganzen Lauf
# wiederholen und die Ausgabe diesmal vollstaendig auffangen; die
# Zeitdatei daneben haelt ausschliesslich Laufzeiten fest, keine Ergebnisse.
# Das Protokoll unten kostet nichts: Namen, Status, Dauer und Grund stehen
# ohnehin schon in den Arrays, aus denen die Tabelle darueber gedruckt wird.
ERGEBNIS_FILE="$HOME/.local/state/wb-run-all-tests.ergebnis.tsv"
if mkdir -p "$(dirname "$ERGEBNIS_FILE")" 2>/dev/null; then
  {
    printf '# Lauf beendet: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf '# PASS=%s FAIL=%s SKIP=%s FREMD=%s OHNE_GEGENSTAND=%s gesamt=%s\n' \
      "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$FREMD_COUNT" "$KEIN_GEGENSTAND_COUNT" "${#NAMES[@]}"
    printf '# suite\tstatus\tdauer\tgrund\n'
    for i in "${!NAMES[@]}"; do
      printf '%s\t%s\t%s\t%s\n' \
        "${NAMES[$i]}" "${STATUSES[$i]}" "${DURATIONS[$i]}" "${REASONS[$i]}"
    done
  } > "$ERGEBNIS_FILE" 2>/dev/null || true
  if [ "$FAIL_COUNT" -gt 0 ]; then
    echo
    echo "Die $FAIL_COUNT fehlgeschlagene(n) Suite(n) im Klartext:"
    for i in "${!NAMES[@]}"; do
      [ "${STATUSES[$i]}" = "FAIL" ] && printf '  %s  (%s)  %s\n' \
        "${NAMES[$i]}" "${DURATIONS[$i]}" "${REASONS[$i]}"
    done
    echo "Vollstaendiges Protokoll: $ERGEBNIS_FILE"
  fi
  if [ "$SKIP_COUNT" -gt 0 ]; then
    echo
    echo "Die $SKIP_COUNT uebersprungene(n) Suite(n), die wie ein Fehlschlag zaehlen:"
    for z in "${ZAEHLENDE_SKIPS[@]}"; do printf '  %s\n' "$z"; done
    echo "  Jede davon ist auf DIESER Maschine herstellbar -- ein fehlendes Werkzeug,"
    echo "  ein nicht gebautes Paket, ein nicht geladenes Modell. Gehoert eine davon"
    echo "  wirklich einer anderen Maschine, bekommt ihre Skip-Zeile das Kennzeichen:"
    echo "  echo \"UEBERSPRUNGEN: nicht auf dieser Maschine: <Grund>\"; exit 77"
  fi
  if [ "$FREMD_COUNT" -gt 0 ]; then
    echo
    echo "Nicht auf dieser Maschine ($FREMD_COUNT) -- zaehlt nicht gegen den Exit-Code:"
    for i in "${!NAMES[@]}"; do
      [ "${STATUSES[$i]}" = "FREMD" ] && printf '  %s  %s\n' "${NAMES[$i]}" "${REASONS[$i]}"
    done
  fi
  if [ "${NURLAST_COUNT:-0}" -gt 0 ]; then
    echo
    echo "Nur unter Parallelitaet rot, einzeln gruen -- erledigt ist das NICHT:"
    for i in "${!NAMES[@]}"; do
      [ "${STATUSES[$i]}" = "LAST" ] && printf '  %s  (%s)\n' "${NAMES[$i]}" "${DURATIONS[$i]}"
    done
    echo "  Diese Suiten lesen einen Wert, waehrend er sich noch bewegt. Der Fix ist"
    echo "  immer derselbe: auf den Zustand warten statt auf eine feste Zeit, mit"
    echo "  einer Frist, deren Ablauf ein eigener, lauter Fehlschlag ist."
  fi
fi

# --- Die AUSGABE eines roten Laufs ueberlebt ihn --------------------------
# ANLASS 2026-08-22: das Ergebnisprotokoll oben (seit 20.08.) nennt die NAMEN
# der roten Suiten, aber nicht mehr, WAS sie ausgegeben haben -- die .out-
# Dateien je Suite lagen im Pool-Verzeichnis, und das wurde bisher sofort nach
# dem Pool-Lauf mit `rm -rf` entfernt, lange bevor hier feststeht, ob der Lauf
# insgesamt rot war. Wer nachsehen wollte, WARUM eine unter Parallelitaet
# gefallene Suite fiel, musste den ganzen (zehnminuetigen) Lauf wiederholen --
# ein eigener xargs-Nachbau, nur um an Einzel-Logs zu kommen, die schon einmal
# da waren, ist genau das Werkzeug, das sich gegen seinen Benutzer stellt.
#
# Zwei Grenzen dabei: ein GRUENER Lauf haeuft nichts an (246 Suiten mal jede
# Woche waere Muell) -- sein Pool-Verzeichnis wird weiterhin geloescht. Und
# es liegt IMMER nur der letzte rote Lauf auf, nie mehrere gleichzeitig --
# derselbe feste Pfad wird beim naechsten roten Lauf ueberschrieben, statt
# sich ueber Wochen anzusammeln. Wer mehr braucht (einen roten Lauf vom
# letzten Dienstag), muss ihn wiederholen; das ist der bewusste Kompromiss,
# nicht die Luecke, die dieser Auftrag schliesst.
#
# Je Suite liegt <job-name>.out (die volle Ausgabe) neben <job-name>.meta
# (Name/Status/Dauer/Grund, Tab-getrennt) -- eine bestimmte Suite findet sich
# darin ueber `grep -l "<suitenname>" *.meta`.
#
# Eigene Funktion statt Inline-Code, GENAU wie is_worktree() in
# betriebslauf.sh/betriebslauf2.sh -- test-run-all-pool-ueberlebt.sh zieht sie
# woertlich per sed und prueft sie gegen synthetische Pool-Verzeichnisse,
# statt einen ganzen (zehnminuetigen) Lauf zweimal zu wiederholen.
pool_aufheben_oder_loeschen() {   # <pool_dir> <fail_count>
  local pool_dir="$1" fail_count="$2"
  [ -n "$pool_dir" ] && [ -d "$pool_dir" ] || return 0
  local roter_lauf_dir="$HOME/.local/state/wb-run-all-letzter-roter-lauf"
  if [ "$fail_count" -gt 0 ]; then
    rm -rf "$roter_lauf_dir" 2>/dev/null
    mkdir -p "$(dirname "$roter_lauf_dir")" 2>/dev/null
    if mv "$pool_dir" "$roter_lauf_dir" 2>/dev/null; then
      echo
      echo "Ausgabe der Pool-Suiten dieses roten Laufs aufgehoben: $roter_lauf_dir"
      echo "  (je Suite <job>.out + <job>.meta -- eine bestimmte Suite darin finden: grep -l \"<suitenname>\" $roter_lauf_dir/*.meta)"
    else
      echo "WARNUNG: Pool-Ausgabe konnte nicht nach $roter_lauf_dir verschoben werden -- $pool_dir bleibt liegen." >&2
    fi
  else
    rm -rf "$pool_dir" 2>/dev/null
  fi
}
# --- Ein zaehlender Skip ist ein Fehlschlag (2026-09-21, Entscheidung ai-78) -
# Addiert wird hier und nicht oben: die Tabelle und die Schlusszeile sollen SKIP
# weiterhin getrennt ausweisen -- wer nur die Zahl sieht, soll wissen, ob der
# Lauf an einem echten Fehlschlag haengt oder an einer Voraussetzung, die
# niemand hergestellt hat. Fuer alles danach (Aufheben der Pool-Ausgabe,
# Exit-Code) ist ein uebersprungener Punkt dagegen dasselbe wie ein roter:
# beides heisst, dass diese Zusage in diesem Lauf NICHT geprueft wurde.
if [ "$SKIP_COUNT" -gt 0 ]; then
  echo
  echo "$SKIP_COUNT uebersprungene(r) Punkt(e) zaehlen wie Fehlschlaege -- dieser Lauf ist rot."
  FAIL_COUNT=$((FAIL_COUNT + SKIP_COUNT))
fi

pool_aufheben_oder_loeschen "${POOL_DIR:-}" "$FAIL_COUNT"
POOL_DIR=""

# --- Vollstaendigkeit, maschinenlesbar UND laut -----------------------------
# Ergaenzung des Nutzers (2026-08-19, waehrend dieses Auftrags): "eine gruene
# Zeile, die nach 'alles gut' aussieht, obwohl nur zwoelf von 195 liefen, waere
# genau die Art stiller Fehlmeldung, die wir heute schon zweimal hatten." Die
# Auswahl (--nur/--schnell/--geaendert) ist fuer die Arbeit ZWISCHENDURCH da,
# nie fuer einen Push nach main -- dort laeuft immer der volle Lauf. Diese
# Zeile ist der einzige Ort, an dem "voll oder Teil" fuer eine spaetere
# Maschine (Push-Weg, wb-testsuite-run) UND fuer einen Menschen im Terminal
# gleichzeitig steht -- Parsing-Anker `^VOLLSTAENDIG:`, demselben Muster wie
# die PASS/FAIL/SKIP-Zeile, die wb-testsuite-run schon per grep liest.
TEILLAUF=0
[ -n "$NUR" ] && TEILLAUF=1
[ "$SCHNELL" -eq 1 ] && TEILLAUF=1
[ "$GEAENDERT" -eq 1 ] && TEILLAUF=1
[ "$ZIEL" != "standard" ] && TEILLAUF=1

# --- Lief das Ziel "lokal-modell" mit? (2026-09-21) -------------------------
# Eigene Zeile, weil ein Standardlauf diese Suiten bewusst NICHT faehrt: sie
# brauchen ein geladenes Modell, und das kostet Speicher, den ein Testlauf sich
# nicht selbst nehmen darf (die Maschine stand deswegen am 21.08. und am
# 29.08.). Damit das nicht zu einer stillen Luecke wird, sagt der Laeufer in
# jedem Lauf, ob das Ziel gelaufen ist -- und wird laut, wenn die Aenderungen
# dieses Baums genau die Pfade betreffen, die diese Suiten pruefen.
if [ "$ZIEL" = "lokal-modell" ]; then
  echo "ZIEL lokal-modell: ja (${#NAMES[@]} Punkt(e) in diesem Lauf)"
else
  echo "ZIEL lokal-modell: nein ($LOKAL_MODELL_UEBERGANGEN Suite(n) nicht gelaufen -- 'run-all.sh --ziel lokal-modell' mit geladenem Modell)"
  if [ "$LOKAL_MODELL_UEBERGANGEN" -gt 0 ]; then
    _lm_ref="$GEAENDERT_REF"
    if [ -z "$_lm_ref" ]; then
      _lm_ref="$(git -C "$REPO_ROOT" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@origin/@')"
      [ -z "$_lm_ref" ] && _lm_ref="main"
    fi
    _lm_treffer="$( { git -C "$REPO_ROOT" diff --name-only "$_lm_ref"...HEAD 2>/dev/null
                      git -C "$REPO_ROOT" diff --name-only HEAD 2>/dev/null
                      git -C "$REPO_ROOT" status --porcelain 2>/dev/null | awk '{print $2}'
                    } | sort -u | grep -E '^shell/(wb-enginex-server|wb-mlx-server|wb-enginey-server|pi-worker|models\.default\.json|wb-registry-sync)$' )"
    if [ -n "$_lm_treffer" ]; then
      echo
      echo "######################################################################"
      echo "# ZIEL lokal-modell IST NOETIG: dieser Baum aendert Pfade der lokalen Modelle."
      printf '#   %s\n' $_lm_treffer
      echo "# Vor einem Push: 'shell/tests/run-all.sh --ziel lokal-modell' mit geladenem"
      echo "# Modell fahren (vorher wb-belegung fragen und die Werkbank-Sitzung abstimmen)."
      echo "######################################################################"
    fi
  fi
fi

if [ "$TEILLAUF" -eq 1 ]; then
  echo "VOLLSTAENDIG: nein ($SUITEN_NICHT_AUSGEWAEHLT von $SUITEN_ENTDECKT Suiten NICHT ausgewaehlt -- --nur/--schnell/--geaendert/--ziel aktiv)"
  echo
  echo "######################################################################"
  echo "# TEILLAUF -- nicht die volle Suite. $SUITEN_NICHT_AUSGEWAEHLT von $SUITEN_ENTDECKT Suiten liefen NICHT mit."
  echo "# Vor einem Push nach main: shell/tests/run-all.sh OHNE --nur/--schnell/--geaendert."
  echo "######################################################################"
else
  # "ja" heisst: alles gelaufen, was zu DIESEM Ziel gehoert. Die Modell-Suiten
  # stehen daneben mit ihrer Zahl, damit die Zeile niemanden glauben laesst,
  # dieser Lauf habe auch sie geprueft.
  if [ "$LOKAL_MODELL_UEBERGANGEN" -gt 0 ]; then
    echo "VOLLSTAENDIG: ja ($((SUITEN_ENTDECKT - LOKAL_MODELL_UEBERGANGEN)) von $SUITEN_ENTDECKT Suiten; die $LOKAL_MODELL_UEBERGANGEN mit lokalem Modell haben ihr eigenes Ziel)"
  else
    echo "VOLLSTAENDIG: ja (alle $SUITEN_ENTDECKT entdeckten Suiten ausgewaehlt)"
  fi
fi

# --- Zeitverlauf fuer --schnell fortschreiben --------------------------------
# Alte Eintraege fuer Suiten, die DIESES Mal nicht liefen (z.B. --nur/--schnell/
# --geaendert), bleiben stehen -- sonst wuerde ein Teillauf die Historie der
# Suiten loeschen, die er gar nicht angefasst hat.
if [ -s "$THIS_RUN_TIMINGS" ]; then
  TIMING_NEU="$(mktemp "${TMPDIR:-/tmp}/wb-run-all-timings-neu.XXXXXX")"
  if [ -f "$TIMING_FILE" ]; then
    awk -F'\t' 'NR==FNR{lief[$1]=1; next} !($1 in lief)' "$THIS_RUN_TIMINGS" "$TIMING_FILE" > "$TIMING_NEU"
  fi
  cat "$THIS_RUN_TIMINGS" >> "$TIMING_NEU"
  sort -o "$TIMING_NEU" "$TIMING_NEU"
  mkdir -p "$(dirname "$TIMING_FILE")"
  mv "$TIMING_NEU" "$TIMING_FILE"
fi

# Exit 0 nur, wenn AUCH keine Suite "nur unter Last rot" war (2026-09-21,
# Auflage des Nutzers: ein Gesamtlauf hat kein einziges Rot, und eine Suite, die
# im Pool rot ist und einzeln gruen, IST rot). Bis hierher zaehlte sie nicht
# mit: der Bestaetigungslauf nahm sie aus FAIL_COUNT heraus und legte sie in
# NURLAST_COUNT, der Lauf endete mit 0, und die Statuszeile meldete Gruen --
# waehrend die Tabelle darueber "erledigt ist das NICHT" schrieb. Genau so
# rutschte ein bekannter Wackler ueber Wochen durch.
[ "$FAIL_COUNT" -eq 0 ] && [ "${NURLAST_COUNT:-0}" -eq 0 ]
