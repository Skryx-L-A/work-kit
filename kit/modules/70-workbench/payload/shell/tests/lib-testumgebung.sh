# lib-testumgebung.sh -- keine Live-Umgebung in einen Test (27.09.2026). Zum Sourcen gedacht;
# lib-testwerkzeuge.sh bindet es selbst ein, Suiten ohne diese Bibliothek sourcen es direkt.
#
# DER ANLASS. Aus einem Werkbank-Pane gestartet, erbt eine Suite AWB_CONTROL_SOCKET,
# AWB_MANTEL_SOCKET, AWB_MANTEL_TOKEN, WB_EIGENTUEMER_* und weitere Werte des LIVE-Kerns.
# Ein Test-Kern mit diesen Werten hat am 27.09. den Mantel-Socket der laufenden App
# geloescht; test-app-gasttor.sh hatte die Bereinigung schon, 98 von 112 App-Suiten nicht.
#
# DIE REGEL. Jede exportierte AWB_*/WB_*-Variable geht, mit zwei Ausnahmen:
#   * die Stellschrauben der aufrufenden Suite selbst -- Namen, die sie als
#     "${NAME:-vorgabe}" liest (etwa WB_BILDER, WB_BIN, AWB_BELEG_DIR); wer sie beim Aufruf
#     setzt, meint sie;
#   * Namen in WB_TEST_BEHALTEN (durch Leerzeichen getrennt), fuer einen Handlauf.
# Die Werte, die nur ein laufender Kern oder Pane setzt, gehen IMMER, auch wenn eine Suite
# sie als Stellschraube liest.
test_live_umgebung_leeren() {
    local skript="${1:-${BASH_SOURCE[${#BASH_SOURCE[@]}-1]}}" knoepfe="" behalten="${WB_TEST_BEHALTEN:-}" name
    if [ -f "$skript" ]; then
        knoepfe="$(grep -oE '(^|[^\\])\$\{A?WB_[A-Za-z0-9_]+:-' "$skript" 2>/dev/null \
            | sed -E 's/.*\{//; s/:-$//' | sort -u | tr '\n' ' ' || true)"
    fi
    for name in $(compgen -e | grep -E '^A?WB_'); do
        case "$name" in
            AWB_CONTROL_SOCKET|AWB_MANTEL_*|WB_MANTEL_*|WB_EIGENTUEMER_*|WB_MENSCH_QUELLE|WB_APP_PID)
                unset "$name"; continue ;;
        esac
        case " $knoepfe $behalten " in
            *" $name "*) continue ;;
        esac
        unset "$name"
    done
}
test_live_umgebung_leeren
