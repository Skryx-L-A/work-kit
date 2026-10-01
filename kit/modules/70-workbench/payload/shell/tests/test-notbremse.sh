#!/usr/bin/env bash
# test-notbremse.sh -- die Zusagen der Notabschaltung (shell/wb-notbremse).
#
# ANLASS: Am 21.08.2026 hat ein Worker einen MLX-Server OHNE `wb-belegung`
# gestartet und dabei versehentlich ein zweites Modell nachgeladen. Der freie
# Speicher fiel auf 1 von 48 GiB, und es gab nichts, was das gestoppt haette --
# der Nutzer musste selbst eingreifen. Sein Auftrag daraufhin, woertlich: "baue ein
# sicherheitsmechanismus ein das bei solchen tests die lokalen modelle automatisch
# beendet werden wenn unter 1gb freier speicher insgesammt verfuegbar ist."
#
# DIE ZUSAGEN, die hier wirklich hergestellt und gemessen werden:
#   1  Ueber der Schwelle passiert NICHTS -- auch wenn ein Modell laeuft.
#   2  Unter der Schwelle wird der Modellprozess gefunden und WIRKLICH beendet,
#      und danach wird NACHGESEHEN, nicht angenommen.
#   3  Die weisse Liste haelt: ein 'ollama serve', ein 'whisper-server' und ein
#      beliebiger fremder Prozess werden nie angefasst, auch nicht unter der
#      Schwelle.
#   4  Sie greift ohne jede Buchung -- der Fall, gegen den sie gebaut ist, war ein
#      Start am Buch VORBEI. Es wird hier nie ein Buch angelegt oder gelesen.
#   5  Sie sagt laut, was sie getan hat: Protokolldatei, Merkdatei mit dem letzten
#      Eingriff, und eine Meldung in jede tmux-Sitzung ihres Servers.
#   6  Bei FALLENDEM Speicher greift sie im Takt, nicht erst hinterher: die
#      Schwelle steht fest, die gemeldete Zahl faellt waehrend die Wache laeuft.
#   7  Ohne messbaren freien Speicher greift sie NICHT. Eine Bremse, die bei
#      fehlender Messung zieht, beendet beim ersten kaputten PATH alle Modelle.
#   8  Die Wache endet von selbst, sobald kein Modell mehr laeuft (stehende Regel:
#      kein Prozess laeuft auf Vorrat).
#   9  EINE einzelne Abtastung unter der Schwelle beendet nichts. Im echten Lauf
#      vom 21.08. lagen zwei Messungen derselben Sekunde 7 GiB auseinander; wer
#      auf eine davon hin toetet, toetet frueher oder spaeter ein gesundes Modell.
#      Erst zwei aufeinanderfolgende Abtastungen zaehlen als Lage.
#  10  Nach einem Eingriff steht die Belegung des beendeten Servers nicht mehr im
#      Buch. Im echten Lauf blieben 25,2 GiB stehen, obwohl der Speicher frei war
#      -- die naechste Anfrage waere an einer Belegung gescheitert, die niemand
#      mehr haelt.
#  11  Der freie Speicher hat GENAU EINE Quelle: check-resources (Auftrag,
#      21.08.2026, nach Befund 2 des Pruefpasses ~/.pi-workers/results/
#      hafenmeister/20260821-045339.md -- eine zweite, eigene Formel war die
#      Verdopplung, die den Befund erst erzeugt hat). Antwortet es gueltig,
#      zaehlt SEINE Zahl. Fehlt es, scheitert es, antwortet es zu langsam oder
#      mit Unsinn (kein JSON, negative Zahl), rechnet die Bremse selbst nach --
#      streng, nicht grosszuegig: lieber einmal zu frueh gebremst als zu spaet.
#      Und sie sagt in jeder Meldung, welche der beiden Quellen gerade galt --
#      eine Sicherung, die still auf den Rueckfall wechselt, waere nur eine
#      halbe Sicherung.
#  12  Ihr Eingriff verlaesst diesen Test nicht. Ein Prozess, dessen Startzeile
#      auf die weisse Liste passt, der aber NICHT zu diesem Lauf gehoert --
#      der Motor-Stellvertreter einer Nachbarsuite --, bleibt unangetastet, und
#      er haelt die Wache aus Zusage 8 auch nicht am Leben.
#
# ISOLATION: eigener tmux-Socket mit PID im Namen, eigenes HOME (`mktemp -d`) --
# damit liegen Protokoll, Pid- und Merkdatei im Wegwerf-HOME und nie im echten
# ~/.local/state. Die "Modelle" sind `sleep`-Prozesse unter einem Dateinamen, auf
# den die weisse Liste passt; es wird KEIN echtes Modell geladen und KEIN echter
# Modellserver beendet. Der fallende Speicher fuer Zusage 6 kommt seit dem
# 21.09.2026 aus einer Attrappe der Messquelle (WB_NOTBREMSE_CHECK) und nicht
# mehr aus echtem Belegen -- Begruendung unten am Fall selbst. Damit belegt
# dieser Test auch keine GiB mehr, waehrend Nachbarsuiten laufen.
#
# UND DER ZAUN (Nachtrag 21.08.2026, der eigentliche Anlass fuer Zusage 12): eigenes
# HOME und eigener Socket haben den zentralen Handgriff dieses Werkzeugs nie
# eingeschlossen. Das Beenden geht durch die Prozessliste der GANZEN Maschine, und
# im parallelen Lauf traf es die Nachbarsuite: test-mlx-wechsel-speicher.sh startet
# einen Stellvertreter, der ebenfalls `mlx_lm.server` heisst (heissen MUSS -- unter
# diesem Namen ruft wb-mlx-server den Motor auf). Gemessen an diesem Tag: laufen
# beide Suiten gleichzeitig, faellt die Wechsel-Suite mit "wb-nohup konnte den
# Server nicht starten" aus, und diese hier faellt umgekehrt in Zusage 8 und 6 aus,
# weil der fremde Stellvertreter ihre Wache nicht enden liess. Beide bestanden
# allein, beide fielen gemeinsam.
#
# Deshalb traegt jede Attrappe dieses Laufs eine MARKE in der Startzeile, und
# wb-notbremse bekommt sie ueber WB_NOTBREMSE_NUR_MUSTER als zusaetzlichen Filter
# gesetzt. Die weisse Liste sucht weiter wie im Ernstfall -- betrachtet wird nur,
# was auch diese Marke traegt. Zusage 12 unten prueft genau das, mit einer Attrappe
# OHNE Marke.
unset TMUX TMUX_PANE
set -uo pipefail

