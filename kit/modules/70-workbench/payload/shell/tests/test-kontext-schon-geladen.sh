#!/usr/bin/env bash
# test-kontext-schon-geladen.sh -- wb-kontext darf Gewichte eines schon
# laufenden MLX-Servers nicht ein zweites Mal einrechnen -- aber NUR fuer die
# Stufe, die der Server WIRKLICH faehrt.
#
# ANLASS (Auftrag "kontextgewichte", gemessen 08.09.2026 19:09): der
# MLX-Server fuer lmgamma-27b lief bereits (wb-mlx-server, PID 98588, Port
# 8081, 14,95 GiB Gewichte geladen, Belegung "realisiert"). Trotzdem rechnete
# `pi-worker unterkante lmgamma ...` in seinem Aufruf `wb-kontext stufen ...
# --json` die Gewichte ERNEUT ein (bedarfGib 16.95 fuer 32k, frei 15.5 GiB,
# "passt: nein") und brach mit "passt nach dem freien Speicher nicht einmal
# die kleinste Kontextstufe -- kein Spawn" ab, obwohl die spaetere,
# tatsaechliche Buchung in pi-worker ("Eigene Sequenz buchen") fuer denselben
# Server korrekt nur 0,001 GiB (--ohne-sockel) bucht. Die Stufenwahl kannte
# den laufenden Server nicht, die Buchung schon -- zwei Rechnungen fuer
# dieselbe Frage.
#
# ZWEITE RUNDE, Gegenleser-Befund Punkt 4: die erste Fassung dieses Fixes
# entlastete faelschlich ALLE Stufen, nicht nur die, deren Tokenzahl dem
# laufenden Kontext entspricht -- ein Server bei 32768 Token deckt keine
# Anfrage bei 65536 nicht ab, die braucht einen echten Neustart mit vollen
# Gewichten. Dieser Test prueft deshalb ALLE DREI Stufen gegeneinander: nur
# 32768 (der gestellte "laufende Kontext") darf entlastet sein, 65536 und
# 131072 muessen die vollen Gewichte tragen. Die oberste 'gewichteGb'/
# 'gewichteQuelle' im JSON zeigen seit der zweiten Runde immer den realen,
# unentlasteten Wert (eine stufenunabhaengige Tatsache ueber das Modell) --
# die Entlastung steht jetzt nur noch in der 'bedarfQuelle' der betroffenen
# Stufe.
#
# HERMETISCH: kein echter Modellstart, kein echtes Laden -- Speicher ist
# knapp (Anweisung des Auftrags). `wb-mlx-server` und `check-resources`
# werden durch Stubs in einem eigenen $HOME ersetzt (dieselbe Isolation wie
# Konfig-Tests im Haus: HOME=$(mktemp -d)), `wb-belegung`/`wb-state` bleiben
# in diesem $HOME schlicht ABWESEND -- wb-kontext faellt dann auf seine
# eigene lokale Naeherung zurueck (siehe bedarf_wirklich()/plaetze_wirklich()
# in wb-kontext: liefert wb-belegung nichts, gilt die lokale Rechnung), genau
# der Pfad, der hier geprueft werden soll: berechne()s Stufen-Schleife und
# bereits_geladener_server().
set -uo pipefail

WK="${WB_KONTEXT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/wb-kontext}"
echo "Geprueft: $WK"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }

ARBEIT="$(mktemp -d)"
trap 'rm -rf "$ARBEIT"' EXIT

# Ein Modellverzeichnis, das wb-kontext wie ein echtes MLX-Modell liest:
# config.json fuer das native Maximum (natives_maximum_mlx()), eine
# .safetensors-Datei fuer die Gewichtegroesse (gewichte_gb()) -- SPARSE
# angelegt (truncate), damit "2 GiB Gewichte" keine 2 GiB echte Platte kostet.
MODELDIR="$ARBEIT/lmgamma-27b-fake"
mkdir -p "$MODELDIR"
cat > "$MODELDIR/config.json" <<'JSON'
{"max_position_embeddings": 131072}
JSON
truncate -s 2G "$MODELDIR/model.safetensors" || {
  echo "FEHLER: truncate -s 2G nicht verfuegbar -- Test kann nicht aufgebaut werden." >&2
  exit 1
}

