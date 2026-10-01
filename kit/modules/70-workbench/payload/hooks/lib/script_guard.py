"""Script step of bash-guard.py (SPEC known defect 9); the comment block below says what it does.

bash-guard.py calls hard_hit() and ask_hit() and holds the hooks into main(); the rest lives here so that
Python compiles it once (a .pyc) and not on every Bash call.
"""
import hashlib
import io
import json
import os
import re
import sys

import ask_muster
import cmdshell

# ===========================================================================
# Started scripts receive only kill-pattern, worker push-gate and commit-trailer hard checks.
# Publication commands enter the question stage. The other workbench guards run on typed Bash
# commands only. A readable local shell script is inspected one level deep, up to 256 KiB;
# the answer names its script and line. Exemptions in guard-exceptions.conf apply here.
# Module 32 separately protects guard policy files even when a script is exempt.

SCRIPT_MAX_BYTES = 256 * 1024
SCRIPT_MAX_FILES = 8
SCRIPT_CHUNK_CHARS = 150000  # below the 200000 limit of the classifiers
_SHELL_OPT_ARG = ('-o', '+o', '-O', '+O', '--rcfile', '--init-file')
PROBING = [False]
PROBE_HITS = []


def _script_exceptions():
    base = os.environ.get('XDG_CONFIG_HOME') or os.path.join(os.path.expanduser('~'), '.config')
    globs = []
    try:
        with open(os.path.join(base, 'work-kit', 'guard-exceptions.conf')) as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith('#'):
                    globs.append(line)
    except OSError:
        pass
    return globs


def _script_literal_path(word, cwd):
    """Absolute path of a word that names a file literally (`~` and $HOME allowed), else None."""
    if not word or any(c in word for c in '*?[`\x02\x01'):
        return None
    home = os.path.expanduser('~')
    w = word
    if w == '~' or w.startswith('~/'):
        w = home + w[1:]
    w = w.replace('${HOME}', home).replace('$HOME', home)
    if '$' in w:
        return None
    return w if os.path.isabs(w) else os.path.join(cwd or os.getcwd(), w)


def _shell_script_arg(args):
    """The script file a shell is asked to run, or None (-c command string, -s, no file)."""
    i = 0
    while i < len(args):
        t = args[i]
        if t == '--':
            return args[i + 1] if i + 1 < len(args) else None
        if t.startswith('--'):
            i += 2 if t in _SHELL_OPT_ARG else 1
            continue
        if len(t) > 1 and t[0] in '-+':
            if 'c' in t[1:] or 's' in t[1:]:
                return None
            i += 2 if t in _SHELL_OPT_ARG else 1
            continue
        return t
    return None


def _stdin_file(stage):
    """The file of an input redirection (`< x.sh`, `<x.sh`, `0< x.sh`) in a stage, or None."""
    for i, t in enumerate(stage):
        m = re.match(r'^0?<(?![<&(])(.*)$', t)
        if m:
            return m.group(1) or (stage[i + 1] if i + 1 < len(stage) else None)
    return None


def _shell_shebang(head):
    """True when a file started directly is a shell script: no shebang, or a shell interpreter."""
    if not head.startswith(b'#!'):
        return True
    words = head[2:].split(b'\n', 1)[0].decode('utf-8', 'replace').split()
    if not words:
        return True
    prog = os.path.basename(words[0])
    if prog == 'env':
        words = [w for w in words[1:] if not w.startswith('-') and '=' not in w]
        prog = os.path.basename(words[0]) if words else ''
    return prog in cmdshell.SHELL_INTERPRETERS


