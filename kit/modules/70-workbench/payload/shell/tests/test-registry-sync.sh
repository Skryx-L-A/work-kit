#!/bin/bash
# test-registry-sync.sh — wb-registry-sync: geteilte Eintraege (Provider ohne
# lokalen Prozess) werden zwischen zwei models.json-Dateien zusammengefuehrt,
# lokale Eintraege (ollama/mlx/llamacpp/…) bleiben unberuehrt, auch wenn
# derselbe id auf beiden Seiten mit abweichenden Feldern steht.
#
# Auftrag 20260910-175010 (Registry-Abgleich Mac/host2). Der Transport ist in
# diesem Test NIE ssh, sondern --fremd <datei> -- eine gewoehnliche Datei
# spielt die Gegenseite, genau der Parameter, den das Werkzeug dafuer
# vorsieht (siehe Kopfkommentar von wb-registry-sync).
#
# ISOLATION: eigenes HOME (mktemp -d), also eigene
# ~/.claude/workbench/models.json UND eigener ~/.local/trash-snapshots-Pfad --
# die echten Registries beider Maschinen werden nie gelesen oder geschrieben.
# Kein tmux, keine Worker: dieses Werkzeug startet keinen Prozess ausser sich
# selbst, ssh wird durch --fremd ersetzt, also entfaellt die sonst noetige
# Isolation gegen die Live-Session komplett.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
SYNC="$REPO/wb-registry-sync"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

echo "Geprueft: Repo-Stand aus $REPO"
[ -x "$SYNC" ] || { echo "wb-registry-sync fehlt oder ist nicht ausfuehrbar — Test kann nicht laufen." >&2; exit 1; }