MARK="${LIVE_MARKER:+-$LIVE_MARKER}"
SOCKET="wbtest-notbremse$MARK-$$"
# Die Marke, die jede Attrappe dieses Laufs in ihrer Startzeile traegt und die
# wb-notbremse als Zaun gesetzt bekommt (siehe Kopfkommentar). Mit der PID darin,
# damit zwei Laeufe sich nicht gegenseitig einschliessen.
MARKE="zaun-notbremse$MARK-$$"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_NOTBREMSE:-$REPO/wb-notbremse}"
echo "Geprueft: $TOOL"

FAKEHOME="$(mktemp -d)"
WORK="$(mktemp -d)"
PROT="$FAKEHOME/.local/state/wb-notbremse/protokoll.log"
EINGRIFF="$FAKEHOME/.local/state/wb-notbremse/letzter-eingriff.json"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

# Die Attrappen werden in einer DATEI gefuehrt, nicht in einem Array. `attrappe`
# laeuft in einer Kommandosubstitution, also in einer Subshell -- ein
# `KINDER+=(...)` dort veraendert nur die Kopie der Subshell, und der Aufraeumer
# der Elternshell fand danach nichts (gemessen 2026-08-21: drei Attrappen liefen
# nach dem Testende weiter, bis ihr eigener sleep ablief). Eine Datei ueberlebt
# die Subshell.
KINDER_DATEI="$WORK/kinder.txt"
: > "$KINDER_DATEI"
tm() { tmux -L "$SOCKET" "$@"; }
cleanup() {
    local k
    while read -r k; do [ -n "$k" ] && kill -9 "$k" 2>/dev/null; done < "$KINDER_DATEI"
    tmux_socket_beenden_ohne_reste "$SOCKET"
    local deadline=$((SECONDS + 5))
    while [ $SECONDS -lt $deadline ] && tm list-sessions >/dev/null 2>&1; do
        tm kill-server 2>/dev/null
        sleep 0.3
    done
    tm list-sessions >/dev/null 2>&1 \
        && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
    rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
    rm -rf "$FAKEHOME" "$WORK"
}
trap cleanup EXIT

nb() {
    HOME="$FAKEHOME" WB_TMUX_SOCKET="$SOCKET" WB_NOTBREMSE_NUR_MUSTER="$MARKE" \
        python3 "$TOOL" "$@"
}

# --- Attrappen: Prozesse, deren KOMMANDOZEILE auf die Muster passt ----------
# Ein `sleep` unter einem Dateinamen, den die weisse Liste trifft. Es wird nie
# etwas geladen und nie etwas ausser diesen Attrappen beendet.
attrappe() {   # <dateiname> [argument...] -> gibt die PID aus
    # Zwei Anweisungen, nicht eine: `local a="$1" b="$WORK/$a"` sieht $a auf der
    # Bash 3.2 dieses Macs noch als ungebunden (gemessen), und `set -u` bricht ab.
    local name="$1"; shift
    # EIN WARTENDER PYTHON-PROZESS, dem der Name als ARGUMENT mitgegeben wird.
    # Zwei naheliegendere Wege scheitern auf diesem Mac, beide gemessen:
    #   - ein Skript mit `exec sleep 600` ersetzt sein Prozessabbild, in der
    #     Prozessliste steht danach "sleep 600" -- der Name, auf den die weisse
    #     Liste passen soll, ist weg;
    #   - eine KOPIE von /bin/sleep unter dem gewuenschten Namen wird von macOS
    #     sofort mit SIGKILL beendet (Exit 137, System-Binaerdatei ausserhalb
    #     ihres Pfades).
    # Der Name steht deshalb in der Kommandozeile eines gewoehnlichen
    # python3-Prozesses; genau dort sucht die Bremse auch im Betrieb.
    # >/dev/null: die Attrappe darf die Ausgabe der Kommandosubstitution NICHT
    # geerbt offen halten -- sonst wartet `$(attrappe ...)` auf ein Dateiende, das
    # erst in zehn Minuten kommt (gemessen: der Testlauf blieb genau hier stehen).
    # 120 s, nicht 600: Faellt ein Lauf aus (Zeitlimit, Abbruch), lebt eine
    # Attrappe sonst zehn Minuten weiter und wird vom NAECHSTEN Lauf mitgefunden --
    # die Bremse beendet sie dann voellig zu Recht, und die Zusage unten verglich
    # gegen die falsche PID (gemessen, 2026-08-21).
    # Die MARKE am Ende der Startzeile (siehe Kopfkommentar): sie steht hinter den
    # uebergebenen Argumenten, damit sie kein Muster zerreisst, das aus zwei
    # benachbarten Woertern besteht ("ollama serve").
    python3 -c 'import time; time.sleep(120)' "$name" "$@" "$MARKE" >/dev/null 2>&1 & local pid=$!
    printf '%s\n' "$pid" >> "$KINDER_DATEI"
    printf '%s\n' "$pid"
}
attrappe_ohne_marke() {   # dasselbe OHNE Marke: der Stellvertreter einer NACHBARSUITE
    local name="$1"; shift
    python3 -c 'import time; time.sleep(120)' "$name" "$@" >/dev/null 2>&1 & local pid=$!
    printf '%s\n' "$pid" >> "$KINDER_DATEI"
    printf '%s\n' "$pid"
}
lebt() { kill -0 "$1" 2>/dev/null; }