def script_files(command, cwd, _depth=0):
    """[(name as typed, absolute path, started directly)] of the local script files a command runs."""
    found = []
    try:
        statements = cmdshell.all_statements(cmdshell.strip_heredocs(command))
    except Exception:
        return found
    for stmt in statements:
        if stmt is None:
            continue
        for full in cmdshell.split_pipeline(stmt, strip=False):
            stage = cmdshell.strip_redirections(full)
            name, idx, rest = cmdshell.resolve_command(stage, {})
            if name is None:
                continue
            word, direct = None, False
            if name in cmdshell.SHELL_INTERPRETERS:
                has_c, script = cmdshell.shell_c_script(rest)
                if has_c:
                    if script and _depth < 2:
                        found.extend(script_files(script, cwd, _depth + 1))
                    continue
                word = _shell_script_arg(rest) or _stdin_file(full)  # `bash x.sh` or `bash < x.sh`
            elif name in ('source', '.'):
                word = rest[0] if rest and not rest[0].startswith('-') else None
            elif '/' in stage[idx] and not stage[idx].endswith('/'):
                word, direct = stage[idx], True
            path = _script_literal_path(word, cwd) if word else None
            if path:
                found.append((word, path, direct))
    return found


def read_script(path, direct):
    """Text of a regular text file up to SCRIPT_MAX_BYTES, else None (the caller then behaves as before)."""
    try:
        if not os.path.isfile(path) or os.path.getsize(path) > SCRIPT_MAX_BYTES:
            return None
        with open(path, 'rb') as fh:
            data = fh.read(SCRIPT_MAX_BYTES + 1)
    except OSError:
        return None
    if len(data) > SCRIPT_MAX_BYTES or not data.strip() or b'\x00' in data or (direct and not _shell_shebang(data)):
        return None
    return data.decode('utf-8', errors='replace')


_SCRIPTS_SEEN = {}


def local_scripts(command, cwd):
    """[(name as typed, text, sha256)] of the readable scripts the command starts (once per command)."""
    key = (command, cwd)
    if key in _SCRIPTS_SEEN:
        return _SCRIPTS_SEEN[key]
    out, done = [], set()
    files = script_files(command, cwd or os.getcwd())[:SCRIPT_MAX_FILES]
    if files:
        import fnmatch
        exempt = _script_exceptions()
        for word, path, direct in files:
            real = os.path.realpath(path)
            if real in done or any(fnmatch.fnmatch(x, g) for g in exempt for x in (real, word)):
                continue
            done.add(real)
            text = read_script(real, direct)
            if text is not None:
                out.append((word, text, hashlib.sha256(text.encode('utf-8', 'replace')).hexdigest()))
    _SCRIPTS_SEEN[key] = out
    return out


def _script_chunks(lines):
    """(first line number, text) pieces of a script, each below the length limit of the classifiers."""
    start, size, cur = 0, 0, []
    for i, ln in enumerate(lines):
        if cur and size + len(ln) + 1 > SCRIPT_CHUNK_CHARS:
            yield start + 1, '\n'.join(cur)
            start, size, cur = i, 0, []
        cur.append(ln[:SCRIPT_CHUNK_CHARS])
        size += len(ln) + 1
    if cur:
        yield start + 1, '\n'.join(cur)


_HEREDOC_RE = re.compile(r'<<(-?)[ \t]*(\\?)([\'"]?)([A-Za-z_][A-Za-z0-9_]*)\3')


def _open_state(buf):
    """Reads the text of a command so far: 'quote'/'cont' when it is not finished (a quote stays open, a
    backslash continues the line), ('heredoc', (word, dash)) when its last line starts a here-document,
    else None."""
    in_s = in_d = False
    i, n = 0, len(buf)
    last_nl = buf.rfind('\n')
    heredoc = None
    while i < n:
        c = buf[i]
        if in_s:
            if c == "'":
                in_s = False
        elif c == '\\':
            if i + 1 >= n:
                return 'cont', None
            i += 1
        elif in_d:
            if c == '"':
                in_d = False
        elif c == "'":
            in_s = True
        elif c == '"':
            in_d = True
        elif c == '#' and (i == 0 or buf[i - 1] in ' \t\n;&|('):
            j = buf.find('\n', i)
            i = n if j < 0 else j
            continue
        elif i > last_nl and buf.startswith('<<', i) and not buf.startswith('<<<', i):
            m = _HEREDOC_RE.match(buf, i)
            if m:
                heredoc = (m.group(4), m.group(1) == '-')
                i = m.end() - 1
        i += 1
    if in_s or in_d:
        return 'quote', None
    return ('heredoc', heredoc) if heredoc else (None, None)


