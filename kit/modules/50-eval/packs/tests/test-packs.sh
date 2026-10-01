#!/usr/bin/env bash
# Offline test of the three packs with fake providers: graders accept good and reject bad
# answers, the engine runner benchmarks a fake streaming server, the harness runner isolates
# tasks in temp repos, compare.py renders the tables. No model, no network.
# EVALKIT: evalkit command (default: evalkit on PATH, else `uv run --project <50-eval> evalkit`).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKS="$(cd "$HERE/.." && pwd)"
MOD="$(cd "$PACKS/.." && pwd)"
if [ -z "${EVALKIT:-}" ]; then
  if command -v evalkit >/dev/null 2>&1; then EVALKIT=evalkit; else EVALKIT="uv run --project $MOD evalkit"; fi
fi
export EVALKIT
W="$(mktemp -d)"
# shellcheck disable=SC2329  # used by trap
cleanup() { if [ -f "$W/fake.pid" ]; then kill "$(cat "$W/fake.pid")" 2>/dev/null || true; fi; rm -rf "$W"; }
trap cleanup EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if (set +o pipefail; eval "$2"); then ok "$1"; else bad "$1"; fi; }
# shellcheck disable=SC2329  # used inside eval
rate() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["summary"]["pass_rate"])' "$1"; }
read -r -a EK <<<"$EVALKIT"

# models pack
"${EK[@]}" run "$PACKS/models/suite.yaml" -p fake --out "$W/fake.json" --no-save -q >/dev/null 2>&1 || true
"${EK[@]}" run "$PACKS/models/suite.yaml" -p fake-bad --out "$W/bad.json" --no-save -q >/dev/null 2>&1 || true
check "models: fake passes every case" "[ \"\$(rate '$W/fake.json')\" = 1.0 ]"
check "models: fake-bad fails every case" "[ \"\$(rate '$W/bad.json')\" = 0.0 ]"
check "models: default run without a server is a provider error, not a crash" \
  "KIT_LLM_BASE_URL=http://127.0.0.1:9/v1 \"\${EK[@]}\" run '$PACKS/models/suite.yaml' -c en-sql --out '$W/down.json' --no-save -q >/dev/null 2>&1; python3 -c 'import json; r=json.load(open(\"$W/down.json\")); assert r[\"runs\"][0][\"error\"]'"
check "checks.py sql rejects a wrong query" "! echo 'SELECT customer, amount AS total FROM orders' | python3 '$PACKS/models/checks.py' sql >/dev/null"
check "checks.py json-fields reads fenced JSON" "printf '\`\`\`json\n{\"a\": \"1,0\", \"b\": 2}\n\`\`\`' | python3 '$PACKS/models/checks.py' json-fields b=2 >/dev/null"
out="$(bash "$PACKS/models/run.sh" --providers fake,fake-bad -n 1 --out "$W/mrun" 2>&1)"
check "models run.sh writes comparison.md" "grep -q '| fake | fake | 13 | 100% |' '$W/mrun/comparison.md' && grep -q '| fake-bad | fake-bad | 13 | 0% |' '$W/mrun/comparison.md'"
check "models run.sh refuses --models without kit-llm" "KIT_LLM=/nonexistent/kit-llm bash '$PACKS/models/run.sh' --models x --out '$W/m2' >/dev/null 2>&1; [ \$? -ne 0 ]"

# engines pack with a fake streaming server
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
cat >"$W/engines.conf" <<CONF
# test config
fake|http://127.0.0.1:$port/v1|fake-model|python3 $PACKS/lib/fake_openai.py --port $port --delay 0.01 --answers $PACKS/models/fake-answers.json >/dev/null 2>&1 & echo \$! > $W/fake.pid|kill \$(cat $W/fake.pid)
missing|http://127.0.0.1:9/v1|x|false|-
CONF
out="$(bash "$PACKS/engines/run.sh" --config "$W/engines.conf" --requests 3 --max-tokens 16 --out "$W/erun" 2>&1)" || { bad "engines run.sh exits 0"; echo "$out" | tail -5; }
check "engines: bench json" "python3 -c 'import json; d=json.load(open(\"$W/erun/fake.bench.json\")); s=d[\"summary\"]; assert s[\"ok\"]==3 and s[\"decode_tok_s_mean\"] and s[\"tokens_reported\"]'"
check "engines: quality subset passes on the fake" "[ \"\$(rate '$W/erun/fake.json')\" = 1.0 ]"
check "engines: comparison has throughput and quality" "grep -q '^| fake | 3 | 3 |' '$W/erun/comparison.md' && grep -q '| fake | local | 6 | 100% |' '$W/erun/comparison.md'"
check "engines: failing start is skipped" "grep -q 'engine missing: start failed, skipped' <<<\"\$out\""
check "engines: fake server stopped" "! kill -0 \$(cat '$W/fake.pid') 2>/dev/null"

# harnesses pack
bash "$PACKS/harnesses/run.sh" --harnesses fake-good,fake-noop --out "$W/hrun" >/dev/null 2>&1 || bad "harness run.sh exits 0"
check "harnesses: fake-good passes all tasks" "[ \"\$(rate '$W/hrun/fake-good.json')\" = 1.0 ]"
check "harnesses: fake-noop fails all tasks" "[ \"\$(rate '$W/hrun/fake-noop.json')\" = 0.0 ]"
j="$(echo fix-bug | HARNESS_KEEP=1 python3 "$PACKS/harnesses/harness_run.py" --harness fake-good)"
wd="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["workdir"])' "$j")"
check "harnesses: temp repo is a git repo with baseline commit" "git -C '$wd/repo' log --oneline | grep -q baseline"
check "harnesses: prompt file kept outside the repo" "[ -f '$wd/prompt.md' ] && [ ! -e '$wd/repo/prompt.md' ]"
check "harnesses: changed files reported" "grep -q 'pager.py' <<<'$j'"
rm -rf "$wd"
check "harnesses: unknown task is a fail line" "echo '../etc' | python3 '$PACKS/harnesses/harness_run.py' --harness fake-good | grep -q 'unknown task'"
check "harnesses: unknown harness exits 2" "echo fix-bug | python3 '$PACKS/harnesses/harness_run.py' --harness nope >/dev/null 2>&1; [ \$? = 2 ]"
check "harnesses: no temp repos left" "[ -z \"\$(ls \"\${TMPDIR:-/tmp}\" | grep '^harness-eval-' || true)\" ]"
exit "$fail"