# DIESELBE QUELLE WIE DAS WERKZEUG, NICHT EINE ZWEITE FORMEL (Nachtrag
# 21.08.2026, Zusage 11): bis hierher rechnete diese Funktion die strenge
# vm_stat-Formel selbst nach, mit demselben Kommentar, der schon in
# wb-notbremse falsch wurde -- eine dritte, unabhaengige Fassung derselben
# Formel, die beim naechsten Umbau von check-resources genauso lautlos
# veraltet waere (siehe Befund 2, ~/.pi-workers/results/hafenmeister/
# 20260821-045339.md: GENAU diese Verdopplung hat den Befund erst erzeugt).
# wb-notbremse fragt seit demselben Umbau zuerst check-resources -- also
# misst diese Funktion jetzt genauso, ueber denselben Nachbarn im Repo, den
# wb-notbremses eigene check_resources_pfad() auch findet. Als FUNKTION,
# damit jeder Fall frisch misst (ein einmal am Anfang gemerkter Wert
# veraltet waehrend des Laufs, daran ist der erste Anlauf von Fall 6
# gescheitert). Faellt check-resources aus, der seltene Rueckfall auf die
# strenge Formel direkt -- lieber eine grobe Zahl als keine.
frei_messen() {
    if [ -x "$REPO/check-resources" ] \
        && WERT="$("$REPO/check-resources" --json 2>/dev/null | python3 -c '
import json, sys
try:
    print(int(json.load(sys.stdin)["ram"]["free_mib"]))
except Exception:
    sys.exit(1)
' 2>/dev/null)"; then
        printf '%s\n' "$WERT"
        return 0
    fi
    python3 - <<'PY'
import re, subprocess
seite = int(subprocess.run(["/usr/sbin/sysctl","-n","hw.pagesize"],capture_output=True,text=True).stdout)
vms = subprocess.run(["/usr/bin/vm_stat"],capture_output=True,text=True).stdout
n = sum(int(re.search(re.escape(k)+r":\s*(\d+)", vms).group(1))
        for k in ("Pages free","Pages inactive","Pages speculative","Pages purgeable"))
print(int(n*seite/1048576))
PY
}
FREI_MIB="$(frei_messen)"
echo "  (freier Speicher gerade: ${FREI_MIB} MiB)"

echo "== 1  Ueber der Schwelle passiert nichts =="
MPID="$(attrappe mlx_lm.server)"
sleep 0.5
AUS="$(nb pruefen --schwelle-mib 1 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$AUS" | grep -q 'Kein Eingriff noetig'; then
    ok "ueber der Schwelle: Exit 0, kein Eingriff"
else
    bad "ueber der Schwelle nicht folgenlos (rc=$RC): $AUS"
fi
lebt "$MPID" && ok "Modellattrappe lebt noch" || bad "Modellattrappe wurde beendet, obwohl genug frei war"

echo "== 2b mlx_vlm.server steht auf der weissen Liste (Nachtrag 2026-09-10) =="
# Gemessen 2026-09-10: der Vorgabemotor der Worker (mlx_vlm.server) fehlte in MUSTER,
# die Wache meldete nur "passt auf KEIN bekanntes Modell-Muster" und griff nicht ein,
# waehrend der Prozess auf 43 GB wuchs und der Worker mit Metal-OOM fiel.
VPID="$(attrappe mlx_vlm.server)"
sleep 0.5
AUS="$(nb pruefen --schwelle-mib $((FREI_MIB + 100000)) 2>&1)"
printf '%s' "$AUS" | grep -q "pid $VPID" \
    && ok "mlx_vlm.server wird als Modellprozess erkannt" || bad "mlx_vlm.server fehlt in der Liste: $AUS"
kill "$VPID" 2>/dev/null; wait "$VPID" 2>/dev/null || true

echo "== 3  Weisse Liste: gefunden wird nur, was Modell ist =="
# Die beiden ersten sind die ECHTE Probe auf die Vorrangregel: ihre Kommandozeile
# trifft ein Muster der weissen Liste UND ein Tabu. Nur wenn das Tabu zuerst
# geprueft wird, fallen sie heraus -- ein blosser Fremdprozess (der dritte) wuerde
# das nicht zeigen, denn der trifft ohnehin kein Muster.
OPID="$(attrappe "mlx_lm.server" "ollama" "serve")"
WPID="$(attrappe "mlx_lm.server-w" "whisper-server")"
FPID="$(attrappe "irgendwas-fremdes")"
sleep 0.5
AUS="$(nb pruefen --schwelle-mib $((FREI_MIB + 100000)) 2>&1)"
printf '%s' "$AUS" | grep -q "pid $MPID" \
    && ok "der Modellprozess steht in der Liste" || bad "Modellprozess fehlt: $AUS"
if printf '%s' "$AUS" | grep -qE "pid ($OPID|$WPID|$FPID)"; then
    bad "ein Tabu-Prozess oder ein fremder Prozess steht in der Liste: $AUS"
else
    ok "Tabu (ollama serve, whisper-server) schlaegt die weisse Liste; Fremdes faellt ohnehin heraus"
fi
printf '%s' "$AUS" | grep -q 'WUERDE ZUSCHLAGEN' \
    && ok "unter der Schwelle wird der Eingriff angekuendigt (ohne ihn zu tun)" \
    || bad "keine Ankuendigung: $AUS"
lebt "$MPID" && ok "'pruefen' beendet nichts" || bad "'pruefen' hat beendet"

echo "== 7  Ohne messbaren freien Speicher: kein Eingriff =="
# Gepatcht wird frei_mib_quelle() -- der Einstiegspunkt, den cmd_pruefen/
# cmd_wache seit dem Umbau auf 'genau eine Quelle' wirklich aufrufen (Zusage
# 11). Ein Patch auf das alte frei_mib() allein wuerde hier NICHTS mehr
# bewirken: frei_mib_quelle() fragt zuerst check-resources, und der Nachbar
# davon liegt im echten Repo direkt neben dieser Datei -- ein Patch, der nur
# frei_mib() ueberschreibt, wuerde also still am echten check-resources
# vorbeilaufen und den wirklich freien Speicher DIESER Maschine liefern,
# nicht None. Genau die Lehre aus dieser Woche: die Attrappe muss den
# tatsaechlich benutzten Pfad treffen, nicht nur einen plausiblen.
AUS="$(HOME="$FAKEHOME" python3 - "$TOOL" <<'PY' 2>&1
import importlib.util, sys, types
spec = importlib.util.spec_from_loader("nb", loader=None)
quelle = open(sys.argv[1], encoding="utf-8").read()
mod = types.ModuleType("nb"); mod.__file__ = sys.argv[1]
exec(compile(quelle, sys.argv[1], "exec"), mod.__dict__)
mod.frei_mib_quelle = lambda: (None, "test-stub")
class A: schwelle_mib = 1024.0; pid = None
print("RC=%d" % mod.cmd_pruefen(A(), wirklich=True))
PY
)"
if printf '%s' "$AUS" | grep -q 'RC=0' && printf '%s' "$AUS" | grep -q 'nicht messbar'; then
    ok "nicht messbar -> Exit 0, kein Eingriff, mit Begruendung"