# Freier Speicher: knapp genug, dass 2 GiB Gewichte + KV bei 32768 Token NICHT
# mehr passen (rechnerisch rund 4,19 GiB Bedarf), aber 0,001 GiB Gewichte +
# dieselbe KV (rund 2,19 GiB) SEHR WOHL passen. RESERVE_MIB steht in
# wb-kontext auf 0 (Nachtrag 27.08.2026), geht also direkt in den Vergleich.
FREI_MIB=4000

bin_aufsetzen() {   # <bin-verzeichnis>
  local bindir="$1"
  mkdir -p "$bindir"
  cat > "$bindir/check-resources" <<EOF
#!/usr/bin/env bash
echo '{"ram": {"free_mib": $FREI_MIB}}'
EOF
  chmod +x "$bindir/check-resources"
}

wk_stufen() {   # <home> [weitere Argumente fuer stufen] -> setzt WK_JSON, WK_STDERR, WK_RC
  local errdatei home="$1"; shift
  errdatei="$(mktemp)"
  WK_JSON="$(HOME="$home" python3 "$WK" stufen "$MODELDIR" --parallel 1 --denken low --json "$@" 2>"$errdatei")"
  WK_RC=$?
  WK_STDERR="$(cat "$errdatei")"; rm -f "$errdatei"
}

feld() {   # <json> <feld> -> Wert (json-kodiert) oder FEHLT
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get(sys.argv[2], 'FEHLT'))
" "$1" "$2" 2>/dev/null || echo FEHLT
}

stufe_feld() {   # <json> <tokens> <feld> -> Wert oder FEHLT
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
s = next((x for x in d['stufen'] if x['tokens'] == int(sys.argv[2])), None)
print(s[sys.argv[3]] if s is not None else 'FEHLT')
" "$1" "$2" "$3" 2>/dev/null || echo FEHLT
}

echo "== 1  Server laeuft bereits MIT diesem Modell, Kontext 32768 (realisiert) =="
HOME_A="$ARBEIT/home-laeuft"
BIN_A="$HOME_A/.local/bin"
bin_aufsetzen "$BIN_A"
cat > "$BIN_A/wb-mlx-server" <<EOF
#!/usr/bin/env bash
if [ "\$1" = status ]; then
  echo 'wb-mlx-server: laeuft (PID 98588, Port 8081), seit: Tue Sep  8 19:00:00 2026, Speicher: 15000 MiB'
  echo '  Modell: $MODELDIR'
  echo '  Entwerfer: keiner'
  echo '  Kontext gebucht: 32768'
  exit 0
fi
exit 1
EOF
chmod +x "$BIN_A/wb-mlx-server"

wk_stufen "$HOME_A"
if [ "$WK_RC" -ne 0 ]; then
  bad "Server laeuft: wb-kontext brach ab" "$WK_STDERR"