SPIEL="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-registry-sync-test.XXXXXX")" && pwd)"
cleanup() {
  case "$SPIEL" in
    /tmp/wb-registry-sync-test.*|/private/tmp/wb-registry-sync-test.*|/var/folders/*/wb-registry-sync-test.*)
      rm -rf "$SPIEL" ;;
    *) echo "WARNUNG: SPIEL='$SPIEL' sieht nicht nach einem Testverzeichnis aus — NICHT geloescht." >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

TESTHOME="$SPIEL/heim"
mkdir -p "$TESTHOME/.claude/workbench"
LOKAL="$TESTHOME/.claude/workbench/models.json"
FREMD="$SPIEL/host2.json"

# ── Fixtures ─────────────────────────────────────────────────────────────────
# LOKAL spielt "Mac": ein Cloud-Eintrag, den die Gegenseite noch nicht kennt,
# UND ein lokaler ollama-Eintrag mit einem Mac-eigenen Kontextfenster.
python3 - "$LOKAL" <<'PY'
import json, sys
json.dump({
    "version": 1,
    "providers": [
        {"id": "openrouter", "label": "OpenRouter", "kind": "cloud"},
        {"id": "ollama", "label": "Ollama (lokal)", "kind": "local"},
    ],
    "harnesses": [{"id": "aider", "label": "Aider", "command": "aider"}],
    "models": [
        {"id": "aider-openrouter-nur-mac", "harness": "aider", "provider": "openrouter",
         "modelRef": "x/mac-only", "discoveredAt": "2026-09-01T00:00:00Z"},
        {"id": "aider-ollama-lmalpha-35b", "harness": "aider", "provider": "ollama",
         "modelRef": "ollama/lmalpha:35b", "contextWindow": 131072},
        {"id": "shared-conflict", "harness": "aider", "provider": "openrouter",
         "modelRef": "x/z", "updated": "2026-09-05T00:00:00Z", "label": "mac-fassung, aelter"},
    ],
}, open(sys.argv[1], "w"), ensure_ascii=False, indent=2)
PY

# FREMD spielt "host2": ein anderer Cloud-Eintrag, ein anderer lokaler
# ollama-Eintrag (ANDERES Kontextfenster als auf der Mac-Seite -- das darf
# beim Merge nicht angefasst werden), und dieselbe geteilte Kennung wie oben
# mit NEUEREM Zeitstempel -- die muss gewinnen.
python3 - "$FREMD" <<'PY'
import json, sys
json.dump({
    "version": 1,
    "providers": [
        {"id": "openrouter", "label": "OpenRouter", "kind": "cloud"},
        {"id": "ollama", "label": "Ollama (lokal)", "kind": "local"},
    ],
    "harnesses": [{"id": "aider", "label": "Aider", "command": "aider"}],
    "models": [
        {"id": "aider-openrouter-nur-host2", "harness": "aider", "provider": "openrouter",
         "modelRef": "x/host2-only", "discoveredAt": "2026-09-02T00:00:00Z"},
        {"id": "aider-ollama-lmalpha-35b", "harness": "aider", "provider": "ollama",
         "modelRef": "ollama/lmalpha:35b", "contextWindow": 65536},
        {"id": "host2-ollama-nur-hier", "harness": "aider", "provider": "ollama",
         "modelRef": "ollama/nur-host2"},
        {"id": "shared-conflict", "harness": "aider", "provider": "openrouter",
         "modelRef": "x/z", "updated": "2026-09-08T00:00:00Z", "label": "host2-fassung, neuer"},
    ],
}, open(sys.argv[1], "w"), ensure_ascii=False, indent=2)
PY

cksum_lokal_vorher="$(md5 -q "$LOKAL" 2>/dev/null || md5sum "$LOKAL" | cut -d' ' -f1)"
cksum_fremd_vorher="$(md5 -q "$FREMD" 2>/dev/null || md5sum "$FREMD" | cut -d' ' -f1)"

feld() { # feld <datei> <id> <feldname> -- druckt ein Feld eines Modell-Eintrags, "" wenn er fehlt
  HOME="$TESTHOME" python3 - "$1" "$2" "$3" <<'PY'
import json, sys
pfad, mid, feld = sys.argv[1:4]
try:
    d = json.load(open(pfad))
except Exception:
    print(""); sys.exit()
for m in d.get("models", []):
    if m.get("id") == mid:
        print(m.get(feld, "") if feld != "__da__" else "ja")
        sys.exit()
print("")
PY
}

# ── 1. --dry-run: nichts geschrieben, kein Schnappschuss ───────────────────
export HOME="$TESTHOME"
out_dry="$("$SYNC" host2 --dry-run --fremd "$FREMD" 2>&1)"
rc_dry=$?
if [ "$rc_dry" -eq 0 ]; then ok "--dry-run: Exit 0"; else bad "--dry-run: Exit 0" "war $rc_dry"; fi

cksum_lokal_nach="$(md5 -q "$LOKAL" 2>/dev/null || md5sum "$LOKAL" | cut -d' ' -f1)"
cksum_fremd_nach="$(md5 -q "$FREMD" 2>/dev/null || md5sum "$FREMD" | cut -d' ' -f1)"
if [ "$cksum_lokal_vorher" = "$cksum_lokal_nach" ]; then ok "--dry-run laesst lokale Datei unveraendert"
else bad "--dry-run laesst lokale Datei unveraendert" "Datei wurde geschrieben"; fi
if [ "$cksum_fremd_vorher" = "$cksum_fremd_nach" ]; then ok "--dry-run laesst Fremd-Datei unveraendert"
else bad "--dry-run laesst Fremd-Datei unveraendert" "Datei wurde geschrieben"; fi
if [ ! -d "$TESTHOME/.local/trash-snapshots" ]; then ok "--dry-run legt keinen Schnappschuss an"
else bad "--dry-run legt keinen Schnappschuss an" "$(find "$TESTHOME/.local/trash-snapshots" -type f)"; fi
case "$out_dry" in
  *"nichts geschrieben"*) ok "--dry-run sagt im Text, dass nichts geschrieben wurde" ;;
  *) bad "--dry-run sagt im Text, dass nichts geschrieben wurde" "$out_dry" ;;
esac

# ── 2. echter Lauf ───────────────────────────────────────────────────────────
out_echt="$("$SYNC" host2 --fremd "$FREMD" 2>&1)"
rc_echt=$?
if [ "$rc_echt" -eq 0 ]; then ok "echter Lauf: Exit 0"; else bad "echter Lauf: Exit 0" "war $rc_echt: $out_echt"; fi

# nur-Mac-Cloud-Eintrag landet auf host2
if [ "$(feld "$FREMD" aider-openrouter-nur-mac __da__)" = "ja" ]; then
  ok "nur-Mac-Cloud-Eintrag landet auf der Fremd-Seite (host2)"
else
  bad "nur-Mac-Cloud-Eintrag landet auf der Fremd-Seite (host2)" "fehlt in $FREMD"
fi
# und umgekehrt: nur-host2-Cloud-Eintrag landet lokal
if [ "$(feld "$LOKAL" aider-openrouter-nur-host2 __da__)" = "ja" ]; then
  ok "nur-host2-Cloud-Eintrag landet lokal"
else
  bad "nur-host2-Cloud-Eintrag landet lokal" "fehlt in $LOKAL"
fi

# host2-Ollama-Eintrag bleibt auf host2, kommt NICHT auf den Mac
if [ "$(feld "$LOKAL" host2-ollama-nur-hier __da__)" = "" ]; then
  ok "host2-eigener Ollama-Eintrag kommt NICHT auf die lokale (Mac-)Seite"
else
  bad "host2-eigener Ollama-Eintrag kommt NICHT auf die lokale (Mac-)Seite" "steht jetzt in $LOKAL"
fi
if [ "$(feld "$FREMD" host2-ollama-nur-hier __da__)" = "ja" ]; then
  ok "host2-eigener Ollama-Eintrag bleibt auf host2 stehen"
else
  bad "host2-eigener Ollama-Eintrag bleibt auf host2 stehen" "fehlt jetzt sogar dort"
fi

# lokale Eintraege mit demselben id auf beiden Seiten behalten ihre EIGENEN,
# abweichenden Felder -- keine Vermischung der Kontextfenster.
fenster_lokal="$(feld "$LOKAL" aider-ollama-lmalpha-35b contextWindow)"
fenster_fremd="$(feld "$FREMD" aider-ollama-lmalpha-35b contextWindow)"
if [ "$fenster_lokal" = "131072" ] && [ "$fenster_fremd" = "65536" ]; then
  ok "gleichnamiger lokaler Ollama-Eintrag behaelt je Maschine sein eigenes Kontextfenster"
else
  bad "gleichnamiger lokaler Ollama-Eintrag behaelt je Maschine sein eigenes Kontextfenster" \
      "lokal=$fenster_lokal fremd=$fenster_fremd (erwartet 131072/65536)"
fi

# geteilter Eintrag mit zwei Fassungen: die neuere (host2, 09-08) gewinnt, auf
# BEIDEN Seiten, und der Lauf meldet den Konflikt statt ihn zu verschweigen.
label_lokal="$(feld "$LOKAL" shared-conflict label)"
label_fremd="$(feld "$FREMD" shared-conflict label)"
if [ "$label_lokal" = "host2-fassung, neuer" ] && [ "$label_fremd" = "host2-fassung, neuer" ]; then
  ok "Konflikt: neuere Fassung (host2) gewinnt auf beiden Seiten"
else
  bad "Konflikt: neuere Fassung (host2) gewinnt auf beiden Seiten" \
      "lokal='$label_lokal' fremd='$label_fremd'"
fi
case "$out_echt" in
  *"shared-conflict"*"neuer"*) ok "Konflikt wird im Laufbericht genannt, nicht still geloest" ;;
  *) bad "Konflikt wird im Laufbericht genannt, nicht still geloest" "$out_echt" ;;
esac

# Schnappschuss liegt, mit dem Stand VOR dem Schreiben (die aeltere,
# 09-05-Fassung von shared-conflict muss darin noch stehen).
SNAP_DIR="$(find "$TESTHOME/.local/trash-snapshots" -maxdepth 1 -type d -name '*-registry' | head -1)"
if [ -n "$SNAP_DIR" ] && [ -n "$(find "$SNAP_DIR" -name '*models-lokal.json')" ]; then
  ok "Schnappschuss-Verzeichnis liegt, mit lokaler Vor-Lauf-Kopie"
else
  bad "Schnappschuss-Verzeichnis liegt, mit lokaler Vor-Lauf-Kopie" "gefunden: $SNAP_DIR"
fi
snap_datei="$(find "$SNAP_DIR" -name '*models-lokal.json' 2>/dev/null | head -1)"
if [ -n "$snap_datei" ] && grep -q "mac-fassung, aelter" "$snap_datei"; then
  ok "Schnappschuss traegt den Stand VOR dem Merge (aeltere Fassung noch drin)"
else
  bad "Schnappschuss traegt den Stand VOR dem Merge (aeltere Fassung noch drin)" "$snap_datei"
fi

echo
echo "== $PASS ok, $FAIL FAIL =="
[ "$FAIL" -eq 0 ]
