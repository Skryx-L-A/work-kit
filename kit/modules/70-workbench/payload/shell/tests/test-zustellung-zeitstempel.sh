#!/usr/bin/env bash
# test-zustellung-zeitstempel.sh -- zwei Auftraege in DERSELBEN Sekunde.
#
# DER BEFUND, den diese Suite festhaelt (2026-08-20, Stresstest der
# Zustellung, gemessen). Der Ergebnisdateiname eines Auftrags ist ein
# Zeitstempel mit Sekundenaufloesung, und er ist zugleich der MARKER, an dem
# pi-worker die Ankunft nachweist. Zwei Auftraege an denselben Worker innerhalb
# einer Sekunde sind kein Sonderfall: ein zweiter Auftrag in einen bestehenden
# Pane braucht ueber die Sitzungs-Inbox rund eine Sekunde, und in einem Lauf
# mit zwoelf Auftraegen hintereinander teilten sich gemessen je zwei denselben
# Zeitstempel.
#
# Solange sie ihn teilten, war der Beleg wertlos -- und zwar in der
# gefaehrlichen Richtung: der zweite Auftrag wurde von der Sitzung verschluckt
# (im Pane kein einziges Mal zu finden), pi-worker fand den Marker des ERSTEN
# und meldete "zugestellt (Ankunft belegt: Pane)", Exit 0. Dazu ueberschrieb
# der zweite Auftrag die Auftragsdatei des ersten, und beide zeigten auf
# dieselbe Ergebnisdatei.
#
# Die Uhr wird hier ANGEHALTEN, statt auf den Zufall zu warten: ein `date`-
# Stellvertreter im PATH liefert fuer GENAU das Auftragsformat einen festen
# Wert und reicht jeden anderen Aufruf an /bin/date weiter. Nur so ist der Fall
# reproduzierbar und nicht bloss gelegentlich.
#
#   1  Zwei Auftraege in derselben Sekunde, beide sauber zugestellt: zwei
#      VERSCHIEDENE Ergebnisdateien, zwei verschiedene Auftragsdateien, beide
#      Auftragstexte erhalten.
#   2  Zwei Auftraege in derselben Sekunde, der zweite wird verschluckt: das
#      MUSS ein lauter Fehlschlag sein. Vor dem Fix war es eine Erfolgsmeldung.
#
# ISOLATION und LOESCH-SICHERUNG: siehe lib-zustellbett.sh.
# LAUFZEIT: rund anderthalb Minuten, davon eine Minute fuer Fall 2 -- die
# 60-s-Frist des Socket-Wegs muss dort wirklich ablaufen.
set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-zustellbett.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOR="$(cd "$HIER/.." && pwd)"
command -v tmux >/dev/null 2>&1 || ueberspringen "tmux nicht im PATH"
[ -x "$VOR/pi-worker" ]             || ueberspringen "shell/pi-worker fehlt"
[ -f "$HIER/fake-claude-inbox.py" ] || ueberspringen "fake-claude-inbox.py fehlt"
command -v /usr/bin/python3 >/dev/null || ueberspringen "python3 fehlt"

echo "== Zwei Auftraege in derselben Sekunde =="
zustellbett_start || ueberspringen "Testaufbau fehlgeschlagen"
trap zustellbett_ende EXIT INT TERM

# Die Uhr anhalten -- aber NUR fuer das eine Format, das den Auftragsnamen
# bildet. Alles andere (Fristen, Auftragsbuch, Anzeige) muss weiterlaufen,
# sonst haengt der Test in einer Warteschleife, deren Uhr nicht tickt.
cat > "$SHIM/date" <<'DEOF'
#!/bin/sh
if [ "$1" = "+%Y%m%d-%H%M%S" ]; then echo "20260820-000000"; exit 0; fi
exec /bin/date "$@"
DEOF
chmod +x "$SHIM/date"

# ── 1: beide Auftraege kommen an ──────────────────────────────────────────────
echo
echo "-- 1: zwei Auftraege in derselben Sekunde, beide sauber zugestellt --"
zustellbett_panes_weg
zustellbett_leeren "$RECV"
zustellbett_claude_inbox normal
Z1="t1$MARKE"
A1="$(pi_lauf socket "$Z1" "SEKUNDE-EINS-$MARKE")"
A2="$(pi_lauf socket "$Z1" "SEKUNDE-ZWEI-$MARKE")"
[ "$(zustellweg "$A1")" = SOCKET ] && ok "1: der erste Auftrag ist belegt zugestellt" \
                                   || bad "1: schon der erste Auftrag scheiterte"
