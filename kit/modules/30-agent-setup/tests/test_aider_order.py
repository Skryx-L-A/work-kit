"""~/.aider.conf.yml is written by 30-agent-setup (kit-sync region), 31-caveman and 32-harness-profiles.
Every install order must leave each module's read: line exactly once, and a second run must change nothing.
Run: python3 -m unittest discover -s tests -v (from this module dir)."""
import itertools
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

MODULES = Path(__file__).resolve().parent.parent.parent
ORDER = ("30-agent-setup", "31-caveman", "32-harness-profiles")
# what each module's line looks like in the file
NEEDLES = {"30-agent-setup": "agent-setup/source/AGENTS.md", "31-caveman": "caveman-aider.md",
           "32-harness-profiles": "roles/lead.md"}
MODEL_REGION = ("# work-kit:begin model-endpoint - managed by kit-models\nmodel: openai/x\n"
                "# work-kit:end model-endpoint\n")


@unittest.skipUnless(shutil.which("bash") and all((MODULES / m / "install.sh").is_file() for m in ORDER),
                     "needs the sibling modules")
class AiderOrder(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.home = Path(self._tmp.name).resolve() / "home"
        (self.home / ".aider").mkdir(parents=True)
        self.env = {k: v for k, v in os.environ.items() if k not in (
            "CODEX_HOME", "XDG_CONFIG_HOME", "KIT_DATA_DIR", "KIT_BIN_DIR", "CLAUDE_CONFIG_DIR", "COPILOT_HOME",
            "GIT_CONFIG_GLOBAL", "KIT_PYTHON", "PI_CODING_AGENT_DIR", "KIT_AGENT_ROLE")}
        self.env.update(HOME=str(self.home), PATH="/usr/bin:/bin", PYTHONDONTWRITEBYTECODE="1",
                        GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(self.home / ".gitconfig"))
        self.conf = self.home / ".aider.conf.yml"

    def tearDown(self):
        self._tmp.cleanup()

    def fresh(self):
        shutil.rmtree(self.home)
        (self.home / ".aider").mkdir(parents=True)

    def install(self, mod):
        r = subprocess.run(["bash", str(MODULES / mod / "install.sh")], capture_output=True, text=True,
                           env=self.env, stdin=subprocess.DEVNULL)
        self.assertEqual(r.returncode, 0, mod + "\n" + r.stdout + r.stderr)

    def uninstall(self, mod):
        r = subprocess.run(["bash", str(MODULES / mod / "uninstall.sh")], capture_output=True, text=True,
                           env=self.env, stdin=subprocess.DEVNULL)
        self.assertEqual(r.returncode, 0, mod + "\n" + r.stdout + r.stderr)

    def check_marks(self, text, order, user_items=()):
        for mod, needle in NEEDLES.items():
            if user_items and mod == "30-agent-setup":
                continue  # kit-sync leaves a read: list of your own alone
            self.assertEqual(text.count(needle), 1, f"{order}: {mod} line count\n{text}")
        self.assertEqual(sum(1 for ln in text.splitlines() if ln == "read:"), 1, f"{order}: one read: key\n{text}")
        for item in user_items:
            self.assertEqual(text.count(item), 1, f"{order}: {item}\n{text}")

    def run_order(self, order, start="", user_items=()):
        if start:
            self.conf.write_text(start)
        for mod in order:
            self.install(mod)
        first = self.conf.read_text()
        self.check_marks(first, order, user_items)
        for mod in order:
            self.install(mod)
        self.assertEqual(self.conf.read_text(), first, f"{order}: second run changed the file")
        return first

    def test_all_orders_on_a_fresh_file(self):
        for order in itertools.permutations(ORDER):
            with self.subTest(order=order):
                self.fresh()
                self.run_order(order)

    def test_all_orders_with_user_and_model_endpoint_lines(self):
        start = "model-timeout: 5\n" + MODEL_REGION
        for order in itertools.permutations(ORDER):
            with self.subTest(order=order):
                self.fresh()
                text = self.run_order(order, start)
                self.assertIn("model-timeout: 5", text)
                self.assertIn(MODEL_REGION.strip(), text)

    def test_all_orders_with_a_user_read_list(self):
        start = "read:\n  - CONVENTIONS.md\nauto-lint: false\n"
        for order in itertools.permutations(ORDER):
            with self.subTest(order=order):
                self.fresh()
                text = self.run_order(order, start, ("CONVENTIONS.md",))
                self.assertIn("auto-lint: false", text)

    def test_uninstall_leaves_the_others(self):
        self.run_order(ORDER)
        self.uninstall("32-harness-profiles")
        text = self.conf.read_text()
        self.assertNotIn("roles/lead.md", text)
        self.assertEqual(text.count("caveman-aider.md"), 1)
        self.assertEqual(text.count("AGENTS.md"), 1)
        self.uninstall("31-caveman")
        text = self.conf.read_text()
        self.assertNotIn("caveman", text)
        self.assertEqual(text.count("AGENTS.md"), 1)
        self.assertEqual(sum(1 for ln in text.splitlines() if ln == "read:"), 1)

    def test_old_caveman_layout_is_taken_over(self):
        # 31-caveman < 2026-09-25 wrote its own top-level read: key
        rules = self.home / ".local/share/work-kit/generated/caveman-aider.md"
        self.conf.write_text(f"model: x\n# work-kit-caveman: chat style\nread:\n  - {rules}\n")
        self.install("30-agent-setup")
        text = self.conf.read_text()
        self.assertEqual(text.count("caveman-aider.md"), 1)
        self.assertEqual(sum(1 for ln in text.splitlines() if ln == "read:"), 1)
        self.assertIn("model: x", text)
        self.install("31-caveman")
        self.assertEqual(self.conf.read_text(), text)


if __name__ == "__main__":
    unittest.main()
