import unittest
from migration_crawler.normalizer import normalize_html


class NormalizerTests(unittest.TestCase):
    def test_removes_navigation_scripts_and_update_noise(self):
        raw = b"""
        <html><body>
          <nav>Menu item</nav><main><h1>Nomination requirements</h1>
          <p>Applicants must check the official criteria.</p>
          <p>Updated: 27/08/2026</p></main><script>secret()</script>
        </body></html>
        """
        value = normalize_html(raw)
        self.assertIn("Nomination requirements", value)
        self.assertNotIn("Menu item", value)
        self.assertNotIn("secret", value)
        self.assertNotIn("Updated", value)


if __name__ == "__main__":
    unittest.main()

