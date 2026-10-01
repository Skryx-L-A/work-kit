import unittest

from pager import page, page_count


class PagerTest(unittest.TestCase):
    def test_first_page(self):
        self.assertEqual(page(list(range(10)), 1, 3), [0, 1, 2])

    def test_last_partial_page(self):
        self.assertEqual(page(list(range(10)), 4, 3), [9])

    def test_page_count(self):
        self.assertEqual(page_count(list(range(10)), 3), 4)

    def test_invalid(self):
        with self.assertRaises(ValueError):
            page([1], 0, 3)


if __name__ == "__main__":
    unittest.main()
