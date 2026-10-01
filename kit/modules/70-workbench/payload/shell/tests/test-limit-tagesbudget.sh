#!/bin/bash
# test-limit-tagesbudget.sh — `wb-budget --limit` und der SessionStart-Hook, der die Zahl
# in jeden Kontext legt.
#
# Anlass (2026-08-22): der Nutzer musste die Wochenlimit-Regel zweimal korrigieren, und beide
# Male war die Zahl im Rollen-Prompt zu streng. Erst stand dort eine starre Marke ("ab 40 %
# keine Cloud-Worker"), die am Samstag dieselbe Zahl ansetzte wie am Montag. Dann rechnete
# die Nachfolgeregel zwar anteilig, nahm aber den bis JETZT verstrichenen Fensteranteil als
# Maszstab statt das Ende des laufenden Tages — am selben Samstagmorgen 64 % statt 86 %.
# Sein Satz dazu: "erst wenn man über dem ist, was bis zu dem Zeitpunkt hätte verbraucht
# werden dürfen, damit man die ganze Zeit gleich viel macht, erst dann sollst Du die Nutzung
# runterfahren."
#
# Diese Suite haelt beide Fehler fest: die Wochentagsrechnung an JEDEM der sieben Tage, und
# die Unterscheidung zwischen "Luft" und "darueber". Beides ist am eigenen Rechner nur an
# genau einem Wochentag pruefbar — deshalb der Testhaken WB_LIMIT_JETZT in wb-budget, der im
# Betrieb nie gesetzt ist.
#
# ISOLATION: eigenes HOME unter mktemp, eigene limits.jsonl. Kein Zugriff auf das echte
# Betriebslog, kein Netz, kein tmux, kein Prozess ausser python3.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WB="$REPO_ROOT/shell/wb-budget"
HOOK="$REPO_ROOT/hooks/sessionstart-limit-budget.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok    $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
zusage() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAKEHOME="$TMP/home"
mkdir -p "$FAKEHOME/.claude/workbench" "$FAKEHOME/.local/bin"

# Das Fenster, an dem der Nutzer gerechnet hat: Reset Montag 2026-08-24 14:00 lokal,
# Start also Montag 2026-08-17 14:00.
RESET="$(python3 -c 'import datetime; print(int(datetime.datetime(2026,8,24,14,0).timestamp()))')"
schreibe_log() { # schreibe_log <pct>
  printf '{"ts": "2026-08-21T23:53:02Z", "session": "x", "five_hour_pct": 3, "seven_day_pct": %s, "seven_day_resets_at": "%s"}\n' \
    "$1" "$RESET" > "$FAKEHOME/.claude/workbench/limits.jsonl"
}
# <wochentag> <stunde> -> epoch
zeitpunkt() { python3 -c "import datetime; print(int(datetime.datetime(2026,8,$1,$2,0).timestamp()))"; }

lauf() { # lauf <tag-im-august> <stunde> [--knapp]
  local tag="$1" std="$2"; shift 2
  HOME="$FAKEHOME" WB_LIMIT_JETZT="$(zeitpunkt "$tag" "$std")" bash "$WB" --limit "$@" 2>&1
}

echo "== Die sieben Tage des Fensters =="
schreibe_log 60
# Montag 17.08. ist Tag 1, Sonntag 23.08. ist Tag 7. Erwartet: Tag * 100/7, gerundet.
i=1
for tag in 17 18 19 20 21 22 23; do
  erwartet="$(python3 -c "print(round($i*100/7))")"
  AUS="$(lauf "$tag" 20 --knapp)"
  case "$AUS" in
    *"erlaubt ${erwartet}%"*"Tag $i von 7"*) ok "Tag $i (August $tag): erlaubt ${erwartet}%" ;;
    *) bad "Tag $i (August $tag): erwartet ${erwartet}%, bekommen: $AUS" ;;
  esac
  i=$((i+1))
done

