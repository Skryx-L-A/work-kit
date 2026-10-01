"""Decision logic of kit-guard: one function per check, no harness specifics.

decide(command, cwd, policy) -> Decision("allow" | "ask" | "deny", reason, check)

Checks, in this order (the first refusal wins, "ask" only when nothing refuses):
  kill       broad pkill/killall/kill-by-pattern/tmux kill-server (lib/killguard.py)
  secrets    a secret literal in the command line; `git add`/`git commit` that would stage a
             secret file (.env, keys) or a file whose content holds a secret
  trailer    a commit message in the command with an agent co-author or "generated with" line
  noverify   `git commit --no-verify` / `-n` (skips the data guard and the trailer hook)
  dataguard  outbound commands (curl upload, scp, rsync to a host, gh gist) whose payload fails
             `data-guard check` (kit module 40-data-guard; skipped when it is not installed)
  commit     `git commit` when the policy says ask or deny (lead default: ask)
  publish    a command that publishes or cannot be taken back: gh release create/upload/edit, gh repo create,
             gh pr merge, git push --force/-f/--force-with-lease or a deletion, npm/pnpm/yarn/cargo/uv publish,
             twine upload, docker push, hf/huggingface-cli upload. Always "ask" (both roles); after the human
             agreed, `KIT_PUBLISH_OK=1` in front of the command. Inside started scripts too.
  script     a local shell script the command starts (`bash x.sh`, `sh x.sh`, `zsh x.sh`, `./x.sh`,
             `source x.sh`, `. x.sh`): the script text runs through all checks above; the reason names
             script and line. Text files up to 256 KiB, one level deep; unreadable files change nothing.

Ported from the workbench guards of kit module 70-workbench (bash-guard-secrets.sh,
bash-guard-commit-trailer.sh, kill_pattern_classify.py); patterns and limits are the same.
"""
from __future__ import annotations

import math
import os
import re
import shutil
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import cmdshell as cs
import killguard

CHECKS = ("kill", "secrets", "trailer", "noverify", "dataguard", "commit", "publish", "script")


@dataclass
class Decision:
    decision: str  # allow | ask | deny
    reason: str = ""
    check: str = ""


@dataclass
class Policy:
    commit: str = "ask"            # allow | ask | deny
    disabled: tuple = ()
    exceptions: tuple = ()         # glob patterns exempt from the content scan (also: scripts not inspected)
    dataguard_cmd: str = ""        # path of data-guard, "" = look it up


# --- secret patterns (same list as the workbench content scan) ------------------------------