else
  gewichte_oben="$(feld "$WK_JSON" gewichteGb)"
  quelle_oben="$(feld "$WK_JSON" gewichteQuelle)"
  bedarf32="$(stufe_feld "$WK_JSON" 32768 bedarfGib)"
  passt32="$(stufe_feld "$WK_JSON" 32768 passt)"
  quelle32="$(stufe_feld "$WK_JSON" 32768 bedarfQuelle)"
  bedarf64="$(stufe_feld "$WK_JSON" 65536 bedarfGib)"
  quelle64="$(stufe_feld "$WK_JSON" 65536 bedarfQuelle)"
  bedarf128="$(stufe_feld "$WK_JSON" 131072 bedarfGib)"
  if [ "$bedarf32" = FEHLT ] || [ "$bedarf64" = FEHLT ] || [ "$bedarf128" = FEHLT ]; then
    bad "Server laeuft: eine der drei Stufen fehlt in der Ausgabe" "$WK_JSON"
  else
    fehler=""
    # Die oberste gewichteGb/gewichteQuelle bleibt seit der zweiten Runde
    # IMMER der reale, unentlastete Wert -- eine stufenunabhaengige Tatsache.
    awk -v g="$gewichte_oben" 'BEGIN{exit !(g+0 > 1.9 && g+0 < 2.1)}' \
      || fehler="oberstes gewichteGb=$gewichte_oben, erwartet rund 2.0 (der reale Wert, unabhaengig von jeder Stufe)"
    case "$quelle_oben" in *"schon geladen"*) fehler="${fehler:+$fehler; }oberste gewichteQuelle nennt faelschlich 'schon geladen': $quelle_oben (das gehoert seit der zweiten Runde nur noch in die Stufe)" ;; esac
    # NUR Stufe 32768 ist entlastet.
    awk -v b="$bedarf32" 'BEGIN{exit !(b+0 < 2.3)}' \
      || fehler="${fehler:+$fehler; }Stufe 32768: bedarfGib=$bedarf32, erwartet nahe 2.19 (KV allein, Gewichte entlastet)"
    case "$quelle32" in *"schon geladen"*"PID 98588"*"Kontext 32768"*) : ;; *) fehler="${fehler:+$fehler; }Stufe 32768: bedarfQuelle nennt weder 'schon geladen' noch 'PID 98588' noch 'Kontext 32768': $quelle32" ;; esac
    [ "$passt32" = True ] || fehler="${fehler:+$fehler; }Stufe 32768: passt=$passt32, erwartet True bei ${FREI_MIB} MiB frei"
    # Stufe 65536 und 131072 sind NICHT entlastet -- volle Gewichte (2 GiB) plus KV.
    awk -v b="$bedarf64" 'BEGIN{exit !(b+0 > 6.0)}' \
      || fehler="${fehler:+$fehler; }Stufe 65536: bedarfGib=$bedarf64, erwartet ueber 6 (volle Gewichte + KV -- ein anderer Kontext braucht einen echten Neustart)"
    case "$quelle64" in *"schon geladen"*) fehler="${fehler:+$fehler; }Stufe 65536: bedarfQuelle nennt faelschlich 'schon geladen', obwohl der Server bei 32768 laeuft: $quelle64" ;; esac
    awk -v b="$bedarf128" 'BEGIN{exit !(b+0 > 10.0)}' \
      || fehler="${fehler:+$fehler; }Stufe 131072: bedarfGib=$bedarf128, erwartet ueber 10 (volle Gewichte + KV)"
    if [ -n "$fehler" ]; then
      bad "Server laeuft: $fehler" "$WK_JSON"
    else
      ok "Server laeuft: oben gewichteGb=$gewichte_oben (real, unentlastet); Stufe 32768 bedarfGib=$bedarf32 (entlastet, passt=$passt32); Stufe 65536/131072 voll ($bedarf64/$bedarf128)"
    fi
  fi
fi

echo "== 2  Gegenprobe: kein laufender Server fuer dieses Modell -- Gewichte zaehlen wie bisher =="
HOME_B="$ARBEIT/home-inaktiv"
BIN_B="$HOME_B/.local/bin"
bin_aufsetzen "$BIN_B"
cat > "$BIN_B/wb-mlx-server" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = status ]; then
  echo 'wb-mlx-server: nicht aktiv (Port 8081 frei)'
  exit 0
fi
exit 1
EOF
chmod +x "$BIN_B/wb-mlx-server"

wk_stufen "$HOME_B"
if [ "$WK_RC" -ne 0 ]; then
  bad "Kein Server: wb-kontext brach ab" "$WK_STDERR"
else
  gewichte="$(feld "$WK_JSON" gewichteGb)"
  quelle="$(feld "$WK_JSON" gewichteQuelle)"
  bedarf="$(stufe_feld "$WK_JSON" 32768 bedarfGib)"
  passt="$(stufe_feld "$WK_JSON" 32768 passt)"
  if [ "$gewichte" = FEHLT ] || [ "$bedarf" = FEHLT ]; then
    bad "Kein Server: gewichteGb oder Stufe 32768 fehlt in der Ausgabe" "$WK_JSON"
  else
    fehler=""
    awk -v g="$gewichte" 'BEGIN{exit !(g+0 > 1.9 && g+0 < 2.1)}' || fehler="gewichteGb=$gewichte, erwartet rund 2.0 (die echte Dateigroesse)"
    case "$quelle" in *"schon geladen"*) fehler="${fehler:+$fehler; }gewichteQuelle nennt faelschlich 'schon geladen': $quelle" ;; esac
    [ "$passt" = False ] || fehler="${fehler:+$fehler; }passt=$passt, erwartet False -- volle Gewichte + KV muessen bei ${FREI_MIB} MiB frei ueber die Grenze gehen"
    if [ -n "$fehler" ]; then
      bad "Kein Server: $fehler" "$WK_JSON"
    else
      ok "Kein Server: gewichteGb=$gewichte, Quelle='$quelle', Stufe 32768 bedarfGib=$bedarf, passt=$passt (unveraendertes Verhalten)"
    fi
  fi
