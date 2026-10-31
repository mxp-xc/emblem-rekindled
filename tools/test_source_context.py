"""Keep generated/minified source inspection bounded even on a single huge line."""

import unittest

from source_context import fragments


class SourceContextTest(unittest.TestCase):
    def test_minified_line_is_bounded_and_has_offsets(self):
        result = fragments(("x" * 10000 + "needle") * 50, "needle", radius=10, limit=2)
        self.assertEqual(len(result), 2)
        self.assertTrue(result[0].startswith("offset 10000: "))
        self.assertLess(len("\n".join(result)), 100)

    def test_invalid_limits_fail(self):
        for options in ({"limit": 0}, {"radius": 1000}):
            with self.assertRaises(ValueError):
                fragments("text", "t", **options)


if __name__ == "__main__":
    unittest.main()
