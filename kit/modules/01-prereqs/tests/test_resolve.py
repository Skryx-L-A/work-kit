"""Unit tests for resolve.py (stdlib unittest; also runs under pytest)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import resolve  # noqa: E402


class VersionTest(unittest.TestCase):
    def test_order(self):
        pairs = [("1.0", "1.0.1"), ("1.0~rc1", "1.0"), ("2.0", "1:0.1"), ("2.43.0-1ubuntu7", "2.43.0-1ubuntu7.3"),
                 ("1.2a", "1.2b"), ("1.0-1", "1.0-1+b1"), ("0.13-3", "0.13-3build1"), ("1.9", "1.10")]
        for a, b in pairs:
            self.assertEqual(resolve.vercmp(a, b), -1, (a, b))
            self.assertEqual(resolve.vercmp(b, a), 1, (b, a))
        self.assertEqual(resolve.vercmp("1.0-1", "1.0-1"), 0)
        self.assertEqual(resolve.vercmp("0:1.0", "1.0"), 0)

    def test_constraints(self):
        self.assertTrue(resolve.version_ok("2.39-0ubuntu8", ">=", "2.34"))
        self.assertFalse(resolve.version_ok("2.39", "<<", "2.39"))
        self.assertTrue(resolve.version_ok("1", None, None))


class RelationTest(unittest.TestCase):
    def test_parse(self):
        got = resolve.parse_relations("libc6 (>= 2.34), python3:any, a | b (<< 2) [amd64]")
        self.assertEqual(got, [[("libc6", ">=", "2.34")], [("python3", None, None)],
                               [("a", None, None), ("b", "<<", "2")]])


def stanza(name, version, depends="", provides="", pre=""):
    st = {"Package": name, "Version": version, "Architecture": "amd64",
          "Filename": "pool/%s_%s.deb" % (name, version), "Size": "1", "SHA256": "0" * 64}
    if depends:
        st["Depends"] = depends
    if provides:
        st["Provides"] = provides
    if pre:
        st["Pre-Depends"] = pre
    return st


class ResolveTest(unittest.TestCase):
    def archive(self, *stanzas):
        a = resolve.Archive()
        for st in stanzas:
            a.add(dict(st), "http://x")
        a.finish()
        return a

    def test_highest_version_and_closure(self):
        a = self.archive(stanza("app", "1", "libx (>= 2), liby | libz"), stanza("libx", "1"), stanza("libx", "2"),
                         stanza("liby", "1", pre="libc6"), stanza("libz", "1"), stanza("libc6", "2.39"))
        got = resolve.resolve(a, ["app"], lambda m: None)
        self.assertEqual(got, ["app", "libx", "liby", "libc6"])
        self.assertEqual(a.best["libx"]["Version"], "2")

    def test_virtual_provider(self):
        a = self.archive(stanza("chrome", "1", "libasound2 (>= 1.0.17)"),
                         stanza("libasound2t64", "1.2.11", provides="libasound2 (= 1.2.11)"))
        self.assertEqual(resolve.resolve(a, ["chrome"], lambda m: None), ["chrome", "libasound2t64"])

    def test_prefers_already_chosen_alternative(self):
        a = self.archive(stanza("app", "1", "libz, liby | libz"), stanza("liby", "1"), stanza("libz", "1"))
        self.assertEqual(resolve.resolve(a, ["app"], lambda m: None), ["app", "libz"])

    def test_unsatisfiable(self):
        a = self.archive(stanza("app", "1", "libx (>= 3)"), stanza("libx", "2"))
        with self.assertRaises(SystemExit):
            resolve.resolve(a, ["app"], lambda m: None)


if __name__ == "__main__":
    unittest.main()