echo "== Fall des Nutzers, wortwoertlich =="
# Samstag, 60 % verbraucht. Seine Rechnung: 6 x 14 = 84, also Luft. Die Fassung davor
# rechnete den bis JETZT verstrichenen Anteil und kam auf 64 % — knapp bis gesperrt.
AUS="$(lauf 22 1 --knapp)"
case "$AUS" in
  *"Samstag, Tag 6 von 7"*) ok "Samstag wird als Tag 6 gefuehrt" ;;
  *) bad "Samstag nicht als Tag 6: $AUS" ;;
esac
case "$AUS" in
  *"erlaubt 86%"*) ok "Samstag erlaubt 86 % (des Nutzers 84 mit exaktem 100/7 statt 14)" ;;
  *) bad "Samstag nicht 86 %: $AUS" ;;
esac
case "$AUS" in
  *Luft*) ok "60 % verbraucht am Samstag heisst LUFT, nicht knapp" ;;
  *) bad "Samstag mit 60 % nicht als Luft gemeldet: $AUS" ;;
esac
# Die Uhrzeit darf am Ergebnis nichts aendern: der Maszstab ist das Tagesende, nicht jetzt.
FRUEH="$(lauf 22 1 --knapp)"; SPAET="$(lauf 22 23 --knapp)"
[ "$FRUEH" = "$SPAET" ]; zusage $? "morgens und abends desselben Tages ergeben dieselbe Zahl"

echo "== Drosseln erst oberhalb der Linie =="
schreibe_log 20
AUS="$(lauf 17 20 --knapp)"   # Montag: erlaubt 14, verbraucht 20
case "$AUS" in
  *DARUEBER*) ok "Montag mit 20 % verbraucht meldet DARUEBER" ;;
  *) bad "Montag mit 20 % nicht als darueber gemeldet: $AUS" ;;
esac
schreibe_log 10
AUS="$(lauf 17 20 --knapp)"   # Montag: erlaubt 14, verbraucht 10
case "$AUS" in
  *Luft*) ok "Montag mit 10 % verbraucht meldet Luft" ;;
  *) bad "Montag mit 10 % nicht als Luft gemeldet: $AUS" ;;
esac

echo "== Deckel und Randfaelle =="
schreibe_log 99
AUS="$(lauf 23 23 --knapp)"
case "$AUS" in
  *"erlaubt 100%"*) ok "am siebten Tag ist der Deckel 100 %, nicht mehr" ;;
  *) bad "Deckel am Tag 7 nicht 100 %: $AUS" ;;
esac

rm -f "$FAKEHOME/.claude/workbench/limits.jsonl"
HOME="$FAKEHOME" bash "$WB" --limit --knapp >/dev/null 2>&1
[ $? -ne 0 ]; zusage $? "ohne Betriebslog endet --limit mit ungleich 0 statt eine Zahl zu erfinden"

printf 'kaputt\n{"ts":"x"}\nnoch kaputter\n' > "$FAKEHOME/.claude/workbench/limits.jsonl"
HOME="$FAKEHOME" bash "$WB" --limit --knapp >/dev/null 2>&1
[ $? -ne 0 ]; zusage $? "ein Log ohne brauchbaren Eintrag endet mit ungleich 0"

# Ein spaeterer Eintrag OHNE die beiden Felder darf den letzten brauchbaren nicht verdraengen.
schreibe_log 60
printf '{"ts": "2026-08-22T00:00:00Z", "five_hour_pct": 4}\n' >> "$FAKEHOME/.claude/workbench/limits.jsonl"
AUS="$(lauf 22 20 --knapp)"
case "$AUS" in
  *"60% verbraucht"*) ok "ein Eintrag ohne die beiden Felder verdraengt den letzten brauchbaren nicht" ;;
  *) bad "letzter brauchbarer Eintrag verloren: $AUS" ;;
esac

echo "== Der Hook =="
schreibe_log 60
[ -x "$HOOK" ]; zusage $? "der SessionStart-Hook ist ausfuehrbar"

# Der Hook ruft $HOME/.local/bin/wb-budget — im Fake-HOME liegt dort die Repo-Fassung.
cp "$WB" "$FAKEHOME/.local/bin/wb-budget"; chmod +x "$FAKEHOME/.local/bin/wb-budget"
AUS="$(HOME="$FAKEHOME" WB_LIMIT_JETZT="$(zeitpunkt 22 20)" bash "$HOOK" 2>&1)"
ZEILEN="$(printf '%s\n' "$AUS" | grep -c .)"
[ "$ZEILEN" = 1 ]; zusage $? "der Hook gibt GENAU eine Zeile aus (gezaehlt: $ZEILEN)"
case "$AUS" in
  *Wochenlimit*) ok "die Zeile nennt das Wochenlimit" ;;
  *) bad "Hook-Zeile ohne Wochenlimit: $AUS" ;;
