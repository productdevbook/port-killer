"""
Tests for the Linux port scanner output parsers.

These cover the pure string-parsing paths only; nothing here shells out.

Run with:  python3 -m unittest discover -s platforms/linux/tests
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from src.scanner import PortScanner


class TestParseAddress(unittest.TestCase):
    def test_ipv4(self):
        self.assertEqual(PortScanner.parse_address("127.0.0.1:3000"), ("127.0.0.1", 3000))
        self.assertEqual(PortScanner.parse_address("0.0.0.0:443"), ("0.0.0.0", 443))

    def test_wildcard(self):
        self.assertEqual(PortScanner.parse_address("*:8080"), ("*", 8080))

    def test_empty_address_becomes_wildcard(self):
        self.assertEqual(PortScanner.parse_address(":8080"), ("*", 8080))

    def test_ipv6(self):
        self.assertEqual(PortScanner.parse_address("[::1]:3000"), ("[::1]", 3000))
        self.assertEqual(PortScanner.parse_address("[fe80::1]:8080"), ("[fe80::1]", 8080))

    def test_invalid(self):
        self.assertIsNone(PortScanner.parse_address("no-colon-here"))
        self.assertIsNone(PortScanner.parse_address("127.0.0.1:notaport"))
        self.assertIsNone(PortScanner.parse_address("[::1]"))


class TestParseSsUsers(unittest.TestCase):
    def test_single(self):
        res = PortScanner.parse_ss_users('users:(("node",pid=1234,fd=23))')
        self.assertEqual(res, [("node", 1234)])

    def test_multiple(self):
        res = PortScanner.parse_ss_users(
            'users:(("nginx",pid=1235,fd=6),("nginx",pid=1234,fd=6))'
        )
        self.assertEqual(res, [("nginx", 1235), ("nginx", 1234)])

    def test_no_process_info(self):
        self.assertEqual(PortScanner.parse_ss_users(""), [])
        self.assertEqual(PortScanner.parse_ss_users("0.0.0.0:*"), [])

    def test_malformed_pid_is_skipped(self):
        self.assertEqual(PortScanner.parse_ss_users('users:(("x",pid=abc,fd=1))'), [])


class TestParseSsOutput(unittest.TestCase):
    def _scan(self, output):
        # get_process_commands() shells out to ps; stub it for these tests.
        original = PortScanner.get_process_commands
        PortScanner.get_process_commands = staticmethod(lambda: {})
        try:
            return PortScanner.parse_ss_output(output)
        finally:
            PortScanner.get_process_commands = original

    def test_parses_rows_and_skips_header(self):
        output = (
            "State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process\n"
            'LISTEN 0      4096   127.0.0.1:3000     0.0.0.0:*  users:(("node",pid=1234,fd=23))\n'
            'LISTEN 0      511    [::1]:8080         [::]:*     users:(("nginx",pid=555,fd=6))\n'
        )
        ports = self._scan(output)
        self.assertEqual(len(ports), 2)
        self.assertEqual(ports[0]["port"], 3000)
        self.assertEqual(ports[0]["pid"], 1234)
        self.assertEqual(ports[0]["process_name"], "node")
        self.assertEqual(ports[0]["address"], "127.0.0.1")
        self.assertEqual(ports[1]["port"], 8080)
        self.assertEqual(ports[1]["address"], "[::1]")

    def test_localised_header_is_still_skipped(self):
        # A translated header must not be parsed as a data row.
        output = (
            "Estado Recv-Q Send-Q Direccion local:Puerto Peer Address:Port\n"
            'LISTEN 0      4096   127.0.0.1:3000     0.0.0.0:*  users:(("node",pid=1,fd=2))\n'
        )
        ports = self._scan(output)
        self.assertEqual(len(ports), 1)
        self.assertEqual(ports[0]["port"], 3000)

    def test_row_without_process_column(self):
        # Unprivileged ss omits users:(...) for other users' sockets
        output = (
            "State  Recv-Q Send-Q Local Address:Port Peer Address:Port\n"
            "LISTEN 0      128    0.0.0.0:22         0.0.0.0:*\n"
        )
        ports = self._scan(output)
        self.assertEqual(len(ports), 1)
        self.assertEqual(ports[0]["port"], 22)
        self.assertEqual(ports[0]["pid"], 0)
        self.assertEqual(ports[0]["process_name"], "Unknown")

    def test_results_are_sorted_by_port(self):
        output = (
            "State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process\n"
            'LISTEN 0 0 127.0.0.1:9000 0.0.0.0:* users:(("b",pid=2,fd=1))\n'
            'LISTEN 0 0 127.0.0.1:3000 0.0.0.0:* users:(("a",pid=1,fd=1))\n'
        )
        ports = self._scan(output)
        self.assertEqual([p["port"] for p in ports], [3000, 9000])


class TestParseLsofOutput(unittest.TestCase):
    def _scan(self, output):
        original = PortScanner.get_process_commands
        PortScanner.get_process_commands = staticmethod(lambda: {1234: "node server.js"})
        try:
            return PortScanner.parse_lsof_output(output)
        finally:
            PortScanner.get_process_commands = original

    def test_parses_and_dedupes(self):
        output = (
            "COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME\n"
            "node    1234 user   23u  IPv4  56789      0t0  TCP 127.0.0.1:3000 (LISTEN)\n"
            "node    1234 user   24u  IPv4  56790      0t0  TCP 127.0.0.1:3000 (LISTEN)\n"
            "nginx    555 root    6u  IPv6  11111      0t0  TCP [::1]:8080 (LISTEN)\n"
        )
        ports = self._scan(output)
        self.assertEqual(len(ports), 2)
        self.assertEqual(ports[0]["port"], 3000)
        self.assertEqual(ports[0]["command"], "node server.js")
        self.assertEqual(ports[1]["port"], 8080)
        self.assertEqual(ports[1]["address"], "[::1]")
        # Falls back to the process name when ps has no entry for the pid
        self.assertEqual(ports[1]["command"], "nginx")

    def test_empty_output(self):
        self.assertEqual(self._scan(""), [])
        self.assertEqual(self._scan("COMMAND  PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\n"), [])


if __name__ == "__main__":
    unittest.main()
