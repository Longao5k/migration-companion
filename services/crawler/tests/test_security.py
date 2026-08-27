import socket
import unittest
from migration_crawler.security import SourceRejected, validate_url


def fake_resolver(address: str):
    def resolve(_host, _port, type=socket.SOCK_STREAM):
        return [(socket.AF_INET, type, 6, '', (address, 443))]
    return resolve


class SecurityTests(unittest.TestCase):
    def test_rejects_unapproved_host(self):
        with self.assertRaises(SourceRejected):
            validate_url(
                "https://example.com/path",
                {"migration.sa.gov.au"},
                resolver=fake_resolver("8.8.8.8"),
            )

    def test_rejects_private_dns_target(self):
        with self.assertRaises(SourceRejected):
            validate_url(
                "https://migration.sa.gov.au/path",
                {"migration.sa.gov.au"},
                resolver=fake_resolver("127.0.0.1"),
            )

    def test_accepts_allowlisted_public_target(self):
        host = validate_url(
            "https://migration.sa.gov.au/news",
            {"migration.sa.gov.au"},
            resolver=fake_resolver("8.8.8.8"),
        )
        self.assertEqual(host, "migration.sa.gov.au")


if __name__ == "__main__":
    unittest.main()