esac

# Anders als die Geschwister-Hooks schweigt dieser NICHT bei gruen -- das ist der Kern:
# eine fehlende Zahl wird durch eine geratene ersetzt.
schreibe_log 1
AUS="$(HOME="$FAKEHOME" WB_LIMIT_JETZT="$(zeitpunkt 22 20)" bash "$HOOK" 2>&1)"
[ -n "$AUS" ]; zusage $? "der Hook spricht auch dann, wenn reichlich Luft ist"

# Ohne wb-budget schweigt er und endet mit 0 -- ein Sessionstart darf daran nie scheitern.
rm -f "$FAKEHOME/.local/bin/wb-budget"
AUS="$(HOME="$FAKEHOME" bash "$HOOK" 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ -z "$AUS" ]; zusage $? "ohne wb-budget schweigt der Hook und endet mit 0"

echo "== Gegenprobe: die alte Rechnung haette hier anders geantwortet =="
# Die Fassung vom selben Tag rechnete (jetzt - start) / 7 Tage. Am Samstag um 01:23 sind das
# 4,47 von 7 Tagen = 64 %. Wenn die neue Rechnung dieselbe Zahl lieferte, waere sie nicht
# repariert worden.
schreibe_log 60
AUS="$(lauf 22 1 --knapp)"
case "$AUS" in
  *"erlaubt 64%"*) bad "die neue Rechnung liefert weiterhin die alten 64 % — nichts geaendert" ;;
  *) ok "die neue Rechnung liefert NICHT mehr die alten 64 %" ;;
esac

echo "== ChatGPT Plus (Codex): Wochenbudget nach Kalendertagen, 5h hart =="
# Der Codex-Reset ist rollend, die Sparlinie aber fuer beide Abos gleich: Tag 1
# zaehlt bereits am Fensterbeginn, danach Tagindex * 100/7. Die 5h-Zeile ist
# nur ein hartes Limit und darf keine anteilige Erlaubnis ausgeben.
CODEXLOG="$FAKEHOME/.claude/workbench/codex-limits.jsonl"
# Fester Abfragezeitpunkt fuer den ganzen Codex-Abschnitt, EINMAL berechnet --
# dieselbe Zahl geht in den Rueckfallzeitpunkt und als WB_LIMIT_JETZT in den
# Aufruf, damit Fensterbeginn, Tageswechsel und Reset steuerbar bleiben.
CODEX_JETZT_EPOCH="$(python3 -c 'import datetime; print(int(datetime.datetime(2026,9,10,20,0).timestamp()))')"
# Epoch -> ISO-UTC, dieselbe Umrechnung wie iso_von_epoch weiter oben -- hier lokal
# noch einmal, weil CODEX_JETZT_EPOCH selbst ueber eine NAIVE lokale datetime
# entsteht (wie zeitpunkt() im Rest der Datei) und jeder Rueckfallzeitpunkt aus
# DERSELBEN Umrechnung stammen muss, sonst verschiebt die lokale Zeitzone (hier
# gemessen: CEST, +2h) den scheinbaren reset_after_seconds-Wert.
codex_iso_epoch() { python3 -c "import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$1"; }