else
    bad "nicht messbar falsch behandelt: $AUS"
fi
lebt "$MPID" && ok "auch dabei wurde nichts beendet" || bad "es wurde beendet"

echo "== 5  Eine tmux-Sitzung, in der die Meldung ankommen soll =="
tm new-session -d -s notbremstest cat || bad "Testsitzung liess sich nicht anlegen"

echo "== 12  Der Eingriff verlaesst diesen Test nicht =="
# Ein Stellvertreter, wie ihn die NACHBARSUITE startet: gleicher Name, gleiches
# Muster der weissen Liste -- nur ohne die Marke dieses Laufs. Er wird bewusst
# NICHT wieder beendet, sondern lebt bis zum Ende der Suite: damit steht er auch
# waehrend Zusage 6 (Wache unter echtem Druck) und Zusage 8 (die Wache endet von
# selbst) noch da, und beide pruefen dadurch mit, dass der Zaun haelt. Genau diese
# beiden Zusagen sind im vollen Lauf gefallen.
NACHBARPID="$(attrappe_ohne_marke mlx_lm.server)"
sleep 0.5
AUS="$(nb pruefen --schwelle-mib $((FREI_MIB + 100000)) 2>&1)"
printf '%s' "$AUS" | grep -q "pid $NACHBARPID" \
    && bad "12: der Stellvertreter der Nachbarsuite steht in der Liste: $AUS" \
    || ok "12: ein passender Prozess ohne die Marke dieses Laufs wird gar nicht erst betrachtet"
printf '%s' "$AUS" | grep -q "Zaun " \
    && ok "12: die Ausgabe sagt, dass gerade nicht die ganze Maschine betrachtet wird" \
    || bad "12: kein Hinweis auf den Zaun in der Ausgabe: $AUS"

echo "== 2+4+5  Unter der Schwelle: beenden, nachsehen, laut werden =="
AUS="$(nb jetzt --schwelle-mib $((FREI_MIB + 100000)) 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && ok "Eingriff meldet sich mit Exit 1" || bad "Exit war $RC statt 1"
warte_auf_bedingung 10 "die Modellattrappe ist beendet" '! kill -0 '"$MPID"' 2>/dev/null' \
    && ok "der Modellprozess ist WIRKLICH weg (nachgesehen, nicht angenommen)"
lebt "$OPID" && lebt "$WPID" && lebt "$FPID" \
    && ok "Tabu-Prozesse und Fremdes unangetastet" \
    || bad "ein Prozess ausserhalb der weissen Liste wurde beendet"
lebt "$NACHBARPID" \
    && ok "12: der Eingriff hat den Stellvertreter der Nachbarsuite nicht angefasst" \
    || bad "12: der Eingriff ist ueber diesen Test hinausgegangen und hat einen fremden Prozess beendet"
[ -s "$PROT" ] && grep -q 'NOTBREMSE' "$PROT" \
    && ok "das Protokoll nennt den Eingriff" || bad "kein Protokolleintrag in $PROT"
# MITGLIEDSCHAFT, nicht Reihenfolge: die Bremse ist maschinenweit und beendet
# voellig zu Recht JEDEN Prozess, der auf die weisse Liste passt -- auch eine
# Attrappe aus einem frueheren, abgebrochenen Lauf. Eine Zusage auf "der erste
# Eintrag ist meiner" prueft die Sortierung fremder Prozesse, nicht das Werkzeug.
if [ -s "$EINGRIFF" ] && python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
sys.exit(0 if int(sys.argv[2]) in [e['pid'] for e in d['beendet']] else 1)" "$EINGRIFF" "$MPID"; then
    ok "die Merkdatei nennt den beendeten Prozess"
else
    bad "letzter-eingriff.json fehlt oder nennt den Prozess nicht: $(cat "$EINGRIFF" 2>/dev/null)"
fi
if python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
sys.exit(0 if d.get('sitzungen_benachrichtigt',0) >= 1 else 1)" "$EINGRIFF" 2>/dev/null; then
    ok "die Meldung ging in die tmux-Sitzung(en) des Servers"
else
    bad "keine tmux-Sitzung benachrichtigt: $(cat "$EINGRIFF" 2>/dev/null)"
fi
[ -e "$FAKEHOME/.local/state/wb-belegung" ] \
    && bad "die Bremse hat ein Belegungsbuch angefasst" \
    || ok "kein Buch gelesen oder angelegt -- sie greift auch an der Buchung vorbei"

echo "== 8  Die Wache endet von selbst, wenn kein Modell mehr laeuft =="
# Und sie endet auch dann, wenn nebenan noch der Stellvertreter einer anderen Suite
# laeuft (NACHBARPID aus Zusage 12 lebt hier noch). Ohne den Zaun blieb die Wache
# genau daran haengen -- das war einer der drei Fehlschlaege im vollen Lauf.
nb start --schwelle-mib 1 --takt 0.3 --anlauf 1 >/dev/null 2>&1
warte_auf_bedingung 10 "die Wache traegt sich als laufend ein" \
    '[ -s "'"$FAKEHOME"'/.local/state/wb-notbremse/wache.pid" ]'
WPIDD="$(cat "$FAKEHOME/.local/state/wb-notbremse/wache.pid" 2>/dev/null)"
if [ -n "$WPIDD" ]; then
    warte_auf_bedingung 20 "die Wache endet ohne Modell von selbst" '! kill -0 '"$WPIDD"' 2>/dev/null' \
        && ok "ohne Modell endet die Wache von selbst (kein Prozess auf Vorrat)"
