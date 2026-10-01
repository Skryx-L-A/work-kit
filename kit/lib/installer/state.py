"""install-state.json: per-module result of the last install run."""
import json
import os
import tempfile
import time

INSTALLED, FAILED, NOT_SELECTED = "installed", "failed", "not_selected"
# a module that found nothing to do on this machine (95-desktop on Xfce, ...) and changed nothing
SKIPPED = "skipped"


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


class State:
    def __init__(self, path):
        self.path = path
        self.modules = {}
        self.warning = ""
        self._load()

    def _load(self):
        try:
            with open(self.path, encoding="utf-8") as fh:
                data = json.load(fh)
            mods = data.get("modules", {})
            if not isinstance(mods, dict):
                raise ValueError("modules is not an object")
            self.modules = mods
        except FileNotFoundError:
            return
        except (ValueError, OSError, AttributeError) as exc:
            bad = "%s.bad-%s" % (self.path, time.strftime("%Y%m%d%H%M%S"))
            try:
                os.replace(self.path, bad)
            except OSError:
                bad = "(could not move it)"
            self.warning = "state file unreadable (%s); started fresh, old file: %s" % (exc, bad)
            self.modules = {}

    def status(self, mid):
        return self.modules.get(mid, {}).get("status", NOT_SELECTED)

    def entry(self, mid):
        return self.modules.get(mid, {})

    def set(self, mid, status, reason="", step="", log="", exit_code=None, fingerprint=None):
        self.modules[mid] = {
            "status": status,
            "updated": now(),
            "reason": reason,
            "step": step,
            "log": log,
            "exit_code": exit_code,
        }
        if fingerprint is not None:
            self.modules[mid]["fingerprint"] = fingerprint

    def save(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(self.path), prefix=".install-state.")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump({"version": 1, "modules": self.modules}, fh, indent=2, sort_keys=True)
                fh.write("\n")
            os.replace(tmp, self.path)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