def script_units(text):
    """[(first line number, command text)]: physical lines joined where a backslash continues the line,
    a quote stays open or a here-document body follows; blank and comment-only lines dropped."""
    lines = text.split('\n')
    units, i = [], 0
    while i < len(lines):
        start, buf = i, lines[i]
        i += 1
        while i < len(lines):
            state, arg = _open_state(buf)
            if state is None:
                break
            if state == 'heredoc':
                word, dash = arg
                while i < len(lines):
                    buf += '\n' + lines[i]
                    i += 1
                    if (lines[i - 1].lstrip('\t') if dash else lines[i - 1]) == word:
                        break
                break
            buf += '\n' + lines[i]
            i += 1
        if buf.strip() and not buf.lstrip().startswith('#'):
            units.append((start + 1, buf))
    return units


def _probe_hard(text, data, main_fn):
    """(decision, guard, reason) the hard guards would answer for `text` typed as a command, or None.
    Runs main() in probe mode: no marker, no log, no approval used, nothing printed."""
    tool_input = dict(data.get('tool_input') or {})
    tool_input['command'] = text
    payload = json.dumps(dict(data, tool_input=tool_input))
    out, err = io.StringIO(), io.StringIO()
    old = sys.stdout, sys.stderr
    del PROBE_HITS[:]
    PROBING[0] = True
    sys.stdout, sys.stderr = out, err
    try:
        rc = main_fn(payload)
    except Exception:
        return None  # a crash is what the hook would do for the typed command too
    finally:
        sys.stdout, sys.stderr = old
        PROBING[0] = False
    guard = PROBE_HITS[0] if PROBE_HITS else 'script'
    if rc == 2:
        return 'deny', guard, err.getvalue().strip()
    try:
        hso = json.loads(out.getvalue()).get('hookSpecificOutput') or {}
    except ValueError:
        return None
    if hso.get('permissionDecision') in ('deny', 'ask'):
        return hso['permissionDecision'], guard, hso.get('permissionDecisionReason') or ''
    return None


_UNDECIDABLE = re.compile(r'unentscheidbare Formen|undecidable forms|cannot be classified as safe|Subcommand: [^\n]*[$`]')


def hard_hit(command, cwd, data, main_fn):
    """(decision, guard, reason) of the strictest refusal of the hard guards inside the scripts the
    command starts, with script and line in the reason; None when nothing refuses.

    A refusal that only says "cannot be decided" (a variable as the target of rm, mv, > or kill: normal in
    scripts, undecidable without running them) does not count: the script is then judged command by command,
    and only what is decidable and refused counts."""
    ask = None
    for name, text, _sha in local_scripts(command, cwd):
        lines = text.split('\n')
        for first, chunk in _script_chunks(lines):
            hit = _probe_hard(chunk, data, main_fn)
            if hit is None:
                continue
            found = []  # (decision, guard, reason, line)
            if not _UNDECIDABLE.search(hit[2]):
                rows = lines[first - 1:first + chunk.count('\n')]

                def refused(k, hit=hit, rows=rows):
                    h = _probe_hard('\n'.join(rows[:k]), data, main_fn)
                    return h is not None and h[1] == hit[1] and not _UNDECIDABLE.search(h[2])
                lo, hi = 0, len(rows)
                at = None
                if refused(hi):
                    while hi - lo > 1:
                        mid = (lo + hi) // 2
                        if refused(mid):
                            hi = mid
                        else:
                            lo = mid
                    at = first + hi - 1
                found.append((hit[0], hit[1], hit[2], at))
            else:
                for no, unit in script_units(chunk):
                    h = _probe_hard(unit, data, main_fn)
                    if h is not None and not _UNDECIDABLE.search(h[2]):
                        found.append((h[0], h[1], h[2], first + no - 1))
            for decision, guard, reason, at in found:
                where = 'line %d' % at if at else 'lines %d-%d' % (first, first + chunk.count('\n'))
                res = (decision, guard, 'script %s, %s: %s' % (name, where, reason))
                if decision == 'deny':
                    return res
                ask = ask or res
    return ask