else
    bad "keine Wache gestartet"
fi

echo "== 6  Fallender Speicher: sie greift im Takt =="
# DIE ZUSAGE: steht die Schwelle fest und FAELLT die gemeldete Zahl waehrend die
# Wache laeuft unter sie, greift die Wache in ihrem Takt -- nicht erst beim
# naechsten Aufruf von Hand, und nicht schon oberhalb der Schwelle.
#
# BIS 21.09.2026 wurde dafuer ECHT Speicher belegt (druck-erzeugen.py, in Stufen
# bis unter eine aus dem freien Speicher abgeleitete Schwelle). Das hing am
# Zustand der Maschine und war damit genau die Bauart, die regeln/
# tests-und-eingriffe.md ausschliesst ("Ein Test STELLT seine Voraussetzung HER"):
# im Parallellauf bewegen Nachbarsuiten selbst Speicher, der Druck erreichte die
# Schwelle nicht, und der Fall meldete "ZUSTAND NICHT HERGESTELLT" -- ein roter
# Test ohne kaputtes Werkzeug. Zweiter Grund, unabhaengig davon: mehrere GiB zu
# belegen, waehrend fuenf andere Suiten laufen, ist selbst ein Eingriff in die
# Nachbarn.
#
# STATTDESSEN wird jetzt die MESSQUELLE gestellt, nicht der Speicher. Die Wache
# ohne --pid fragt zuerst check-resources (frei_mib_quelle() in wb-notbremse);
# WB_NOTBREMSE_CHECK ist der dafuer vorgesehene Test-Umweg, denselben benutzen
# die Faelle 11 und 7 weiter unten schon. Die Attrappe liest ihre Zahl bei jedem
# Aufruf frisch aus einer Datei, die dieser Test beschreibt -- damit faellt der
# gemeldete Speicher wirklich waehrend die Wache laeuft, deterministisch und
# ohne ein einziges belegtes MiB. Die Schwelle bleibt fest (1024 MiB), sie wird
# nicht nachtraeglich unter den Messwert geschoben.
CR6="$WORK/check-resources-fallend"
FREI6="$WORK/frei6.mib"
printf '8192\n' > "$FREI6"
cat > "$CR6" <<EOF
#!/bin/sh
printf '{"ram":{"free_mib":%s,"total_mib":49152}}\n' "\$(cat '$FREI6')"
EOF
chmod +x "$CR6"
MPID2="$(attrappe mlx_lm.server)"
sleep 0.5
# Erst aufraeumen, dann starten: blieb die Wache aus Zusage 8 stehen, meldet
# 'start' nur "laeuft bereits", diese Wache hier kaeme nie zustande, und der
# Fall unten schoebe es der Bremse in die Schuhe. Genau diese Kette hat einen
# einzigen Grund im vollen Lauf wie drei Fehlschlaege aussehen lassen.
nb stopp >/dev/null 2>&1
( export WB_NOTBREMSE_CHECK="$CR6"
  nb start --schwelle-mib 1024 --takt 0.5 --anlauf 60 >/dev/null 2>&1 )
warte_auf_bedingung 10 "die Wache laeuft" \
    '[ -s "'"$FAKEHOME"'/.local/state/wb-notbremse/wache.pid" ]'
# Oberhalb der Schwelle passiert nichts -- vier Takte lang nachgesehen, nicht
# angenommen. Ohne diesen Schritt wuerde der Fall unten auch dann gruen, wenn
# die Wache wahllos zuschlaegt.
sleep 2
if kill -0 "$MPID2" 2>/dev/null; then
    ok "oberhalb der Schwelle (8192 MiB gemeldet) bleibt das Modell unangetastet"
else
    bad "die Bremse hat oberhalb der Schwelle zugeschlagen (gemeldet: 8192 MiB, Schwelle 1024 MiB)"
fi
# Jetzt faellt die Zahl in Stufen unter die Schwelle. Zusage 9 verlangt zwei
# aufeinanderfolgende Abtastungen unter der Schwelle -- der Takt ist 0,5 s,
# die Wartezeit unten deckt beide ab.
printf '4096\n' > "$FREI6"; sleep 1
printf '2048\n' > "$FREI6"; sleep 1
printf '640\n' > "$FREI6"
warte_auf_bedingung 30 "die Notbremse beendet das Modell bei fallendem Speicher" \
     '! kill -0 '"$MPID2"' 2>/dev/null' \
     "$FAKEHOME/.local/state/wb-notbremse/protokoll.log"
if ! kill -0 "$MPID2" 2>/dev/null; then
    ok "bei fallendem Speicher greift sie im Takt (640 MiB gemeldet, Schwelle 1024 MiB)"
else
    bad "die Bremse hat NICHT gegriffen, obwohl die Quelle 640 MiB unter einer Schwelle von 1024 MiB meldete"
fi
nb stopp >/dev/null 2>&1
nb stopp >/dev/null 2>&1

echo "== 9  Eine EINZELNE Unterschreitung beendet nichts =="
# Die Schleife selbst geprueft, mit einer gestellten Messfolge statt echtem
# Speicher: nur so laesst sich ein einzelner Ausreisser ueberhaupt herstellen.
# Beendet wird nichts -- `beenden` ist durch einen Mitschreiber ersetzt.
AUS="$(HOME="$FAKEHOME" python3 - "$TOOL" <<'PY' 2>&1
import sys, types
quelle = open(sys.argv[1], encoding="utf-8").read()
mod = types.ModuleType("nb"); mod.__file__ = sys.argv[1]
exec(compile(quelle, sys.argv[1], "exec"), mod.__dict__)

# Messfolge: einmal weit unter der Schwelle, dann wieder darueber (der Ausreisser),
# danach zweimal unter der Schwelle (die echte Lage).
folge = [500.0, 9000.0, 500.0, 400.0]
schritte = {"n": 0}

def frei():
    i = schritte["n"]; schritte["n"] += 1
    return folge[i] if i < len(folge) else 9000.0