MAX_BYTES = 2_000_000
FAST_SUBPROCESS_TIMEOUT = 2
DATA_GUARD_TIMEOUT = 5
ENTROPY_THRESHOLD = 4.3
MIN_GENERIC_LEN = 16
PATTERNS = [
    ("aws_access_key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("github_token", re.compile(r"(?:ghp|gho|ghs|ghu|ghr)_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{20,255}")),
    ("anthropic_key", re.compile(r"sk-ant-[A-Za-z0-9_-]{20,}")),
    ("openai_key", re.compile(r"sk-(?!ant-)[A-Za-z0-9_-]{20,}")),
    ("slack_token", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,48}")),
    ("google_api_key", re.compile(r"AIza[0-9A-Za-z_-]{35,}")),
    ("private_key_block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("jwt", re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
    ("stripe_key", re.compile(r"(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}")),
]
GENERIC_ASSIGN = re.compile(
    r"(?i)(password|passwd|secret|token|api[_-]?key|access[_-]?key|secret[_-]?key|client[_-]?secret)\b"
    r"\s*[:=]\s*[\"']?([A-Za-z0-9+/_=\-~.]{%d,})[\"']?" % MIN_GENERIC_LEN
)
# Command-line forms that carry a credential as an argument value.
CLI_SECRET = re.compile(
    r"(?i)(?:-H\s*[\"']?(?:authorization|x-api-key|api-key)\s*:\s*(?:bearer\s+|token\s+)?"
    r"|--(?:password|token|api-key|secret)[= ]\s*[\"']?"
    r"|://[^/\s:@]+:)([A-Za-z0-9+/_=\-~.]{%d,})" % MIN_GENERIC_LEN
)


def entropy(s: str) -> float:
    if not s:
        return 0.0
    n = len(s)
    return -sum((c / n) * math.log2(c / n) for c in Counter(s).values())


def find_secrets(text: str) -> list[str]:
    """Names (with line numbers) of secret-like strings in text; never the secret itself."""
    found = []
    for name, rx in PATTERNS:
        m = rx.search(text)
        if m:
            found.append("line %d, pattern '%s'" % (text.count("\n", 0, m.start()) + 1, name))
    for rx, label in ((GENERIC_ASSIGN, "assignment"), (CLI_SECRET, "credential argument")):
        for m in rx.finditer(text):
            value = m.group(2) if rx is GENERIC_ASSIGN else m.group(1)
            if entropy(value) >= ENTROPY_THRESHOLD:
                found.append("line %d, %s with high entropy" % (text.count("\n", 0, m.start()) + 1, label))
                break
    return found


def redact(text: str) -> tuple[str, int]:
    """Replace provider-token matches with a marker (used for tool output). Returns (text, count)."""
    count = 0
    for name, rx in PATTERNS:
        text, n = rx.subn("[redacted %s]" % name, text)
        count += n
    return text, count


# --- git helpers ----------------------------------------------------------------------------

SECRET_PATH = re.compile(
    r"(^|/)\.env($|\.[A-Za-z0-9_-]+$)|(^|/)(id_rsa|id_ed25519|id_ecdsa)$|\.(pem|p12|pfx|key)$"
    r"|(^|/)credentials\.json$|(^|/)service-account.*\.json$|(^|/)secrets\.ya?ml$",
    re.I,
)
ENV_TEMPLATE = re.compile(r"\.env\.(example|template|sample)$", re.I)


def is_secret_path(p: str) -> bool:
    return bool(SECRET_PATH.search(p)) and not ENV_TEMPLATE.search(p)


def git_invocations(command: str):
    """Yield (subcommand, dir_hint, args) for every `git ...` in the command (all statements)."""
    stmts = cs.all_statements(cs.strip_heredocs(command))
    for stmt in stmts:
        if stmt is None:
            continue
        for stage in cs.split_pipeline(stmt):
            name, idx, rest = cs.resolve_command(stage, {})
            if name != "git":
                continue
            dirhint, j = "", 0
            while j < len(rest):
                t = rest[j]
                if t == "-C" and j + 1 < len(rest):
                    dirhint = rest[j + 1]
                    j += 2
                    continue
                if t == "-c":
                    j += 2
                    continue
                if t.startswith("--git-dir=") or t.startswith("--work-tree="):
                    dirhint = t.split("=", 1)[1]
                    j += 1
                    continue
                if t.startswith("-"):
                    j += 1
                    continue
                break
            if j < len(rest):
                yield rest[j], dirhint, rest[j + 1:]


def raw_git_mentions(command: str, sub: str) -> bool:
    """Text fallback, used only when the command cannot be tokenized (unbalanced quotes)."""
    if all(s is not None for s in cs.all_statements(cs.strip_heredocs(command))):
        return False
    return bool(re.search(r"(^|[;&|()\s])git(\s+-\S+)*(\s+\S+=\S+)?\s+%s(\s|$)" % sub, command))


def _exempt(rel: str, patterns) -> bool:
    import fnmatch
    return any(fnmatch.fnmatch(rel, p) for p in patterns)


def check_staging(command: str, cwd: str, policy: Policy) -> Decision | None:
    invs = list(git_invocations(command))
    adds = [i for i in invs if i[0] == "add"]
    commit_all = [i for i in invs if i[0] == "commit" and any(
        a in ("-a", "--all") or re.match(r"^-[a-zA-Z]*a[a-zA-Z]*$", a) for a in i[2])]
    if not (adds or commit_all or raw_git_mentions(command, "add")):
        return None
    hint = (adds or commit_all or [("", "", [])])[0][1]
    repo = hint if hint and os.path.isabs(hint) else os.path.join(cwd or os.getcwd(), hint or "")
    try:
        top = subprocess.run(["git", "-C", repo, "rev-parse", "--show-toplevel"], capture_output=True,
                             text=True, timeout=FAST_SUBPROCESS_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as e:
        return Decision("deny", "git add/commit could not be inspected (%s). Refused until it can be checked." % e,
                        "secrets")
    if top.returncode != 0:
        # git not usable: check the names in the command text at least.
        for tok in re.split(r"[\s()]+", command):
            tok = tok.strip("\"'")
            if tok and not tok.startswith("-") and is_secret_path(tok):
                return Decision("deny", "git add/commit names '%s', which looks like a secret file (.env, key). "
                                "Keep it out of git; add a *.example file instead." % tok, "secrets")
        return None
    toplevel = top.stdout.strip()
    st = subprocess.run(["git", "-C", repo, "status", "--porcelain", "--untracked-files=all"],
                        capture_output=True, text=True, timeout=FAST_SUBPROCESS_TIMEOUT)
    for line in st.stdout.splitlines():
        path = line[3:].split(" -> ")[-1].strip().strip('"')
        if not path:
            continue
        if is_secret_path(path):
            return Decision("deny", "git add/commit in %s would include a secret file (%s). Keep it out of git "
                            "(.gitignore) and commit a *.example file instead." % (toplevel, path), "secrets")
        full = os.path.join(toplevel, path)
        if not os.path.isfile(full) or _exempt(path, policy.exceptions):
            continue
        try:
            with open(full, "rb") as f:
                data = f.read(MAX_BYTES)
        except OSError as e:
            return Decision("deny", "git add/commit: %s could not be checked for secrets (%s). "
                            "Refused until it can be read." % (path, e), "secrets")
        if b"\x00" in data:
            continue
        hits = find_secrets(data.decode("utf-8", errors="replace"))
        if hits:
            return Decision("deny", "git add/commit in %s would include a probable secret in %s (%s). Remove it "
                            "and use an environment variable; for a known test string add a glob to "
                            "~/.config/work-kit/guard-exceptions.conf." % (toplevel, path, hits[0]), "secrets")
    return None


# --- the checks -----------------------------------------------------------------------------

TRAILER = re.compile(
    r"(?im)^\s*co-authored-by:.*(claude|anthropic|copilot|openai|codex|chatgpt|gemini|google-labs|aider|cursor"
    r"|opencode|\bpi\b|agent|\bbot\b|\[bot\])"
    r"|generated (with|by) \[?(claude|copilot|codex|gemini|aider|cursor|opencode|pi|an? ai)"
    r"|noreply@anthropic\.com|claude-session:\s*https"
)


def check_text_secrets(text: str, in_script: bool = False) -> Decision | None:
    hits = find_secrets(text)
    if not hits:
        return None
    if in_script:
        return Decision("deny", "The script contains a probable secret (%s). Read it from an environment variable "
                        "or a file that stays out of the repository and the logs." % re.sub(r"^line \d+, ", "", hits[0]),
                        "secrets")
    return Decision("deny", "The command line contains a probable secret (%s). Pass secrets through "
                    "an environment variable or a file that stays out of logs." % hits[0], "secrets")


def check_trailer(command: str, in_script: bool = False) -> Decision | None:
    if in_script:
        for _line, unit in script_units(command):
            found = check_trailer(unit)
            if found:
                return found
        return None
    if not any(s == "commit" for s, _, _ in git_invocations(command)) and not raw_git_mentions(command, "commit"):
        return None
    # Normalize literal "\n" in -m strings so a trailer written on one line is caught too.
    text = command.replace("\\n", "\n")
    if TRAILER.search(text):
        return Decision("deny", "Commit message carries an agent co-author or 'generated with' line. Commit the "
                        "same message without it; commits carry only the human author.", "trailer")
    return None


def check_noverify(command: str) -> Decision | None:
    for sub, _, args in git_invocations(command):
        if sub == "commit" and any(a == "--no-verify" or re.match(r"^-[a-zA-Z]*n[a-zA-Z]*$", a) for a in args
                                   if not a.startswith("--") or a == "--no-verify"):
            return Decision("deny", "git commit --no-verify skips the data guard and the trailer hook. Fix what the "
                            "hook reports instead, or ask the human.", "noverify")
    return None


OUTBOUND = re.compile(
    r"(^|[;&|(\s])(curl|wget|http|https|scp|rsync|sftp|gh\s+gist|gh\s+issue|gh\s+pr\s+comment|nc|ncat)\b")


def _payload_files(tokens: list[str], cwd: str) -> list[str]:
    files = []
    for i, t in enumerate(tokens):
        nxt = tokens[i + 1] if i + 1 < len(tokens) else ""
        cand = None
        if t in ("-d", "--data", "--data-binary", "--data-raw", "--data-urlencode", "-F", "--form") and "@" in nxt:
            cand = nxt.split("@", 1)[1]
        elif t.startswith(("--data=@", "--data-binary=@")):
            cand = t.split("@", 1)[1]
        elif t in ("-T", "--upload-file"):
            cand = nxt
        if cand:
            files.append(cand if os.path.isabs(cand) else os.path.join(cwd, cand))
    return files


def find_dataguard(policy: Policy) -> str:
    if policy.dataguard_cmd:
        return policy.dataguard_cmd
    return shutil.which("data-guard") or ""


def check_dataguard(command: str, cwd: str, policy: Policy) -> Decision | None:
    if not OUTBOUND.search(command):
        return None
    dg = find_dataguard(policy)
    if not dg:
        return None
    try:
        tokens = cs.tokenize(command) or command.split()
    except Exception:
        tokens = command.split()
    targets = [("command text", None)] + [(p, p) for p in _payload_files(tokens, cwd or os.getcwd())]
    # scp/rsync: local files that are sent to a host:path target
    stmts = cs.all_statements(cs.strip_heredocs(command))
    for stmt in stmts or []:
        if not stmt:
            continue
        for stage in cs.split_pipeline(stmt):
            name, _, rest = cs.resolve_command(stage, {})
            if name in ("scp", "rsync", "sftp") and any(re.match(r"^[^/\s]+:", a) for a in rest):
                for a in rest:
                    if a.startswith("-") or re.match(r"^[^/\s]+:", a):
                        continue
                    p = a if os.path.isabs(a) else os.path.join(cwd or os.getcwd(), a)
                    if os.path.isfile(p):
                        targets.append((a, p))
    for label, path in targets:
        try:
            if path is None:
                r = subprocess.run([dg, "check", "-"], input=command, capture_output=True, text=True,
                                   timeout=DATA_GUARD_TIMEOUT)
            elif os.path.isfile(path):
                r = subprocess.run([dg, "check", path], capture_output=True, text=True,
                                   timeout=DATA_GUARD_TIMEOUT)
            else:
                continue
        except (OSError, subprocess.TimeoutExpired) as e:
            return Decision("deny", "Outbound command, but data-guard could not run (%s). Refused until it runs." % e,
                            "dataguard")
        if r.returncode == 1:
            return Decision("deny", "data-guard found secrets or deny-listed company terms in the %s of an outbound "
                            "command. Nothing was sent. Check the data class (AGENTS.md) and ask the human." % (
                                "text" if path is None else "file " + label), "dataguard")
    return None


APPROVED = re.compile(r"(^|[;&|(\s])KIT_COMMIT_OK=1\s+git\b")
APPROVED_ANY = re.compile(r"(^|[;&|(\s])KIT_COMMIT_OK=1\s+\S")


def check_commit_policy(command: str, policy: Policy, in_script: bool = False, approved: bool = False) -> Decision | None:
    """Soft gate: `commit only when asked`. After the human said yes in chat, the agent runs
    `KIT_COMMIT_OK=1 git commit ...`; the prefix stays visible in the transcript. For a commit inside a
    script the prefix goes in front of the command that starts the script."""
    if policy.commit == "allow" or (policy.commit == "ask" and (approved or APPROVED.search(command))):
        return None
    if not any(s == "commit" for s, _, _ in git_invocations(command)) and not raw_git_mentions(command, "commit"):
        return None
    if policy.commit == "deny":
        return Decision("deny", "Commits are switched off for this role (guard.conf commit=deny). Ask the human.",
                        "commit")
    if in_script:
        return Decision("ask", "git commit: commit only when the human asked for it. If the human asked, rerun the "
                        "command that starts the script with `KIT_COMMIT_OK=1` in front; otherwise ask first.",
                        "commit")
    return Decision("ask", "git commit: commit only when the human asked for it. If the human asked, rerun as "
                    "`KIT_COMMIT_OK=1 git commit ...`; otherwise ask first.", "commit")


# --- publishing -----------------------------------------------------------------------------

_PUBLISH_OK = re.compile(r"(^|[;&|(\s])KIT_PUBLISH_OK=1\s+\S")
_OPT_WITH_VALUE = {
    "gh": {"-R", "--repo", "--hostname"},
    "git": {"-o", "--push-option", "--receive-pack", "--exec", "--repo", "--signed"},
    "npm": {"--registry", "--otp", "--tag", "--access", "--prefix", "-C", "--workspace", "-w"},
    "pnpm": {"--registry", "--otp", "--tag", "--access", "--filter", "-F", "--dir", "-C"},
    "yarn": {"--registry", "--otp", "--tag", "--access", "--cwd"},
    "cargo": {"--registry", "--token", "-p", "--package", "--manifest-path", "--index"},
    "uv": {"--index", "--token", "-u", "--username", "-p", "--password", "--publish-url", "--directory"},
    "twine": {"-r", "--repository", "--repository-url", "-u", "--username", "-p", "--password", "-c", "--config-file"},
    "docker": {"-H", "--host", "--context", "-c", "--config", "-l", "--log-level"},
    "hf": {"--token", "--repo-type", "--revision", "--commit-message"},
}


def _positionals(name: str, args: list[str]) -> list[str]:
    """Arguments that are no option (nor the value of an option that takes one)."""
    takes = _OPT_WITH_VALUE.get(name, set())
    out, i = [], 0
    while i < len(args):
        a = args[i]
        if a == "--":
            out.extend(args[i + 1:])
            break
        if a.startswith("-") and len(a) > 1:
            i += 2 if a in takes else 1
            continue
        out.append(a)
        i += 1
    return out


def _git_push_args(rest: list[str]) -> list[str] | None:
    """The arguments after `git [-C d] [-c k=v] ... push`, or None when the subcommand is not push."""
    j = 0
    while j < len(rest):
        t = rest[j]
        if t in ("-C", "-c"):
            j += 2
        elif t.startswith("-"):
            j += 1
        else:
            break
    return rest[j + 1:] if j < len(rest) and rest[j] == "push" else None


def _publish_what(name: str, rest: list[str]) -> str | None:
    """What a command would publish, or None when it publishes nothing."""
    n = name.lower()
    if n == "git":
        args = _git_push_args(rest)
        if args is None:
            return None
        takes = _OPT_WITH_VALUE["git"]
        i = 0
        while i < len(args):
            a = args[i]
            if a in takes:
                i += 2
                continue
            if a.startswith("--"):
                if a == "--force" or a.startswith("--force-with-lease") or a == "--force-if-includes":
                    return "git push --force (overwrites published history)"
                if a == "--delete":
                    return "git push --delete (deletes a remote branch or tag)"
            elif a.startswith("-") and len(a) > 1:
                if "f" in a[1:]:
                    return "git push -f (overwrites published history)"
                if "d" in a[1:]:
                    return "git push -d (deletes a remote branch or tag)"
            elif a.startswith("+"):
                return "git push with a forced refspec (%s)" % a
            elif a.startswith(":") and len(a) > 1:
                return "git push %s (deletes a remote branch or tag)" % a
            i += 1
        return None
    pos = _positionals(n if n in _OPT_WITH_VALUE else "", rest)
    if n == "gh":
        if pos[:2] in (["release", "create"], ["release", "upload"], ["release", "edit"],
                       ["release", "delete"]):
            return "gh release %s" % pos[1]
        if pos[:2] == ["repo", "create"]:
            return "gh repo create"
        if pos[:2] == ["repo", "edit"] and any(
                a == "--visibility=public" or (a == "--visibility" and i + 1 < len(rest)
                                               and rest[i + 1] == "public")
                for i, a in enumerate(rest)):
            return "gh repo edit --visibility public"
        if pos[:2] == ["pr", "merge"]:
            return "gh pr merge"
        return None
    if n in ("npm", "pnpm", "yarn"):
        if pos[:1] == ["publish"] or (n == "yarn" and pos[:2] == ["npm", "publish"]):
            return "%s publish" % n
        return None
    if n in ("cargo", "uv"):
        pos = [p for p in pos if not p.startswith("+")]
        return "%s publish" % n if pos[:1] == ["publish"] else None
    if n == "twine":
        return "twine upload" if pos[:1] == ["upload"] else None
    if re.match(r"^python[0-9.]*$", n):
        if "-m" in rest and rest.index("-m") + 1 < len(rest) and rest[rest.index("-m") + 1] == "twine":
            after = _positionals("twine", rest[rest.index("-m") + 2:])
            return "twine upload" if after[:1] == ["upload"] else None
        return None
    if n in ("docker", "podman"):
        pos = _positionals("docker", rest)
        return "%s push" % n if pos[:1] == ["push"] or pos[:2] == ["image", "push"] else None
    if n in ("hf", "huggingface-cli"):
        pos = _positionals("hf", rest)
        return "%s upload" % n if pos[:1] and pos[0].startswith("upload") else None
    return None


_RAW_PUBLISH = re.compile(
    r"(^|[;&|()\s])(gh\s+(release\s+(create|upload|edit|delete)|repo\s+create|repo\s+edit\s+--visibility[= ]public|pr\s+merge)"
    r"|git\s+(\S+\s+)*push\s+(\S+\s+)*(-\w*[fd]\w*|--force\S*|--delete)(\s|$)"
    r"|(npm|pnpm|yarn|cargo|uv)\s+(\S+\s+)*publish|twine\s+upload|docker\s+(image\s+)?push"
    r"|(hf|huggingface-cli)\s+upload)(\s|$)")


def _workbench_asks(text: str, in_script: bool) -> bool:
    """True when the workbench's own question stage (70-workbench, lib/ask_muster.py, loaded in this process
    when 70's bash-guard.py runs kit-guard) will hold this text as a question: then kit-guard leaves it to that
    stage, so the human is asked once, through the approval queue. Nothing to defer to in any other process."""
    if in_script:
        return False  # 70's script question stage is narrower; ask once through kit-guard here.
    am = sys.modules.get("ask_muster")
    if am is None or not hasattr(am, "passendes_muster") or not hasattr(am, "lade_muster"):
        return False
    try:
        liste = am.lade_muster()
    except Exception:
        return False
    if not liste:
        return False
    try:
        return bool(am.passendes_muster(text, liste))
    except am.Unentscheidbar:
        if not in_script:
            return True  # the question stage asks for what it cannot judge
    except Exception:
        return False
    for _no, unit in script_units(text):  # a script that cannot be judged as a whole: unit by unit
        try:
            if am.passendes_muster(unit, liste):
                return True
        except Exception:  # dynamic command names cannot be judged in a script and are skipped
            continue
    return False


def check_publish(command: str, in_script: bool = False, approved: bool = False) -> Decision | None:
    """Ask before something is published or cannot be taken back. `KIT_PUBLISH_OK=1` in front of the
    command (or, for a script, in front of the command that starts it) is the human's yes."""
    try:
        stmts = cs.all_statements(cs.strip_heredocs(command))
    except Exception:
        stmts = [None]
    hit = None
    for stmt in stmts:
        if stmt is None:
            m = _RAW_PUBLISH.search(command)
            if m and not (approved or _PUBLISH_OK.search(command)):
                hit = ("a publish or force-push command (the line cannot be split)", False)
            continue
        for stage in cs.split_pipeline(stmt):
            name, idx, rest = cs.resolve_command(stage, {})
            if name is None:
                continue
            what = _publish_what(name, rest)
            if in_script and what == "gh repo create" and "--public" not in rest:
                what = None
            if what and not (approved or "KIT_PUBLISH_OK=1" in stage[:idx]):
                hit = (what, True)
                break
        if hit:
            break
    if not hit or _workbench_asks(command, in_script):
        return None
    how = ("rerun the command that starts the script with `KIT_PUBLISH_OK=1` in front" if in_script
           else "rerun the same command with `KIT_PUBLISH_OK=1` in front")
    return Decision("ask", "%s: this publishes or cannot be taken back. Ask the human first; if the human agreed, %s."
                    % (hit[0], how), "publish")


# --- scripts started by the command ---------------------------------------------------------

SCRIPT_MAX_BYTES = 256 * 1024
SCRIPT_MAX_FILES = 8
SCRIPT_CHUNK_CHARS = 150_000  # below killguard.MAX_COMMAND_LEN
_SHELL_OPT_ARG = {"-o", "+o", "-O", "+O", "--rcfile", "--init-file"}
_SHEBANG_SHELLS = cs.SHELL_INTERPRETERS


def _literal_path(word: str, cwd: str) -> str | None:
    """Absolute path of a word that names a file literally (`~`, `$HOME` allowed); None otherwise."""
    if not word or any(c in word for c in "*?[`\x02\x01"):
        return None
    home = os.path.expanduser("~")
    w = word
    if w == "~" or w.startswith("~/"):
        w = home + w[1:]
    w = w.replace("${HOME}", home).replace("$HOME", home)
    if "$" in w:
        return None
    return w if os.path.isabs(w) else os.path.join(cwd or os.getcwd(), w)


def _shell_script_arg(args: list[str]) -> str | None:
    """The script file a shell (bash, sh, zsh...) is asked to run, or None (-c command, -s, no file)."""
    i = 0
    while i < len(args):
        t = args[i]
        if t == "--":
            return args[i + 1] if i + 1 < len(args) else None
        if t.startswith("--"):
            i += 2 if t in _SHELL_OPT_ARG else 1
            continue
        if len(t) > 1 and t[0] in "-+":
            if "c" in t[1:] or "s" in t[1:]:
                return None  # command string (typed text, already checked) or script from stdin
            i += 2 if t in _SHELL_OPT_ARG else 1
            continue
        return t
    return None


def _stdin_file(stage: list[str]) -> str | None:
    """The file of an input redirection (`< x.sh`, `<x.sh`, `0< x.sh`) in a stage, or None."""
    for i, t in enumerate(stage):
        m = re.match(r"^0?<(?![<&(])(.*)$", t)
        if m:
            return m.group(1) or (stage[i + 1] if i + 1 < len(stage) else None)
    return None


def _shell_shebang(head: bytes) -> bool:
    """True when a directly executed file is a shell script: no shebang, or a shell interpreter."""
    if not head.startswith(b"#!"):
        return True
    words = head[2:].split(b"\n", 1)[0].decode("utf-8", "replace").split()
    if not words:
        return True
    prog = os.path.basename(words[0])
    if prog == "env":
        words = [w for w in words[1:] if not w.startswith("-") and "=" not in w]
        prog = os.path.basename(words[0]) if words else ""
    return prog in _SHEBANG_SHELLS


def script_files(command: str, cwd: str, _depth: int = 0) -> list[tuple[str, str, bool]]:
    """(name as typed, absolute path, started directly) of every local script file the command runs:
    `bash x.sh`, `sh -x x.sh a b`, `zsh x.sh`, `source x.sh`, `. x.sh`, `./x.sh` or `dir/x.sh` (started
    directly: only with a shell shebang or none), also behind sudo/env/time/nohup and inside
    `bash -c '...'`. Literal paths only."""
    found: list[tuple[str, str, bool]] = []
    try:
        stmts = cs.all_statements(cs.strip_heredocs(command))
    except Exception:
        return found
    for stmt in stmts:
        if stmt is None:
            continue
        for full in cs.split_pipeline(stmt, strip=False):
            stage = cs.strip_redirections(full)
            name, idx, rest = cs.resolve_command(stage, {})
            if name is None:
                continue
            word, direct = None, False
            if name in cs.SHELL_INTERPRETERS:
                has_c, script = cs.shell_c_script(rest)
                if has_c:
                    if script and _depth < 2:
                        found.extend(script_files(script, cwd, _depth + 1))
                    continue
                word = _shell_script_arg(rest) or _stdin_file(full)  # `bash x.sh` or `bash < x.sh`
            elif name in ("source", "."):
                word = rest[0] if rest and not rest[0].startswith("-") else None
            elif "/" in stage[idx] and not stage[idx].endswith("/"):
                word, direct = stage[idx], True
            path = _literal_path(word, cwd) if word else None
            if path:
                found.append((word, path, direct))
    return found


def read_script(path: str, direct: bool) -> str | None:
    """Text of a regular text file up to SCRIPT_MAX_BYTES, or None (missing, unreadable, too large,
    binary, or started directly with a non-shell shebang): the caller then behaves as before."""
    try:
        if not os.path.isfile(path) or os.path.getsize(path) > SCRIPT_MAX_BYTES:
            return None
        with open(path, "rb") as f:
            data = f.read(SCRIPT_MAX_BYTES + 1)
    except OSError:
        return None
    if len(data) > SCRIPT_MAX_BYTES or not data.strip() or b"\x00" in data or (direct and not _shell_shebang(data)):
        return None
    return data.decode("utf-8", errors="replace")


_HEREDOC_RE = re.compile(r"<<(-?)[ \t]*(\\?)['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")


def _open_state(buf: str):
    """'quote'/'cont' when the text of a command is not finished (a quote stays open, a backslash continues
    the line), ('heredoc', (word, dash)) when its last line starts a here-document, else None."""
    in_s = in_d = False
    i, n = 0, len(buf)
    last_nl = buf.rfind("\n")
    heredoc = None
    while i < n:
        c = buf[i]
        if in_s:
            if c == "'":
                in_s = False
        elif c == "\\":
            if i + 1 >= n:
                return "cont", None
            i += 1
        elif in_d:
            if c == '"':
                in_d = False
        elif c == "'":
            in_s = True
        elif c == '"':
            in_d = True
        elif c == "#" and (i == 0 or buf[i - 1] in " \t\n;&|("):
            j = buf.find("\n", i)
            i = n if j < 0 else j
            continue
        elif i > last_nl and buf.startswith("<<", i) and not buf.startswith("<<<", i):
            m = _HEREDOC_RE.match(buf, i)
            if m:
                heredoc = (m.group(3), m.group(1) == "-")
                i = m.end() - 1
        i += 1
    if in_s or in_d:
        return "quote", None
    return ("heredoc", heredoc) if heredoc else (None, None)


def script_units(text: str) -> list[tuple[int, str]]:
    """(first line number, command text): physical lines joined where a backslash continues the line, a
    quote stays open or a here-document body follows; blank and comment-only lines dropped."""
    lines = text.split("\n")
    units, i = [], 0
    while i < len(lines):
        start, buf = i, lines[i]
        i += 1
        while i < len(lines):
            state, arg = _open_state(buf)
            if state is None:
                break
            if state == "heredoc":
                word, dash = arg
                while i < len(lines):
                    buf += "\n" + lines[i]
                    i += 1
                    if (lines[i - 1].lstrip("\t") if dash else lines[i - 1]) == word:
                        break
                break
            buf += "\n" + lines[i]
            i += 1
        if buf.strip() and not buf.lstrip().startswith("#"):
            units.append((start + 1, buf))
    return units


# A kill refusal that only says "cannot be decided" (a variable as PID, socket name or pattern, a command word
# from a substitution) is normal in scripts and undecidable without running them: it does not count there.
_UNDECIDABLE = re.compile(r"undecidable forms|cannot be classified as safe|comes from an unresolvable"
                          r"|Subcommand: [^\n]*[$`]")


def _undecidable(d: Decision) -> bool:
    return d.check == "kill" and bool(_UNDECIDABLE.search(d.reason))


def _chunks(lines: list[str]):
    """(first line number, text) pieces of a script, each below the length limit of the checks."""
    start, size, cur = 0, 0, []
    for i, ln in enumerate(lines):
        if cur and size + len(ln) + 1 > SCRIPT_CHUNK_CHARS:
            yield start + 1, "\n".join(cur)
            start, size, cur = i, 0, []
        cur.append(ln[:SCRIPT_CHUNK_CHARS])
        size += len(ln) + 1
    if cur:
        yield start + 1, "\n".join(cur)


def _locate(lines: list[str], first: int, hit: Decision, cwd: str, policy: Policy, approved: tuple) -> int | None:
    """Line where the refusal of a chunk begins to hold: the smallest k so that the first k lines are
    already refused by the same check (bisection; the prefix before it is not)."""
    def refused(k: int) -> bool:
        d = decide("\n".join(lines[:k]), cwd, policy, _script=approved)
        return d.decision != "allow" and d.check == hit.check and not _undecidable(d)
    lo, hi = 0, len(lines)
    if hi < 1 or not refused(hi):
        return None
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if refused(mid):
            hi = mid
        else:
            lo = mid
    return first + hi - 1


def check_scripts(command: str, cwd: str, policy: Policy) -> Decision | None:
    """All checks over the text of the local scripts the command starts. One level deep: a script's own
    calls of further scripts are not followed. A script that cannot be read changes nothing."""
    prefix = re.match(r"^\s*((?:(?:KIT_COMMIT_OK|KIT_PUBLISH_OK)=1\s+)+)"
                      r"(?:(?:bash|sh|zsh|dash|source|\.)\s+|\./)", command)
    publish_script_approved = bool(prefix and "KIT_PUBLISH_OK=1" in prefix.group(1))
    approved = (bool(APPROVED_ANY.search(command)), publish_script_approved)
    ask, done = None, set()
    for word, path, direct in script_files(command, cwd or os.getcwd())[:SCRIPT_MAX_FILES]:
        real = os.path.realpath(path)
        if real in done or _exempt(real, policy.exceptions) or _exempt(word, policy.exceptions):
            continue
        done.add(real)
        text = read_script(real, direct)
        if text is None:
            continue
        lines = text.split("\n")
        for first, chunk in _chunks(lines):
            d = decide(chunk, cwd, policy, _script=approved)
            if d.decision == "allow":
                continue
            n = first + chunk.count("\n")
            found: list[tuple[Decision, str]] = []
            if not _undecidable(d):
                at = _locate(lines[first - 1:n], first, d, cwd, policy, approved)
                found.append((d, "line %d" % at if at else "lines %d-%d" % (first, n)))
            else:  # judge the script command by command: only what is decidable and refused counts
                for no, unit in script_units(chunk):
                    u = decide(unit, cwd, policy, _script=approved)
                    if u.decision != "allow" and not _undecidable(u):
                        found.append((u, "line %d" % (first + no - 1)))
            for d1, where in found:
                res = Decision(d1.decision, "script %s, %s: %s" % (word, where, d1.reason), d1.check)
                if res.decision == "deny":
                    return res
                ask = ask or res
    return ask


def protected_config_path(word: str, cwd: str, directory: bool = False) -> str | None:
    """Return the guard policy file reached by a literal path, including symlinked parents."""
    xdg = os.environ.get("XDG_CONFIG_HOME")
    if xdg:
        word = word.replace("${XDG_CONFIG_HOME}", xdg).replace("$XDG_CONFIG_HOME", xdg)
    path = _literal_path(word, cwd)
    if path is None:
        return None
    root = os.path.realpath(config_dir())
    target = os.path.realpath(path)
    lexical = os.path.abspath(path)
    lexical_root = os.path.abspath(config_dir())
    if directory and (target == root or lexical == lexical_root):
        return str(config_dir())
    for name in ("guard.conf", "guard-exceptions.conf", "profiles.conf"):
        protected = os.path.join(root, name)
        if target == protected or lexical == os.path.join(lexical_root, name):
            return str(config_dir() / name)
    return None


def check_guard_config(command: str, cwd: str) -> Decision | None:
    """Keep policy changes in human hands, even when guard.conf disables other checks."""
    mutators = {"rm", "rmdir", "unlink", "mv", "rename", "cp", "install", "ln", "touch",
                "tee", "truncate", "chmod", "chown", "chgrp", "patch"}
    for statement in cs.all_statements(cs.strip_heredocs(command)):
        if statement is None:
            continue
        for stage in cs.split_pipeline(statement, strip=False):
            name, _, args = cs.resolve_command(cs.strip_redirections(stage), {})
            targets = [p for _, p in cs.output_redirections(stage) if p]
            if name in mutators:
                operands = [a for a in args if not a.startswith("-")]
                targets.extend(operands[-1:] if name in ("cp", "install", "ln") else operands)
            elif name in ("sed", "perl") and any(a == "-i" or a.startswith("-i") or a == "--in-place"
                                                   for a in args):
                targets.extend(a for a in args if not a.startswith("-"))
            elif name == "dd":
                targets.extend(a[3:] for a in args if a.startswith("of="))
            for word in targets:
                found = protected_config_path(word, cwd, directory=name in mutators)
                if found:
                    return Decision("deny", "the human edits %s." % found, "guard-config")
    return None


def check_script_guard_config(command: str, cwd: str) -> Decision | None:
    """Policy files stay protected even when a script or the script check is exempted."""
    for word, path, direct in script_files(command, cwd or os.getcwd())[:SCRIPT_MAX_FILES]:
        body = read_script(path, direct)
        if body is None:
            continue
        for number, line in enumerate(body.splitlines(), 1):
            found = check_guard_config(line, cwd)
            if found:
                return Decision("deny", "script %s, line %d: %s" % (word, number, found.reason), "guard-config")
        found = check_guard_config(body, cwd)
        if found:
            return Decision("deny", "script %s: %s" % (word, found.reason), "guard-config")
    return None


def decide(command: str, cwd: str = "", policy: Policy | None = None,
           _script: tuple[bool, bool] | None = None) -> Decision:
    """_script: None for a typed command; inside the text of a script it says whether the human approved
    commits and publishing (KIT_COMMIT_OK=1 / KIT_PUBLISH_OK=1 in front of the command that starts the script)."""
    policy = policy or Policy()
    in_script = _script is not None
    if not isinstance(command, str) or not command.strip():
        return Decision("allow")
    if len(command) > killguard.MAX_COMMAND_LEN:
        return Decision("deny", "Command longer than %d characters: too large to check. Write it to a script file."
                        % killguard.MAX_COMMAND_LEN, "kill")
    protected = check_guard_config(command, cwd)
    if not protected and not in_script:
        protected = check_script_guard_config(command, cwd)
    if protected:
        return protected
    off = set(policy.disabled)
    steps = [
        ("kill", lambda: killguard.scan_for_danger(command, {})),
        ("trailer", lambda: check_trailer(command, in_script)),
    ]
    if not in_script:
        steps.extend([
            ("secrets", lambda: check_text_secrets(command)),
            ("secrets", lambda: check_staging(command, cwd, policy)),
            ("noverify", lambda: check_noverify(command)),
            ("dataguard", lambda: check_dataguard(command, cwd, policy)),
            ("commit", lambda: check_commit_policy(command, policy)),
        ])
    steps.append(("publish", lambda: check_publish(command, in_script, bool(_script and _script[1]))))
    if not in_script:  # one level: the text of a script does not start further scripts
        steps.append(("script", lambda: check_scripts(command, cwd, policy)))
    ask = None
    for name, fn in steps:
        if name in off:
            continue
        res = fn()
        if res is None:
            continue
        if isinstance(res, str):
            res = Decision("deny", res, name)
        if res.decision == "deny":
            return res
        if res.decision == "ask" and ask is None:
            ask = res
    return ask or Decision("allow")


# --- configuration --------------------------------------------------------------------------

def config_dir() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return Path(base) / "work-kit"


def read_kv(path: Path) -> dict:
    out = {}
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
    except OSError:
        pass
    return out


def current_role(harness: str = "") -> str:
    """KIT_AGENT_ROLE wins (set by worker launchers), then profiles.conf role.<harness>, then role."""
    env = os.environ.get("KIT_AGENT_ROLE", "").strip().lower()
    if env in ("lead", "worker", "none"):
        return env
    conf = read_kv(config_dir() / "profiles.conf")
    return (conf.get("role.%s" % harness) or conf.get("role") or "lead").lower()


def load_policy(harness: str = "") -> Policy:
    conf = read_kv(config_dir() / "guard.conf")
    role = current_role(harness)
    commit = conf.get("commit.%s" % role) or conf.get("commit") or ("allow" if role == "worker" else "ask")
    if commit not in ("allow", "ask", "deny"):
        commit = "ask"
    disabled = tuple(x.strip() for x in conf.get("disable", "").split(",") if x.strip() in CHECKS)
    exc = []
    try:
        for line in (config_dir() / "guard-exceptions.conf").read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                exc.append(line)
    except OSError:
        pass
    return Policy(commit=commit, disabled=disabled, exceptions=tuple(exc), dataguard_cmd=conf.get("data-guard", ""))