schreibe_codex_log() {   # schreibe_codex_log <seven_day_pct> <five_hour_pct> <sek-bis-7t-rueckfall> [7t-fensterlaenge] [5h-fensterlaenge] [sek-bis-5h-rueckfall]
  local sieben="$1" fuenf="$2" rest_s="$3" sieben_fenster="${4:-604800}" fuenf_fenster="${5:-18000}" fuenf_rest_s="${6:-3600}"
  local reset_iso fuenf_reset_iso
  reset_iso="$(codex_iso_epoch $(( CODEX_JETZT_EPOCH + rest_s )))"
  fuenf_reset_iso="$(codex_iso_epoch $(( CODEX_JETZT_EPOCH + fuenf_rest_s )))"
  printf '{"ts": "2026-09-10T20:00:00Z", "plan": "plus", "five_hour_pct": %s, "seven_day_pct": %s, "five_hour_resets_at": "%s", "seven_day_resets_at": "%s", "five_hour_window_s": %s, "seven_day_window_s": %s}\n' \
    "$fuenf" "$sieben" "$fuenf_reset_iso" "$reset_iso" "$fuenf_fenster" "$sieben_fenster" > "$CODEXLOG"
}
lauf_codex() {
  HOME="$FAKEHOME" WB_LIMIT_JETZT="$CODEX_JETZT_EPOCH" \
    WB_CODEX_LIMITS_FILE="$CODEXLOG" bash "$WB" --limit 2>&1
}
lauf_codex_zu() { # lauf_codex_zu <epoch>; TZ zwingt einen reproduzierbaren DST-Fall.
  HOME="$FAKEHOME" TZ=Europe/Berlin WB_LIMIT_JETZT="$1" \
    WB_CODEX_LIMITS_FILE="$CODEXLOG" bash "$WB" --limit 2>&1
}

schreibe_log 60   # der Claude-Block muss weiterhin erscheinen, unveraendert.
# Der Reset liegt zwei Kalendertage nach dem Pruefzeitpunkt. Sein Fensterbeginn
# liegt damit fuenf Kalendertage vorher: der 10.09. ist Tag 6, also 85,7 %.
schreibe_codex_log 50 10 172800
AUS="$(lauf_codex)"
case "$AUS" in
  *"== Wochenlimit: Tagesbudget =="*"== ChatGPT Plus (Codex) =="*) \
    ok "der Codex-Block folgt nach dem Claude-Block" ;;
  *) bad "die Reihenfolge/Beide Bloecke fehlen: $AUS" ;;
esac
case "$AUS" in
  *"verbraucht 50.0"*"erlaubt 85.7"*"Kalendertag 6 von 7"*Luft*"35.7 Punkte"*) \
    ok "Tag 6 erlaubt 85,7%%, unabhaengig von der Uhrzeit im rollenden Fenster" ;;
  *) bad "die Codex-Tageslinie stimmt nicht: $AUS" ;;
esac
case "$AUS" in
  *"5-Stunden-Fenster"*"verbraucht 10.0"*) ok "die 5-Stunden-Zeile steht dabei" ;;
  *) bad "die 5-Stunden-Zeile fehlt: $AUS" ;;
esac
case "$AUS" in
  *"5-Stunden-Fenster (rollend): verbraucht 10.0"*"hartes Limit bei 100 %"*) \
    ok "das 5-Stunden-Fenster nennt nur das harte 100%%-Limit" ;;
  *) bad "die 5-Stunden-Zeile hat kein hartes Limit: $AUS" ;;
esac
case "$AUS" in
  *"5-Stunden-Fenster"*"erlaubt "*) bad "5-Stunden-Zeile enthaelt weiter eine Tageslinie: $AUS" ;;
  *) ok "5-Stunden-Zeile enthaelt keine anteilige Tageslinie" ;;
esac

# Ein unbekannter Reset nimmt dem gemessenen 5h-Verbrauch nicht seine Aussage.
python3 - "$CODEXLOG" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    data = json.load(stream)
data['five_hour_resets_at'] = 'kaputt'
with open(sys.argv[1], 'w') as stream:
    json.dump(data, stream)
PY
AUS="$(lauf_codex)"
case "$AUS" in
  *"5-Stunden-Fenster (rollend): verbraucht 10.0"*"hartes Limit bei 100 %"*"reset unbekannt"*) ok "5h-Verbrauch bleibt bei defektem Reset sichtbar" ;;
  *) bad "defekter Reset unterdrueckt das harte Limit: $AUS" ;;
esac

# Am Fensterbeginn zaehlt der Kalendertag bereits als Tag 1 (14,3 %).
schreibe_codex_log 50 10 604800
AUS="$(lauf_codex)"
case "$AUS" in
  *"erlaubt 14.3"*"Kalendertag 1 von 7"*"DARUEBER um"*) ok "Fensterbeginn zaehlt als Tag 1" ;;
  *) bad "Fensterbeginn ergibt nicht Tag 1: $AUS" ;;
