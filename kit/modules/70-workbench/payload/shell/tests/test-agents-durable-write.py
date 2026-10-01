"""Prüft die Reihenfolge der zugesagten Datenträger-Synchronisation."""
from pathlib import Path
import os
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import atomar_schreiben as atomic


class DurabilityTest(unittest.TestCase):
    def test_file_synced_before_replace_and_directory_after(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "state.json"
            events = []
            real_sync, real_replace = os.fsync, os.replace
            def sync(fd):
                events.append("directory" if stat.S_ISDIR(os.fstat(fd).st_mode) else "file")
                real_sync(fd)
            def replace(source, destination):
                events.append("replace")
                real_replace(source, destination)
            with patch.object(atomic.os, "fsync", sync), patch.object(atomic.os, "replace", replace):
                atomic.schreiben(target, '{"claim":true}', modus=0o600, dauerhaft=True)
            self.assertEqual(events, ["file", "replace", "directory"])
            self.assertEqual(target.read_text(), '{"claim":true}')
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)

    def test_sync_failure_never_replaces_old_state(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "state"
            target.write_text("old")
            with patch.object(atomic.os, "fsync", side_effect=OSError("disk failed")):
                with self.assertRaises(OSError):
                    atomic.schreiben(target, b"new", dauerhaft=True)
            self.assertEqual(target.read_text(), "old")


if __name__ == "__main__":
    unittest.main()
