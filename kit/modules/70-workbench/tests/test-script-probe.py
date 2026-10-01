#!/usr/bin/env python3
"""Focused checks of the rules retained for script text in module 70."""
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

HOOK = Path(__file__).resolve().parents[1] / 'payload/hooks/bash-guard.py'
with tempfile.TemporaryDirectory(prefix='kit-script-probe-') as home:
    os.environ['HOME'] = home
    os.environ['XDG_CONFIG_HOME'] = str(Path(home) / 'config')
    os.environ['AWB_SETTINGS_FILE'] = str(Path(home) / 'missing-settings.json')
    os.environ['TMUX_PANE'] = '%1'
    spec = importlib.util.spec_from_file_location('workbench_bash_guard', HOOK)
    guard = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = guard
    spec.loader.exec_module(guard)
    data = {'tool_name': 'Bash', 'cwd': home, 'tool_input': {'command': 'bash suite.sh'}}
    def probe(command):
        return guard.script_guard._probe_hard(command, data, guard.main)
    guard.ist_worker_pane = lambda: (True, 'test worker')
    hit = probe('git push origin main')
    assert hit and hit[0] == 'deny' and hit[1] == 'push-gate', hit
    guard.ist_worker_pane = lambda: (False, 'test lead')
    assert probe('git push origin main') is None
    assert probe('rm -rf /tmp/test-fixture') is None
    assert probe('export API_KEY=' + 'sk-' + 'abcdefghijklmnopqrstuvwxyz123456') is None
    hit = probe('git commit -m "fix\\nCo-Authored-By: Claude <noreply@anthropic.com>"')
    assert hit and hit[0] == 'deny' and hit[1] == 'commit-trailer', hit
    hit = probe('pkill -f node')
    assert hit and hit[0] == 'deny' and hit[1] == 'kill-pattern', hit
print('script probe: retained rules and typed-only exclusions passed')