esac

# Ein Kalendertag spaeter steigt die Linie, ohne dass die Uhrzeit im Tag zaehlt.
schreibe_codex_log 50 10 518400
AUS="$(lauf_codex)"
case "$AUS" in
  *"erlaubt 28.6"*"Kalendertag 2 von 7"*) ok "Tagwechsel erhoeht die Codex-Tageslinie auf Tag 2" ;;
  *) bad "Tagwechsel ergibt nicht Tag 2: $AUS" ;;
esac

# Ein neuer Reset stellt ein neues Wochenfenster dar; derselbe Kalendertag ist
# darin wieder Tag 1. So wird der Reset nicht durch die alte Fensterposition
# weitergerechnet.
schreibe_codex_log 10 10 604800
AUS="$(lauf_codex)"
case "$AUS" in
  *"erlaubt 14.3"*"Kalendertag 1 von 7"*) ok "neuer Reset beginnt wieder mit Tag 1" ;;
  *) bad "Reset beginnt nicht mit Tag 1: $AUS" ;;
esac

rm -f "$CODEXLOG"
AUS="$(lauf_codex)"
case "$AUS" in
  *"ChatGPT Plus (Codex): noch nicht gemessen (wb-kontingent auffrischen)"*) \
    ok "ohne codex-limits.jsonl die vorgeschriebene Zeile, kein Fehler" ;;
  *) bad "die 'noch nicht gemessen'-Zeile fehlt: $AUS" ;;
esac

AUS="$(HOME="$FAKEHOME" WB_LIMIT_JETZT="$(zeitpunkt 22 20)" WB_CODEX_LIMITS_FILE="$CODEXLOG" bash "$WB" --limit --knapp 2>&1)"
schreibe_codex_log 50 10 172800
AUS_MIT_CODEX="$(HOME="$FAKEHOME" WB_LIMIT_JETZT="$(zeitpunkt 22 20)" WB_CODEX_LIMITS_FILE="$CODEXLOG" bash "$WB" --limit --knapp 2>&1)"
[ "$AUS" = "$AUS_MIT_CODEX" ]
zusage $? "'--limit --knapp' bleibt zeichengleich -- Codex taucht dort nicht auf (der Hook zaehlt Zeilen)"

echo "== Codex: abweichende oder kaputte Fensterlaenge bekommt keine erfundene Wochenlinie =="
# Die Endpunkt-Fensterlaenge bestimmt den Fensterbeginn. Eine andere gueltige
# Laenge ist aber keine Wochenlinie mit 7 Tagen und wird klar als solche gemeldet.
schreibe_codex_log 60 5 172800 259200 18000
AUS="$(lauf_codex)"
case "$AUS" in
  *"Fensterlaenge 259200 s"*"Tageslinie nur fuer 7-Tage-Fenster moeglich"*) ok "abweichende Fensterlaenge wird nicht als Wochenlinie erfunden" ;;
  *) bad "abweichende Fensterlaenge wurde nicht klar gemeldet: $AUS" ;;
esac
case "$AUS" in
  *"erlaubt "*) bad "abweichende Fensterlaenge bekam weiter eine Tageslinie: $AUS" ;;
  *) ok "abweichende Fensterlaenge hat keine Tageslinie" ;;
esac

schreibe_codex_log 60 5 172800 '"kaputt"' 18000
AUS="$(lauf_codex)"
case "$AUS" in
  *"Fensterlaenge unlesbar"*"keine Tageslinie moeglich"*) ok "kaputte Fensterlaenge faellt nicht still auf 7 Tage zurueck" ;;
  *) bad "kaputte Fensterlaenge wurde nicht klar gemeldet: $AUS" ;;
esac

echo "== Codex: noch nicht gestartete und abgelaufene Fenster sind kein Guthaben =="
schreibe_codex_log 10 5 604801
AUS="$(lauf_codex)"
case "$AUS" in
  *"Fenster beginnt erst"*"keine Tageslinie moeglich"*) ok "kuenftiges Fenster meldet keine frische Luft" ;;
  *) bad "kuenftiges Fenster wurde als Tageslinie gerechnet: $AUS" ;;
