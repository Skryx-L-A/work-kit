#!/usr/bin/env bash
# Model registry of the kit: only models that exist on the laptop, pi's <provider>/<model>
# pairs, discovery of pi's models.json and kit-llm's catalog, the kit-llm endpoint override,
# and add-provider/remove-provider for other modules. Hermetic: own temporary HOME, links to
# the installed tools, no tmux, no network (the endpoint is a closed local port).
#
#   bash tests/test-models.sh [<bin dir>]     default: $HOME/.local/bin
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${1:-$HOME/.local/bin}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
[ -x "$BIN/wb-state" ] && [ -x "$BIN/pi-worker" ] || { echo "test-models: no workbench in $BIN" >&2; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/wb-models.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME/.local/bin" "$HOME/.claude/workbench" "$T/work"
for f in "$BIN"/*; do ln -s "$f" "$HOME/.local/bin/$(basename "$f")"; done
cp "$HERE/payload/shell/models.default.json" "$HOME/.claude/workbench/models.json"
unset KIT_LLM_BASE_URL KIT_LLM_PORT KIT_LLM_CONF KIT_DATA_DIR KIT_LLM_HOME TMUX TMUX_PANE
W="$HOME/.local/bin/wb-state"
PIJ="$HOME/.pi/agent/models.json"
# The build machine's private setup names (port/neutralise.py keeps them out of this file too).
private() { printf '%s' "$1" | python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from neutralise import leftovers; h = leftovers(sys.stdin.read()); print(" ".join(sorted(set(h)))); sys.exit(0 if h else 1)' "$HERE/port"; }
# A port nobody listens on: pi-ensure's context probe fails fast instead of reaching a server.
FREE_PORT=1
pijson() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$PIJ" "$1"; }

echo "== default registry lists only laptop models"
ids="$("$W" models list)"
if private "$ids" >/dev/null || printf '%s\n' "$ids" | grep -Eiq 'qwen3\.6|spark|mlx'; then
  bad "private model ids in the registry: $(private "$ids") $(printf '%s\n' "$ids" | grep -Ei 'spark|mlx' | tr '\n' ' ')"
else ok "no private model ids ($(printf '%s\n' "$ids" | grep -c .) models)"; fi
cat_file="$HERE/../15-local-llm/models.conf"
if [ -f "$cat_file" ]; then
  missing=""
  for id in $(grep -v '^#' "$cat_file" | cut -d'|' -f1); do
    printf '%s\n' "$ids" | grep -qx "$id" || missing="$missing $id"
  done
  [ -z "$missing" ] && ok "every 15-local-llm catalog model is registered for pi" || bad "catalog models missing:$missing"
fi
provs="$(python3 -c 'import json,sys; print(" ".join(p["id"] for p in json.load(open(sys.argv[1]))["providers"]))' "$HOME/.claude/workbench/models.json")"
case " $provs " in *" kit-llm "*) ok "provider kit-llm registered" ;; *) bad "no kit-llm provider ($provs)" ;; esac
if private "$provs" >/dev/null || case " $provs " in *" llamacpp "*|*mlx*) true ;; *) false ;; esac; then
  bad "Mac-only engines in the providers: $provs"; else ok "no Mac-only engines"; fi
"$W" models table | grep -q '`qwen3.5-4b`' && ok "routing table offers qwen3.5-4b" || bad "routing table lacks qwen3.5-4b"

echo "== model families"
for pair in 'opus claude-opus-5-5' 'sonnet claude-sonnet-5' 'fable claude-fable-5-1' \
            'sol gpt-6-sol' 'terra gpt-5.6-terra' 'luna gpt-6-luna' 'astra gpt-6-astra'; do
  family="${pair%% *}"; want="${pair#* }"
  got="$("$W" models get "$family" --field modelRef 2>/dev/null || true)"
  [ "$got" = "$want" ] && ok "$family resolves to its newest shipped model" \
    || bad "$family resolves to $got, expected $want"
done
python3 - "$HOME/.claude/workbench/models.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
h = {x['id']: x for x in d['harnesses']}
assert h['claude']['orchestratorDefaultModel'] == 'opus'
assert h['codex']['orchestratorDefaultModel'] == 'sol'
assert {x['aliases'][0] for x in h['codex']['modelFamilyAliases']} == {'sol', 'terra', 'luna', 'astra'}
PY
[ $? = 0 ] && ok "orchestrator defaults and Codex aliases are family names" \
  || bad "orchestrator defaults or Codex aliases are version-pinned"
"$W" models add '{"id":"codex-gpt-7-sol","label":"GPT-7 Sol","harness":"codex","provider":"chatgpt","modelRef":"gpt-7-sol","roles":["worker","orchestrator"],"maxEffort":"ultra","defaultEffort":"high","enabled":true}' >/dev/null \
  && [ "$("$W" models get sol --field modelRef)" = 'gpt-7-sol' ] \
  && ok "a newly discovered Sol generation wins the family alias" \
  || bad "newer Sol did not win the family alias"

echo "== pi-worker"
out="$("$BIN/pi-worker" w1 mac/qwen3.5-4b "$T/work" "task" 2>&1)"; rc=$?
if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q "unbekanntes Modell 'mac/qwen3.5-4b'"; then ok "unknown provider/model refused"
else bad "mac/qwen3.5-4b not refused (rc=$rc): $(printf '%s' "$out" | head -3)"; fi
checked_out="$out"
# A test HOME below the worktree can itself contain the maintainer's private name.
# Only the diagnostic, not the test fixture paths, is subject to the model-name check.
for fixture_path in "$T" "$BIN" "$HERE" "$(cd "$HERE/../../.." && pwd -P)"; do
  checked_out="${checked_out//"$fixture_path"/<fixture>}"
done
if private "$checked_out" >/dev/null; then bad "error text names private models"
else ok "error text names no private models"; fi
out="$(PI_WORKER_TEST_TROCKENLAUF=1 KIT_LLM_PORT="$FREE_PORT" "$HOME/.local/bin/pi-worker" w1 qwen3.5-4b "$T/work" "task" 2>&1)"
printf '%s' "$out" | grep -q 'Startzeile: pi --provider kit-llm --model qwen3.5-4b' \
  && ok "registry id qwen3.5-4b starts pi with provider kit-llm" || bad "registry id: $(printf '%s' "$out" | tail -2)"
[ "$(pijson 'd["providers"]["kit-llm"]["baseUrl"]')" = "http://127.0.0.1:$FREE_PORT/v1" ] \
  && ok "pi models.json gets kit-llm with the kit-llm port" || bad "kit-llm baseUrl: $(pijson 'd["providers"]["kit-llm"]["baseUrl"]')"
out="$(PI_WORKER_TEST_TROCKENLAUF=1 KIT_LLM_BASE_URL="http://127.0.0.1:$FREE_PORT/custom/v1" \
       "$HOME/.local/bin/pi-worker" w1 kit-llm/qwen3.5-2b "$T/work" "task" 2>&1)"
printf '%s' "$out" | grep -q 'Startzeile: pi --provider kit-llm --model qwen3.5-2b' \
  && ok "pair kit-llm/qwen3.5-2b accepted" || bad "pair kit-llm/qwen3.5-2b: $(printf '%s' "$out" | tail -2)"
[ "$(pijson 'd["providers"]["kit-llm"]["baseUrl"]')" = "http://127.0.0.1:$FREE_PORT/custom/v1" ] \
  && ok "KIT_LLM_BASE_URL overrides the endpoint" || bad "override: $(pijson 'd["providers"]["kit-llm"]["baseUrl"]')"
python3 - "$PIJ" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["providers"]["corp"] = {"baseUrl": "https://llm.example.invalid/v1", "api": "openai-completions",
                          "apiKey": "$CORP_KEY", "models": [{"id": "big-model"}, {"id": "org/small"}]}
json.dump(d, open(sys.argv[1], "w"), indent=2)
PY
out="$(PI_WORKER_TEST_TROCKENLAUF=1 "$HOME/.local/bin/pi-worker" w1 corp/org/small "$T/work" "task" 2>&1)"
printf '%s' "$out" | grep -q 'Startzeile: pi --provider corp --model org/small' \
  && ok "any provider/model of pi's models.json accepted" || bad "corp/org/small: $(printf '%s' "$out" | tail -2)"
[ "$(pijson 'd["providers"]["corp"]["baseUrl"]')" = "https://llm.example.invalid/v1" ] \
  && ok "a provider only pi knows stays as pi has it" || bad "corp provider changed"

echo "== discovery"
mkdir -p "$HOME/.local/share/work-kit/local-llm"
if [ -f "$cat_file" ]; then cp "$cat_file" "$HOME/.local/share/work-kit/local-llm/models.conf"; fi
out="$("$W" models discover pi kit-llm 2>&1)"
printf '%s' "$out" | grep -q '^pi: +2 neu' && ok "pi's models.json imported (corp: 2 models)" || bad "discover pi: $out"
"$W" models get pi-corp-org-small --field modelRef | grep -qx 'org/small' && ok "imported as pi-corp-org-small" || bad "pi-corp-org-small missing"
if [ -f "$cat_file" ]; then
  printf '%s' "$out" | grep -q '^kit-llm: +0 neu, 0 aktualisiert, -0 entfernt' && ok "kit-llm catalog matches the default registry" || bad "discover kit-llm: $out"
fi
out="$("$W" models discover pi kit-llm 2>&1)"
printf '%s' "$out" | grep -q '^pi: +0 neu' && ok "discovery is idempotent" || bad "second discover: $out"

echo "== add-provider / remove-provider"
A=(models add-provider --id acme-gw --kind openai --base-url https://gw.example.invalid/v1 --key-env ACME_KEY --owner test-owner)
"$W" "${A[@]}" --model gpt-x --model team/coder >/dev/null && "$W" "${A[@]}" --model gpt-x >/dev/null \
  && ok "add-provider twice (idempotent)" || bad "add-provider failed"
[ "$("$W" models list | grep -c '^pi-acme-gw-')" = 1 ] && ok "second call replaces the owner's models" || bad "models: $("$W" models list | grep acme)"
[ "$(pijson 'd["providers"]["acme-gw"]["apiKey"]')" = '$ACME_KEY' ] && ok "pi gets the key as env reference only" || bad "pi apiKey entry wrong"
"$W" models add-provider --id acme-gw --kind openai --base-url https://x.invalid/v1 --owner someone-else --model m >/dev/null 2>&1 \
  && bad "foreign owner could overwrite" || ok "foreign owner refused"
"$W" models add-provider --id kit-llm --kind local --base-url http://127.0.0.1:1/v1 --model m >/dev/null 2>&1 \
  && bad "kit-llm could be taken over" || ok "shipped provider not manageable from outside"
"$W" models remove-provider --id acme-gw --owner test-owner >/dev/null && "$W" models remove-provider --id acme-gw --owner test-owner >/dev/null \
  && ok "remove-provider twice (idempotent)" || bad "remove-provider failed"
[ "$("$W" models list | grep -c acme)" = 0 ] && [ "$(pijson '"acme-gw" in d["providers"]')" = False ] \
  && ok "provider gone from registry and pi" || bad "acme-gw left over"

echo
echo "test-models: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
