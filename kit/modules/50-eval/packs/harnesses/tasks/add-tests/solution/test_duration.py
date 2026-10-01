import unittest

from duration import parse_duration


class ParseDurationTest(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(parse_duration("1h30m"), 5400)
        self.assertEqual(parse_duration("45s"), 45)
        self.assertEqual(parse_duration("2h"), 7200)
        self.assertEqual(parse_duration(" 1M5S "), 65)

    def test_invalid(self):
        for bad in ["", "abc", "10x", "1h 30m", "h1"]:
            with self.assertRaises(ValueError):
                parse_duration(bad)


if __name__ == "__main__":
    unittest.main()