esac
schreibe_codex_log 10 5 0
AUS="$(lauf_codex)"
case "$AUS" in
  *"Fenster endete"*"keine Tageslinie moeglich"*) ok "abgelaufenes Fenster meldet keine frische Luft" ;;
  *) bad "abgelaufenes Fenster wurde als Tageslinie gerechnet: $AUS" ;;
esac

schreibe_codex_log 10 5 1
AUS="$(lauf_codex)"
case "$AUS" in
  *"erlaubt 100.0"*) ok "bis unmittelbar vor Reset bleibt das volle Wochenbudget verfuegbar" ;;
  *) bad "gueltige letzte Sekunde bekam keine Tageslinie: $AUS" ;;
esac

echo "== Codex: Ortsdatum wird an DST-Grenze je Zeitstempel berechnet =="
DST_JETZT="$(TZ=Europe/Berlin python3 -c 'import datetime; from zoneinfo import ZoneInfo; print(int(datetime.datetime(2026, 4, 3, 12, tzinfo=ZoneInfo("Europe/Berlin")).timestamp()))')"
DST_RESET="$(TZ=Europe/Berlin python3 -c 'import datetime; from zoneinfo import ZoneInfo; print(datetime.datetime(2026, 4, 5, 0, 30, tzinfo=ZoneInfo("Europe/Berlin")).astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
printf '{"ts":"2026-04-04T10:00:00Z","plan":"plus","five_hour_pct":5,"seven_day_pct":60,"five_hour_resets_at":"2026-04-04T13:00:00Z","seven_day_resets_at":"%s","five_hour_window_s":18000,"seven_day_window_s":604800}\n' "$DST_RESET" > "$CODEXLOG"
AUS="$(lauf_codex_zu "$DST_JETZT")"
case "$AUS" in
  *"erlaubt 100.0"*"Kalendertag 7 von 7"*) ok "DST-Wechsel verschiebt den Fensterstart nicht in den falschen Kalendertag" ;;
  *) bad "DST-Fall liefert nicht Tag 7: $AUS" ;;
esac

echo "== Codex: alte Verlaufszeile ohne Fensterlaengen-Felder bleibt lesbar =="
printf '{"ts": "2026-09-10T20:00:00Z", "plan": "plus", "five_hour_pct": 10, "seven_day_pct": 50, "five_hour_resets_at": "2026-09-10T21:00:00Z", "seven_day_resets_at": "%s"}\n' \
  "$(python3 -c "import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$(( CODEX_JETZT_EPOCH + 172800 ))")" \
  > "$CODEXLOG"
AUS="$(lauf_codex)"
case "$AUS" in
  *"erlaubt 85.7"*"Kalendertag 6 von 7"*) ok "eine alte Zeile ohne *_window_s bleibt mit Wochenlinie lesbar" ;;
  *) bad "alte Zeile liefert keine Wochenlinie: $AUS" ;;
esac

echo "== Codex: eine kaputte seven_day_pct-Angabe stuerzt nicht ab, sondern zeigt 'noch nicht gemessen' =="
printf '{"ts": "2026-09-10T20:00:00Z", "plan": "plus", "five_hour_pct": 10, "seven_day_pct": "kaputt", "five_hour_resets_at": "2026-09-10T21:00:00Z", "seven_day_resets_at": "2099-01-01T00:00:00Z"}\n' \
  > "$CODEXLOG"
AUS="$(lauf_codex)"; RC=$?
[ "$RC" = 0 ]; zusage $? "'wb-budget --limit' stuerzt bei einer kaputten seven_day_pct nicht ab (rc=$RC)"
case "$AUS" in
  *"ChatGPT Plus (Codex): noch nicht gemessen (wb-kontingent auffrischen)"*) \
    ok "eine unlesbare seven_day_pct zeigt dieselbe 'noch nicht gemessen'-Zeile statt eine Zahl zu erfinden" ;;
  *) bad "kaputte seven_day_pct wurde nicht abgefangen: $AUS" ;;
esac

rm -f "$CODEXLOG"

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