beendet = []
def modelle_stub(eigene_pid=None, ziel_pid=None):
    # Nach der Messfolge kein Modell mehr -> die Wache endet von selbst.
    return [] if schritte["n"] > len(folge) else [{"pid": 4242, "art": "mlx-lm",
                                                   "rss_mib": 1.0, "kommando": "attrappe mlx_lm.server"}]
# frei_mib_quelle() gepatcht, nicht frei_mib() -- siehe Begruendung bei Zusage 7
# oben, derselbe Grund gilt hier wortgleich. cmd_wache() ruft seit 27.08.2026
# frei_mib_fuer(a.pid), das bei pid=None unveraendert an frei_mib_quelle()
# durchreicht -- der Patch hier wirkt also weiter unveraendert.
mod.frei_mib_quelle = lambda: (frei(), "test-stub")
mod.modelle = modelle_stub
mod.beenden = lambda procs: (beendet.extend(procs), [(e, True, "SIGTERM") for e in procs])[1]
mod.in_die_sitzungen = lambda text: 0
mod.eingriff_merken = lambda d: None
mod.belegung_zurueckgeben = lambda ziel_pid=None: None

class A:
    schwelle_mib = 1024.0
    takt = 0.01
    anlauf = 0.0
    bestaetigungen = 2
    pid = None
mod.cmd_wache(A())
print("EINGRIFFE=%d" % len(beendet))
PY
)"
if printf '%s' "$AUS" | grep -q 'EINGRIFFE=1'; then
    ok "ein Ausreisser wird uebergangen, die echte Lage danach nicht"
else
    bad "die Bestaetigung greift nicht wie erwartet: $AUS"
fi
grep -q 'Ausreisser' "$PROT"     && ok "der uebergangene Ausreisser steht im Protokoll"     || bad "kein Protokolleintrag zum Ausreisser in $PROT"

echo "== 10  Nach dem Eingriff ist die Belegung aus dem Buch =="
# Ein Stellvertreter fuer wb-belegung im Test-HOME: er schreibt mit, womit er
# gerufen wurde, und meldet Erfolg. Das echte Buch wird nicht angefasst.
mkdir -p "$FAKEHOME/.local/bin" "$FAKEHOME/.local/state/wb-mlx-server"
cat > "$FAKEHOME/.local/bin/wb-belegung" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$WORK/belegung-aufrufe.txt"
exit 0
EOF
chmod +x "$FAKEHOME/.local/bin/wb-belegung"
printf 'abc123\n' > "$FAKEHOME/.local/state/wb-mlx-server/belegung-kennung"
HOME="$FAKEHOME" python3 - "$TOOL" >/dev/null 2>&1 <<'PY'
import sys, types
quelle = open(sys.argv[1], encoding="utf-8").read()
mod = types.ModuleType("nb"); mod.__file__ = sys.argv[1]
exec(compile(quelle, sys.argv[1], "exec"), mod.__dict__)
mod.modelle = lambda eigene_pid=None, ziel_pid=None: []      # kein Modell mehr uebrig
mod.belegung_zurueckgeben()
PY
if grep -q 'gib abc123 --fremd' "$WORK/belegung-aufrufe.txt" 2>/dev/null; then
    ok "die Belegung des beendeten Servers wird zurueckgegeben"
else
    bad "keine Freigabe angefordert: $(cat "$WORK/belegung-aufrufe.txt" 2>/dev/null)"
fi
[ -f "$FAKEHOME/.local/state/wb-mlx-server/belegung-kennung" ]     && bad "die Kennungsdatei liegt noch da, obwohl freigegeben wurde"     || ok "die Kennungsdatei ist weg -- sie wird nicht zweimal freigegeben"
# Und die Gegenprobe: laeuft noch ein Modell, wird NICHT freigegeben.
: > "$WORK/belegung-aufrufe.txt"
printf 'def456\n' > "$FAKEHOME/.local/state/wb-mlx-server/belegung-kennung"
HOME="$FAKEHOME" python3 - "$TOOL" >/dev/null 2>&1 <<'PY'
import sys, types
quelle = open(sys.argv[1], encoding="utf-8").read()
mod = types.ModuleType("nb"); mod.__file__ = sys.argv[1]
exec(compile(quelle, sys.argv[1], "exec"), mod.__dict__)
mod.modelle = lambda eigene_pid=None, ziel_pid=None: [{"pid": 1, "art": "mlx-lm", "rss_mib": 1.0, "kommando": "x"}]
mod.belegung_zurueckgeben()
PY
if [ -s "$WORK/belegung-aufrufe.txt" ]; then
    bad "es wurde freigegeben, obwohl noch ein Modell laeuft: $(cat "$WORK/belegung-aufrufe.txt")"
else
    ok "laeuft noch ein Modell, bleibt die Belegung stehen"
fi

echo
echo "== 11  Genau EINE Quelle fuer freien Speicher: check-resources, mit striktem Rueckfall =="
# Vier Attrappen fuer 'check-resources', ueber WB_NOTBREMSE_CHECK eingehaengt.
# STELLVERTRETER, NIE DER ECHTE DAEMON: jede Attrappe ist ein eigenes Skript in
# $WORK, nie das echte $HOME/.local/bin/check-resources oder der
# Nachbar im Repo. Der Wert 999999 MiB (rund 977 GiB) ist auf dieser Maschine
# UNMOEGLICH -- meldet die Bremse genau diese Zahl, kann sie nur von der
# Attrappe gekommen sein, nicht vom echten Werkzeug (derselbe Trick wie in
# test-check-resources-ollama.sh's Gegencheck, nur ueber den WERT statt ueber
# 'command -v').
CR_STUB="$WORK/check-resources-attrappe"

