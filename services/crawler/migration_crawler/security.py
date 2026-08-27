import ipaddress
import socket
from urllib.parse import urlparse


class SourceRejected(ValueError):
    pass


def validate_url(url: str, allowed_hosts: set[str], resolver=socket.getaddrinfo) -> str:
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise SourceRejected("source must be a credential-free HTTPS URL")
    host = parsed.hostname.lower().rstrip(".")
    if host not in allowed_hosts:
        raise SourceRejected("source host is not on the approved allowlist")

    addresses = {row[4][0] for row in resolver(host, 443, type=socket.SOCK_STREAM)}
    if not addresses:
        raise SourceRejected("source host did not resolve")
    for address in addresses:
        ip = ipaddress.ip_address(address)
        if not ip.is_global:
            raise SourceRejected("source resolved to a private or special-purpose address")
    return host