def real_git_commit(text):
    """A git invocation in executable script text, excluding quoted test fixtures."""
    for stmt in cmdshell.all_statements(cmdshell.strip_heredocs(text)):
        if stmt is None:
            continue
        for stage in cmdshell.split_pipeline(stmt):
            name, _idx, args = cmdshell.resolve_command(stage, {})
            if name == 'git' and 'commit' in args:
                return True
    return False


def trailer_hit(text, check_fn):
    """A trailer must belong to the same executable git command, not another test fixture."""
    return any(real_git_commit(unit) and check_fn(unit) for _line, unit in script_units(text))


def _publish_unit(unit):
    """A publishing command inside a script; data and quoted examples are ignored."""
    for stmt in cmdshell.all_statements(cmdshell.strip_heredocs(unit)):
        if stmt is None:
            continue
        for stage in cmdshell.split_pipeline(stmt):
            name, _idx, args = cmdshell.resolve_command(stage, {})
            if not name:
                continue
            pos = [a for a in args if not a.startswith('-')]
            if name == 'gh':
                if pos[:2] in (['release', 'create'], ['release', 'upload'], ['release', 'edit'],
                               ['release', 'delete'], ['pr', 'merge']):
                    return name
                if pos[:2] == ['repo', 'create'] and '--public' in args:
                    return name
                if pos[:2] == ['repo', 'edit'] and ('--visibility=public' in args or
                        any(a == '--visibility' and i + 1 < len(args) and args[i + 1] == 'public'
                            for i, a in enumerate(args))):
                    return name
            if name == 'git' and 'push' in pos and any(
                    a in ('-f', '--force', '--force-with-lease', '--delete', '-d') or
                    a.startswith(('--force-with-lease=', '+', ':')) for a in args):
                return name
            if name in ('npm', 'pnpm', 'cargo', 'uv') and [p for p in pos if not p.startswith('+')][:1] == ['publish']:
                return name
            if name == 'yarn' and (pos[:1] == ['publish'] or pos[:2] == ['npm', 'publish']):
                return name
            if name == 'twine' and pos[:1] == ['upload']:
                return name
            if re.fullmatch(r'python[0-9.]*', name) and '-m' in args and 'twine' in args and 'upload' in pos:
                return name
            if name in ('docker', 'podman') and (pos[:1] == ['push'] or pos[:2] == ['image', 'push']):
                return name
            if name in ('hf', 'huggingface-cli') and pos[:1] == ['upload']:
                return name
    return None


def ask_hit(command, cwd, muster_liste):
    """Only publication in a started script enters the workbench approval queue."""
    prefix = re.match(r'^\s*((?:(?:KIT_COMMIT_OK|KIT_PUBLISH_OK)=1\s+)+)'
                      r'(?:(?:bash|sh|zsh|dash|source|\.)\s+|\./)', command)
    if not muster_liste or (prefix and 'KIT_PUBLISH_OK=1' in prefix.group(1)):
        return None, command
    for name, text, sha in local_scripts(command, cwd):
        for no, unit in script_units(text):
            tool = _publish_unit(unit)
            if not tool:
                continue
            entry = {'befehl': tool, 'grund': 'script %s, line %d: publishing needs human approval.' % (name, no)}
            return entry, '%s\n# [script %s sha256 %s]' % (command, name, sha)
    return None, command