echo "-- 11a: check-resources antwortet gueltig -> seine Zahl wird benutzt --"
cat > "$CR_STUB" <<'EOF'
#!/bin/sh
echo '{"ram":{"free_mib":999999,"total_mib":1048576}}'
EOF
chmod +x "$CR_STUB"
# GROSSZUEGIGE FRIST HIER, und zwar mit Absicht: diese Zusage misst, ob eine GUELTIGE
# Antwort uebernommen wird -- nicht, wie schnell sie kommt. Dass die Frist ueberhaupt
# greift, prueft 11c mit einer eigenen, absichtlich zu langsamen Attrappe.
# Gemessen am 2026-08-21, nachdem diese Zusage im vollen Lauf rot war: der ERSTE Aufruf
# einer eben erst angelegten Datei kostet auf dieser Maschine bis zu 460 ms (Median 3,3 ms,
# zehn Messungen) -- kalter Dateisystem-Cache plus die Pruefungen, die macOS beim ersten
# Start eines neuen Programms macht. Gegen die Vorgabe von 500 ms ist das ein Rennen mit
# wenigen Millisekunden Abstand, und der Test war damit last- statt sachabhaengig rot.
AUS="$(WB_NOTBREMSE_CHECK="$CR_STUB" WB_NOTBREMSE_CHECK_FRIST_S=10 nb pruefen --schwelle-mib 1024 2>&1)"
if printf '%s' "$AUS" | grep -q '999999 MiB' && printf '%s' "$AUS" | grep -q 'Quelle: check-resources'; then
    ok "11a: die Zahl der Attrappe (999999 MiB, auf dieser Maschine unmoeglich) wird uebernommen"
else
    bad "11a: check-resources' Zahl wurde nicht benutzt: $AUS"
fi

echo "-- 11b: check-resources fehlt -> die Bremse rechnet selbst, streng, und sagt es --"
AUS="$(WB_NOTBREMSE_CHECK="$WORK/gibtsnicht" nb pruefen --schwelle-mib 1 2>&1)"
if printf '%s' "$AUS" | grep -q 'Quelle: streng (lokal, Rueckfall'; then
    ok "11b: ohne check-resources greift der strenge lokale Rueckfall, benannt als solcher"
else
    bad "11b: kein erkennbarer Rueckfall auf die strenge Formel: $AUS"
fi
if printf '%s' "$AUS" | grep -qE 'frei[[:space:]]+[0-9]+ MiB'; then
    ok "11b: der Rueckfall liefert trotzdem eine echte Zahl, keine leere Messung"
else
    bad "11b: der Rueckfall lieferte keine brauchbare Zahl: $AUS"
fi

echo "-- 11c: check-resources antwortet zu langsam -> Frist greift, Rueckfall greift --"
cat > "$CR_STUB" <<'EOF'
#!/bin/sh
sleep 3
echo '{"ram":{"free_mib":555555,"total_mib":1048576}}'
EOF
chmod +x "$CR_STUB"
START=$(date +%s)
AUS="$(WB_NOTBREMSE_CHECK="$CR_STUB" WB_NOTBREMSE_CHECK_FRIST_S=0.2 nb pruefen --schwelle-mib 1024 2>&1)"
DAUER=$(( $(date +%s) - START ))
if printf '%s' "$AUS" | grep -q 'Quelle: streng (lokal, Rueckfall' && ! printf '%s' "$AUS" | grep -q '555555'; then
    ok "11c: eine zu langsame Antwort wird verworfen (nicht die 555555 der Attrappe uebernommen)"
else
    bad "11c: die zu langsame Antwort wurde trotzdem benutzt: $AUS"
fi
if [ "$DAUER" -lt 3 ]; then
    ok "11c: die Frist wird wirklich durchgesetzt (${DAUER}s, nicht die vollen 3s der Attrappe abgewartet)"
else
    bad "11c: der Aufruf hat auf die volle Schlafzeit der Attrappe gewartet (${DAUER}s)"
fi

echo "-- 11d: check-resources antwortet Unsinn -> Rueckfall greift, kein Absturz --"
for FALL in leer keinjson negativ; do
    case "$FALL" in
        leer)     printf '#!/bin/sh\nexit 0\n' > "$CR_STUB" ;;
        keinjson) printf '#!/bin/sh\necho "das hier ist kein JSON"\n' > "$CR_STUB" ;;
        negativ)  printf '#!/bin/sh\necho '"'"'{"ram":{"free_mib":-42,"total_mib":1048576}}'"'"'\n' > "$CR_STUB" ;;
    esac
    chmod +x "$CR_STUB"
    AUS="$(WB_NOTBREMSE_CHECK="$CR_STUB" nb pruefen --schwelle-mib 1 2>&1)"; RC=$?
    if [ "$RC" -le 1 ] && printf '%s' "$AUS" | grep -q 'Quelle: streng (lokal, Rueckfall'; then
        ok "11d ($FALL): kein Absturz, sauberer Rueckfall auf die strenge Formel"
    else
        bad "11d ($FALL): kein sauberer Rueckfall (rc=$RC): $AUS"
    fi
done

echo
echo "== 13-18  --pid (Nachtrag 27.08.2026): keine Musterjagd, wenn die PID schon bekannt ist =="
# Anlass: Auftrag des Nutzers vom 27.08.2026, die Speicher-Reserven abzubauen und
# stattdessen auf diese Bremse zu setzen. wb-mlx-server gibt ab sofort die PID,
# die es von wb-nohup zurueckbekommen hat, direkt mit (--pid) -- keine Suche
# durch die Prozesstabelle per Muster mehr noetig (Hausregel: pgrep -f trifft
# auch den Agenten-Prompt, in dem der Suchbegriff vorkommt). Alle Faelle hier
# gegen HARMLOSE Attrappen, nie gegen echten Speicherdruck -- Zusage 6 hat das
# schon geleistet, hier geht es nur um den neuen --pid-Weg selbst.

echo "-- 13: --pid unter der Schwelle beendet GENAU diese PID, ohne Musterjagd --"
# Bewusst ein Name, der auf KEIN Muster der weissen Liste passt: der Beweis,
# dass --pid ohne Musterjagd auskommt, nicht nur, dass er zusaetzlich matcht.
ZPID="$(attrappe "voellig-unbekannter-prozessname")"
sleep 0.3
AUS="$(nb jetzt --pid "$ZPID" --schwelle-mib $((FREI_MIB + 100000)) 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && ok "13: Eingriff meldet sich mit Exit 1" || bad "13: Exit war $RC statt 1"
warte_auf_bedingung 10 "die Ziel-PID ist wirklich beendet" '! kill -0 '"$ZPID"' 2>/dev/null' \
    && ok "13: --pid beendet einen Prozess, der auf KEIN Muster passt -- die PID gewinnt"

