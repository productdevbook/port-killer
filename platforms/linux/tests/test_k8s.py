"""
Tests for kubectl port-forward command-line parsing.

Run with:  python3 -m unittest discover -s platforms/linux/tests
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from src.services.k8s import K8sService


class TestParsePortForwardCmd(unittest.TestCase):
    def setUp(self):
        self.svc = K8sService()

    def parse(self, cmd):
        return self.svc._parse_port_forward_cmd(1234, cmd)

    def test_service_with_namespace(self):
        fw = self.parse("kubectl port-forward svc/my-service 8080:80 -n dev")
        self.assertEqual(fw.resource, "svc/my-service")
        self.assertEqual(fw.local_port, 8080)
        self.assertEqual(fw.remote_port, 80)
        self.assertEqual(fw.namespace, "dev")

    def test_default_namespace(self):
        fw = self.parse("kubectl port-forward pod/my-pod 5432:5432")
        self.assertEqual(fw.resource, "pod/my-pod")
        self.assertEqual(fw.namespace, "default")

    def test_namespace_with_equals(self):
        fw = self.parse("kubectl port-forward svc/api 3000:3000 --namespace=prod")
        self.assertEqual(fw.namespace, "prod")
        self.assertEqual(fw.resource, "svc/api")

    def test_namespace_flag_value_not_mistaken_for_resource(self):
        # "-n dev" comes before the resource; "dev" must not win
        fw = self.parse("kubectl port-forward -n dev deployment/web 8000:80")
        self.assertEqual(fw.namespace, "dev")
        self.assertEqual(fw.resource, "deployment/web")

    def test_context_flag_value_not_mistaken_for_resource(self):
        fw = self.parse("kubectl port-forward --context staging svc/api 9090:90")
        self.assertEqual(fw.resource, "svc/api")

    def test_bare_pod_name(self):
        fw = self.parse("kubectl port-forward mypod 8080:80")
        self.assertEqual(fw.resource, "mypod")

    def test_single_port_maps_to_itself(self):
        fw = self.parse("kubectl port-forward svc/redis 6379")
        self.assertEqual(fw.local_port, 6379)
        self.assertEqual(fw.remote_port, 6379)

    def test_grep_lines_are_ignored(self):
        self.assertIsNone(self.parse("grep kubectl port-forward"))

    def test_raw_cmd_is_preserved(self):
        cmd = "kubectl port-forward svc/my-service 8080:80 -n dev"
        self.assertEqual(self.parse(cmd).raw_cmd, cmd)


class TestKillAllSafety(unittest.TestCase):
    def test_kill_all_only_targets_scanned_pids(self):
        """kill_all must not fall back to a broad pkill pattern."""
        svc = K8sService()
        killed = []

        svc.scan_active_forwards = lambda: [
            type("FW", (), {"pid": 111})(),
            type("FW", (), {"pid": 222})(),
        ]
        svc.stop_port_forward = lambda pid: (killed.append(pid), True)[1]

        self.assertTrue(svc.kill_all())
        self.assertEqual(killed, [111, 222])

    def test_kill_all_reports_failure(self):
        svc = K8sService()
        svc.scan_active_forwards = lambda: [type("FW", (), {"pid": 111})()]
        svc.stop_port_forward = lambda pid: False
        self.assertFalse(svc.kill_all())


if __name__ == "__main__":
    unittest.main()
