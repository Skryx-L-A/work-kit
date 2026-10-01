"""Tests for prompt_lib.py against the shipped library and a scratch library.
Run: python3 -m unittest discover -s scripts -p 'test_*.py'  (from the skill folder)"""
import contextlib
import io
import tempfile
import unittest
from pathlib import Path

import prompt_lib

KIT_DIR = Path(__file__).resolve().parents[3] / "prompts"


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = prompt_lib.main(argv)
    return rc, out.getvalue(), err.getvalue()


class ShippedLibrary(unittest.TestCase):
    def test_check_passes(self):
        rc, out, _ = run(["--dir", str(KIT_DIR), "check"])
        self.assertEqual(rc, 0, out)

    def test_list_hides_retired(self):
        _, out, _ = run(["--dir", str(KIT_DIR), "list"])
        self.assertIn("general/summarize", out)
        self.assertNotIn("general/tldr", out)
        _, out, _ = run(["--dir", str(KIT_DIR), "list", "--all"])
        self.assertIn("general/tldr", out)

    def test_render_fills_and_requires_variables(self):
        rc, out, err = run(["--dir", str(KIT_DIR), "render", "general/explain",
                            "--var", "topic=RAG", "--var", "background=knows Excel"])
        self.assertEqual(rc, 0)
        self.assertIn("Explain RAG to someone who knows Excel", out)
        self.assertIn("PUBLIC", err)
        rc, _, err = run(["--dir", str(KIT_DIR), "render", "general/explain", "--var", "topic=x"])
        self.assertEqual(rc, 1)
        self.assertIn("background", err)

    def test_retired_needs_flag(self):
        rc, _, err = run(["--dir", str(KIT_DIR), "render", "general/tldr", "--var", "text=x"])
        self.assertEqual(rc, 1)
        self.assertIn("general/summarize", err)
        rc, out, _ = run(["--dir", str(KIT_DIR), "render", "general/tldr", "--var", "text=x",
                          "--allow-retired"])
        self.assertEqual(rc, 0)


class ScratchLibrary(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_new_then_check_and_lint_errors(self):
        rc, out, _ = run(["--dir", str(self.dir), "new", "team/weekly-mail",
                          "--title", "Weekly mail", "--class", "INTERNAL", "--role", "office"])
        self.assertEqual(rc, 0)
        f = self.dir / "team/weekly-mail.md"
        self.assertTrue(f.is_file())
        rc, out, _ = run(["--dir", str(self.dir), "check"])
        self.assertEqual(rc, 0, out)
        rc, _, _ = run(["--dir", str(self.dir), "new", "team/weekly-mail",
                        "--title", "x", "--class", "INTERNAL"])
        self.assertEqual(rc, 1)
        text = f.read_text().replace("{{input}}", "{{input}} {{extra}}")
        text = text.replace("status: draft", "status: retired")
        text = text.replace("data_class: INTERNAL", "data_class: SECRET")
        f.write_text(text)
        rc, out, _ = run(["--dir", str(self.dir), "check"])
        self.assertEqual(rc, 1)
        for msg in ("not declared: extra", "replaced_by", "'retired' date", "SECRET"):
            self.assertIn(msg, out)

    def test_first_dir_wins(self):
        for d, title in ((self.dir / "a", "First"), (self.dir / "b", "Second")):
            run(["--dir", str(d), "new", "x/y", "--title", title, "--class", "PUBLIC"])
        _, out, _ = run(["--dir", str(self.dir / "a"), "--dir", str(self.dir / "b"),
                         "list", "--all"])
        self.assertIn("First", out)
        self.assertNotIn("Second", out)


if __name__ == "__main__":
    unittest.main()