echo "-- 14: --pid ueber der Schwelle laesst den Zielprozess laufen --"
ZPID2="$(attrappe "noch-ein-unbekannter-name")"
sleep 0.3
AUS="$(nb pruefen --pid "$ZPID2" --schwelle-mib 1 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$AUS" | grep -q 'Kein Eingriff noetig' \
    && ok "14: ueber der Schwelle: Exit 0, kein Eingriff" \
    || bad "14: ueber der Schwelle nicht folgenlos (rc=$RC): $AUS"
lebt "$ZPID2" && ok "14: die Zielattrappe lebt weiter" || bad "14: die Zielattrappe wurde trotzdem beendet"
kill -9 "$ZPID2" 2>/dev/null

echo "-- 15: TABU schuetzt auch unter --pid, selbst wenn die PID direkt gezielt ist --"
AUS="$(nb jetzt --pid "$WPID" --schwelle-mib $((FREI_MIB + 100000)) 2>&1)"; RC=$?
lebt "$WPID" && ok "15: ein per TABU geschuetzter Prozess ueberlebt --pid" \
    || bad "15: der TABU-Prozess wurde trotz Schutz beendet"
[ "$RC" -eq 1 ] && printf '%s' "$AUS" | grep -qi 'KEIN lokales Modell' \
    && ok "15: kein Eingriff moeglich gemeldet (TABU zaehlt als 'nichts zu beenden')" \
    || bad "15: TABU-Fall falsch gemeldet (rc=$RC): $AUS"

echo "-- 16: die Wache endet, sobald GENAU ihre Ziel-PID weg ist -- unabhaengig von anderen --"
# NACHBARPID (Zusage 12) laeuft hier noch und passt auf ein Muster -- eine
# musterbasierte Wache haette daran noch etwas zu beobachten. Die --pid-Wache
# hier kennt nur ihr eigenes Ziel und darf sich davon nicht beirren lassen.
ZPID3="$(attrappe "dritter-unbekannter-name")"
sleep 0.3
nb start --pid "$ZPID3" --schwelle-mib 1 --takt 0.2 --anlauf 1 >/dev/null 2>&1
WACHEDATEI="$FAKEHOME/.local/state/wb-notbremse/wache-pid-$ZPID3.pid"
warte_auf_bedingung 10 "die Ziel-Wache traegt sich ein" '[ -s "'"$WACHEDATEI"'" ]'
WPIDD3="$(cat "$WACHEDATEI" 2>/dev/null)"
if [ -n "$WPIDD3" ]; then
    kill -9 "$ZPID3" 2>/dev/null    # das Ziel stirbt aus einem anderen Grund als der Bremse
    warte_auf_bedingung 10 "die Ziel-Wache endet, sobald ihr Ziel weg ist" \
        '! kill -0 '"$WPIDD3"' 2>/dev/null' \
        && ok "16: die --pid-Wache endet mit ihrem Ziel, ungestoert vom weiterlaufenden Nachbarn" \
        || bad "16: die --pid-Wache lief nach dem Tod ihres Ziels weiter"
    lebt "$NACHBARPID" && ok "16: der Nachbar (anderes Muster-Ziel) blieb unangetastet" \
        || bad "16: der Nachbar wurde ungewollt beendet"
else
    bad "16: keine Ziel-Wache gestartet ($WACHEDATEI)"
fi

echo "-- 17: WB_NOTBREMSE_SCHWELLE_MIB setzt die Vorgabe, ohne --schwelle-mib --"
AUS="$(WB_NOTBREMSE_SCHWELLE_MIB=424242 nb pruefen 2>&1)"
printf '%s' "$AUS" | grep -q 'Schwelle 424242 MiB' \
    && ok "17: die Umgebungsvariable setzt die Schwelle, testbar ohne echten Speicher wegzunehmen" \
    || bad "17: die Vorgabe kam nicht aus der Umgebungsvariable: $AUS"

echo "-- 18: zwei --pid-Wachen fuer verschiedene Ziele kommen sich nicht in die Quere --"
# Der Fehler, den piddatei_fuer() beheben sollte: eine EINE gemeinsame PID-Datei
# haette der zweiten Wache faelschlich 'laeuft bereits' gemeldet, obwohl sie ein
# ganz anderes Ziel beobachten soll (Modellwechsel bei wb-mlx-server).
ZPID4="$(attrappe "vierter-unbekannter-name")"
ZPID5="$(attrappe "fuenfter-unbekannter-name")"
sleep 0.3
nb start --pid "$ZPID4" --schwelle-mib 1 --takt 5 --anlauf 60 >/dev/null 2>&1
nb start --pid "$ZPID5" --schwelle-mib 1 --takt 5 --anlauf 60 >/dev/null 2>&1
WD4="$FAKEHOME/.local/state/wb-notbremse/wache-pid-$ZPID4.pid"
WD5="$FAKEHOME/.local/state/wb-notbremse/wache-pid-$ZPID5.pid"
warte_auf_bedingung 10 "beide Ziel-Wachen tragen sich ein" '[ -s "'"$WD4"'" ] && [ -s "'"$WD5"'" ]'
W4="$(cat "$WD4" 2>/dev/null)"; W5="$(cat "$WD5" 2>/dev/null)"
if [ -n "$W4" ] && [ -n "$W5" ] && [ "$W4" != "$W5" ] && lebt "$W4" && lebt "$W5"; then
    ok "18: zwei --pid-Wachen fuer verschiedene Ziele laufen gleichzeitig, unabhaengig voneinander"
else
    bad "18: die zweite Wache kam nicht eigenstaendig zustande (W4=$W4 W5=$W5)"
fi
nb stopp --pid "$ZPID4" >/dev/null 2>&1
nb stopp --pid "$ZPID5" >/dev/null 2>&1
kill -9 "$ZPID4" "$ZPID5" 2>/dev/null

echo
echo "  bestanden: $pass, gescheitert: $fail"
[ "$fail" -eq 0 ]
