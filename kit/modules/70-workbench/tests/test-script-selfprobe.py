#!/usr/bin/env python3
"""Feed every kit shell test to the combined 70/32 hook without executing it."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
HOOK = ROOT / 'kit/modules/70-workbench/payload/hooks/bash-guard.py'
GUARD = ROOT / 'kit/modules/32-harness-profiles/guard'
patterns = ('kit/modules/*/tests/*.sh', 'kit/modules/70-workbench/payload/**/tests/*.sh', 'tests/**/*.sh')
suites = sorted({p for pattern in patterns for p in ROOT.glob(pattern) if p.is_file()})
with tempfile.TemporaryDirectory(prefix='kit-script-selfprobe-') as temporary:
    base = Path(temporary)
    home = base / 'home'
    home.mkdir()
    data = base / 'data'
    shutil.copytree(GUARD, data / 'harness-profiles/guard')
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(base / 'config'), KIT_DATA_DIR=str(data),
               AWB_SETTINGS_FILE=str(base / 'missing-settings.json'), AWB_CONFIG=str(base / 'missing-config.json'),
               AWB_GUARD_LOG=str(base / 'guard.log'), AWB_GUARD_BLOCKS_DIR=str(base / 'blocks'),
               AWB_GUARD_GRANTS_DIR=str(base / 'grants'), AWB_ROLLEN_DIR=str(base / 'roles'))
    for key in ('TMUX', 'TMUX_PANE', 'KIT_AGENT_ROLE'):
        env.pop(key, None)
    findings = []
    for suite in suites:
        payload = {'tool_name': 'Bash', 'cwd': str(ROOT), 'tool_input': {'command': 'bash ' + str(suite)}}
        run = subprocess.run([sys.executable, str(HOOK)], input=json.dumps(payload), text=True,
                             capture_output=True, env=env, timeout=30)
        try:
            output = json.loads(run.stdout) if run.stdout.strip() else {}
            answer = output.get('hookSpecificOutput') or {}
            decision = answer.get('permissionDecision') or ('deny' if run.returncode else 'allow')
            reason = answer.get('permissionDecisionReason') or run.stderr.strip()
        except ValueError:
            decision, reason = 'error', run.stdout[:200]
        if decision != 'allow':
            findings.append((suite.relative_to(ROOT), decision, reason.replace('\n', ' ')[:240]))
    print('selfprobe: %d suites, %d refused/questions' % (len(suites), len(findings)))
    for path, decision, reason in findings:
        print('%s: %s: %s' % (path, decision, reason))
    sys.exit(1 if findings else 0)