[ "$(zustellweg "$A2")" = SOCKET ] && ok "1: der zweite ebenfalls" \
                                   || bad "1: der zweite Auftrag scheiterte: $(printf '%s' "$A2" | grep -m1 FEHLER)"
R1="$(ergebnisdatei "$A1")"; R2="$(ergebnisdatei "$A2")"
if [ -z "$R1" ] || [ -z "$R2" ]; then
  bad "1: eine der beiden Ergebnisdateien wurde nicht genannt"
elif [ "$R1" = "$R2" ]; then
  bad "1: beide Auftraege zeigen auf DIESELBE Ergebnisdatei ($R1) -- und damit auf denselben Ankunftsmarker"
else
  ok "1: die beiden Auftraege haben verschiedene Ergebnisdateien"
fi
ANZ_AUFTRAG=$(ls -1 "$TESTHOME/.pi-workers/results/$Z1"/*.auftrag.txt 2>/dev/null | wc -l | tr -d ' ')
[ "$ANZ_AUFTRAG" -eq 2 ] \
  && ok "1: beide Auftragstexte sind erhalten geblieben" \
  || bad "1: nur $ANZ_AUFTRAG Auftragsdatei(en) -- der zweite Auftrag hat den ersten ueberschrieben"
EINS=0; ZWEI=0
for f in "$TESTHOME/.pi-workers/results/$Z1"/*.auftrag.txt; do
  grep -qF "SEKUNDE-EINS-$MARKE" "$f" 2>/dev/null && EINS=1
  grep -qF "SEKUNDE-ZWEI-$MARKE" "$f" 2>/dev/null && ZWEI=1
done
{ [ "$EINS" -eq 1 ] && [ "$ZWEI" -eq 1 ]; } \
  && ok "1: und jeder der beiden Texte ist einzeln wiederzufinden" \
  || bad "1: einer der beiden Auftragstexte fehlt (eins=$EINS zwei=$ZWEI)"
[ "$(zustellbett_empfang_zahl)" -eq 2 ] \
  && ok "1: beide Nachrichten sind bei der Sitzung angekommen" \
  || bad "1: nicht beide Nachrichten kamen an ($(zustellbett_empfang_zahl))"

# ── 2: der zweite Auftrag wird verschluckt ────────────────────────────────────
echo
echo "-- 2: dieselbe Sekunde, aber der zweite Auftrag wird verschluckt --"
zustellbett_panes_weg
zustellbett_leeren "$RECV"
SCHLUCK="$TESTHOME/schluckschalter"
rm -f -- "$SCHLUCK"
zustellbett_claude_inbox normal idle 0 "$SCHLUCK"
Z2="t2$MARKE"
A1="$(pi_lauf socket "$Z2" "VERSCHLUCKT-EINS-$MARKE")"
[ "$(zustellweg "$A1")" = SOCKET ] \
  && ok "2: der erste Auftrag ist belegt zugestellt" \
  || bad "2: schon der erste Auftrag scheiterte"
# Ab jetzt nimmt die Sitzung jede Nachricht entgegen und verschluckt sie.
: > "$SCHLUCK"
A2="$(pi_lauf socket "$Z2" "VERSCHLUCKT-ZWEI-$MARKE")"; RC=$?
[ "$RC" -ne 0 ] \
  && ok "2: der verschluckte zweite Auftrag ist ein lauter Fehlschlag (rc=$RC)" \
  || bad "2: Exit-Code 0 fuer einen Auftrag, der nie angekommen ist -- der Marker des ERSTEN wurde als Beleg gelesen"
[ "$(zustellweg "$A2")" = FEHLSCHLAG ] \
  && ok "2: und es wird kein Erfolg behauptet" \
  || bad "2: Erfolg behauptet: $(printf '%s' "$A2" | tail -2)"
# Die Gegenprobe: der zweite Auftragstext steht wirklich nirgends im Pane.
P="$(worker_pane "$Z2")"
if [ -z "$P" ]; then
  bad "2: der Worker-Pane ist nicht auffindbar -- die Gegenprobe faellt aus"
else
  tm capture-pane -p -J -S -2000 -t "$P" 2>/dev/null | grep -qF "VERSCHLUCKT-ZWEI-$MARKE" \
    && bad "2: der zweite Auftrag steht doch im Pane -- dieser Fall misst nicht, was er messen soll" \
    || ok "2: der zweite Auftragstext ist im Pane wirklich nirgends zu finden"
fi
[ "$(zustellbett_platzhalter "$Z2")" = weg ] \
  && ok "2: kein Platzhalter zurueckgeblieben" \
  || bad "2: '.laufend.md' steht noch da"

echo
echo "-- die echte Umgebung blieb unberuehrt --"
zustellbett_umgebung_pruefen "$Z1" "$Z2"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
