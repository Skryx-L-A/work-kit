#!/usr/bin/env bash
# test-kontext-kv-namen.sh -- eine echte, GEMESSENE KV-Zahl muss unter dem
# Namen erreichbar sein, den ein Aufrufer wirklich benutzt.
#
# ANLASS (Pruefer-Befund N2, 19.08.2026 abends): die Messstrecke trug frische
# KV-Werte unter von Hand gebildeten Kunstnamen ein (Beispiel:
# "qwen3-1.7b-ollama-q4km" fuer den echten modelRef 'qwen3:1.7b' aus
# ~/.local/state/wb-belegung/kv-bedarf.json). `wb-kontext stufen qwen3:1.7b`
# suchte nur exakt und fiel deshalb auf den viel teureren Ersatzwert zurueck
# -- die Messung war da, nur nicht angeschlossen. Fix: kv_ollama_kunstname()
# in wb-kontext erkennt den festen Namensteil "-ollama-" und normalisiert den
# Doppelpunkt im Ollama-Tag zu einem Bindestrich, um den Kunstnamen trotzdem
# zu finden.
#
# HERMETISCH, ANDERS ALS test-kontext-messungen.sh: dieser Test prueft den
# NAMENS-Abgleich selbst, nicht eine reale Messung -- ein eigenes HOME mit
# einer synthetischen kv-bedarf.json reicht dafuer, und macht den Test
# unabhaengig davon, ob die reale Datei den alten Kunstnamen gerade noch
# traegt oder (wie inzwischen beobachtet) schon auf den echten Namen
# umgestellt wurde. `check-resources` und `wb-state` werden als echte Kopien
# mitgegeben (wb-kontext braucht beide fuer frei_mib()/resolve()), 'ollama'
# NICHT -- der gesuchte Pfad ist ausschliesslich der Registry-kv-Treffer,
# kein Architektur-Fallback.
#
# KORREKTUR 2026-08-20: die Hermetik-Behauptung darueber stimmte NICHT. Das
# eigene HOME nahm zwar die kv-bedarf.json mit, aber KEINE Registry -- und
# ohne Registry-Eintrag loeste `wb-kontext` den Namen 'qwen3:1.7b' ueber
# `ollama list` auf der echten Maschine auf. Der Test hing damit an einem
# laufenden Ollama-Dienst, entgegen genau dem Satz, der das ausschloss.
# Aufgefallen ist es, als der Dienst zum Speichersparen gestoppt wurde: der
# Test wurde rot, ohne dass sich eine Zeile Code geaendert hatte. Seitdem
# legt der Aufbau unten eine eigene Mini-Registry an, die den Eintrag
# mitbringt -- damit ist der Test das, was der Kommentar immer versprach.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WK="${WB_KONTEXT:-$REPO/wb-kontext}"
echo "Geprueft: $WK"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }

TESTHOME="$(mktemp -d)"
trap 'rm -rf "$TESTHOME"' EXIT
mkdir -p "$TESTHOME/.local/state/wb-belegung" "$TESTHOME/.local/bin"
cat > "$TESTHOME/.local/state/wb-belegung/kv-bedarf.json" <<'EOF'
{
  "version": 1,
  "modelle": {
    "qwen3-1.7b-ollama-q4km": {
      "mib_je_token": 0.06581,
      "herkunft": "gemessen",
      "wann": "2026-08-19",
      "notiz": "Fixture, Nachbildung des echten Eintrags aus Pruefer-Befund N2"
    }
  }
}
EOF
cp "$REPO/wb-state" "$REPO/check-resources" "$TESTHOME/.local/bin/"
chmod +x "$TESTHOME/.local/bin/wb-state" "$TESTHOME/.local/bin/check-resources"

# Stellvertreter fuer 'ollama' (2026-08-20). wb-kontext loest 'qwen3:1.7b' ueber
# `ollama list` auf -- ueber die Registry geht es NICHT, denn `wb-state models get`
# sucht ausschliesslich ueber die id ('pi-qwen3-1-7b'), nicht ueber den modelRef.
# Ohne diesen Stellvertreter braucht der Test einen laufenden Ollama-Dienst, und
# genau daran ist er am 2026-08-20 rot geworden, als der Dienst zum Speichersparen
# gestoppt wurde. Der Stellvertreter meldet dasselbe wie der echte Dienst und laesst
# den geprueften Pfad unveraendert.
cat > "$TESTHOME/.local/bin/ollama" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  list)
    printf 'NAME\tID\tSIZE\tMODIFIED\n'
    printf 'qwen3:1.7b\tabc123\t1.4 GB\t2 days ago\n'
    exit 0 ;;
  show)
    # wb-kontext liest hieraus das native Maximum (Muster: "context length <zahl>").
    printf '  Model\n'
    printf '    architecture        qwen3\n'
    printf '    parameters          1.7B\n'
    printf '    context length      40960\n'
    printf '    embedding length    2048\n'
    printf '    quantization        Q4_K_M\n'
    exit 0 ;;
esac
exit 1
EOF
chmod +x "$TESTHOME/.local/bin/ollama"

echo "== 1  Kunstname 'qwen3-1.7b-ollama-q4km' wird fuer den echten Aufruf 'qwen3:1.7b' gefunden =="
out="$(HOME="$TESTHOME" PATH="$TESTHOME/.local/bin:$PATH" python3 "$WK" stufen qwen3:1.7b --parallel 1 --denken low --json 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  bad "wb-kontext brach ab" "$out"
else
  kv="$(printf '%s' "$out" | python3 -c "import json,sys; print(json.load(sys.stdin)['kvMibProToken'])" 2>/dev/null || echo FEHLER)"
  if [ "$kv" = "0.06581" ]; then
    ok "kvMibProToken = 0.06581 -- die echte Messung kam an, nicht der Ersatzwert"
  else
    bad "kvMibProToken = '$kv', erwartet 0.06581 -- die Messung ist nicht angeschlossen" "$out"
  fi
fi

echo "== 2  Ein Modell OHNE Eintrag erfindet keinen Treffer (kein Ueber-Match des Namensabgleichs) =="
out="$(HOME="$TESTHOME" PATH="$TESTHOME/.local/bin:$PATH" python3 "$WK" stufen ganzunbekannt:9b --parallel 1 --denken low --json 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "weder"; then
  ok "ein Modell, das weder Registry noch Ollama kennt, bricht sauber ab -- die Namensaufloesung erfindet keine Treffer"
else
  bad "unerwartetes Verhalten fuer ein unbekanntes Modell (rc=$rc)" "$out"
fi

echo
echo "Ergebnis: $pass ok, $fail FAIL"
[ "$fail" -eq 0 ]