fi

echo "== 3  Server laeuft, aber MIT Entwerfer -- ohne angefragten Entwerfer keine Entlastung =="
# Gegenleser-Befund Punkt 2: der Entwerferzustand muss mitverglichen werden,
# sonst wird ein Server, der einen Entwerfer traegt, faelschlich fuer eine
# entwerferlose Anfrage als "schon geladen" gehalten (oder umgekehrt).
HOME_C="$ARBEIT/home-mit-entwerfer"
BIN_C="$HOME_C/.local/bin"
bin_aufsetzen "$BIN_C"
cat > "$BIN_C/wb-mlx-server" <<EOF
#!/usr/bin/env bash
if [ "\$1" = status ]; then
  echo 'wb-mlx-server: laeuft (PID 55001, Port 8081), seit: Tue Sep  8 19:00:00 2026, Speicher: 15000 MiB'
  echo '  Modell: $MODELDIR'
  echo '  Entwerfer: /pfad/zum/entwerfer (mlx-dspark, spekulatives Decoding aktiv, --parallel = Prompt-Cache-Plaetze)'
  echo '  Kontext gebucht: 32768'
  exit 0
fi
exit 1
EOF
chmod +x "$BIN_C/wb-mlx-server"

wk_stufen "$HOME_C"
if [ "$WK_RC" -ne 0 ]; then
  bad "Server mit Entwerfer: wb-kontext brach ab" "$WK_STDERR"
else
  quelle32="$(stufe_feld "$WK_JSON" 32768 bedarfQuelle)"
  case "$quelle32" in
    *"schon geladen"*) bad "Server mit Entwerfer: Stufe 32768 faelschlich als 'schon geladen' fuer eine Anfrage OHNE Entwerfer erkannt" "$quelle32" ;;
    *) ok "Server mit Entwerfer: Stufe 32768 bleibt unentlastet fuer eine Anfrage ohne Entwerfer (Entwerferzustand verglichen, kein Ueber-Match)" ;;
  esac
fi

echo "== 4  Server MIT Entwerfer, Anfrage ueber den PFAD mit Entwerfergewichten -- Entlastung greift =="
# Nachtrag 2026-09-10, gemessen: pi-worker uebergibt den Modell-PFAD, die
# Registry-Aufloesung liefert dann keine Bauart (vorhersage=None), und der
# Entwerfervergleich verwarf die Entlastung -- der Spawn brach mit "passt nach
# dem freien Speicher nicht einmal die kleinste Kontextstufe" ab, waehrend der
# Server das Modell samt Entwerfer laengst hielt. Mit --entwerfer-gewichte-gb
# hat der Aufrufer den Entwerfer ausgesprochen; die Stufe des Servers ist dann
# entlastet, die anderen nicht.
wk_stufen "$HOME_C" --entwerfer-gewichte-gb 0.25
if [ "$WK_RC" -ne 0 ]; then
  bad "Pfad mit Entwerfergewichten: wb-kontext brach ab" "$WK_STDERR"
else
  quelle32="$(stufe_feld "$WK_JSON" 32768 bedarfQuelle)"
  quelle64="$(stufe_feld "$WK_JSON" 65536 bedarfQuelle)"
  case "$quelle32" in
    *"schon geladen"*"PID 55001"*) ok "Pfad mit Entwerfergewichten: Stufe 32768 entlastet (Server mit Entwerfer, Bauart aus dem Pfad unbekannt, Entwerfer vom Aufrufer ausgesprochen)" ;;
    *) bad "Pfad mit Entwerfergewichten: Stufe 32768 NICHT entlastet -- der gemessene Spawn-Abbruch vom 2026-09-10" "$quelle32" ;;
  esac
  case "$quelle64" in
    *"schon geladen"*) bad "Pfad mit Entwerfergewichten: Stufe 65536 faelschlich entlastet, der Server laeuft bei 32768" "$quelle64" ;;
    *) ok "Pfad mit Entwerfergewichten: Stufe 65536 bleibt unentlastet" ;;
  esac
fi

echo
echo "Ergebnis: $pass ok, $fail FAIL"
[ "$fail" -eq 0 ]
