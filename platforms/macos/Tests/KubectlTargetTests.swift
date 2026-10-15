import Foundation
import Testing
@testable import PortKiller

/**
 * Tests for Kubernetes context / kubeconfig support:
 * kubectl argument building, wrapper script quoting, context parsing,
 * and backward-compatible decoding of saved connections.
 */
struct KubectlTargetTests {

    // MARK: - Global Arguments

    @Test("Default target adds no global arguments")
    func defaultTargetHasNoArguments() {
        #expect(KubectlTarget.default.globalArguments.isEmpty)
        #expect(KubectlTarget.default.arguments(["get", "ns"]) == ["get", "ns"])
    }

    @Test("Empty and whitespace values fall back to kubectl defaults")
    func emptyValuesIgnored() {
        let target = KubectlTarget(context: "  ", kubeconfigPath: "")
        #expect(target.resolvedContext == nil)
        #expect(target.resolvedKubeconfigPath == nil)
        #expect(target.globalArguments.isEmpty)
    }

    @Test("Context and kubeconfig are passed as single --flag=value arguments")
    func contextAndKubeconfigArguments() {
        let target = KubectlTarget(context: "prod-cluster", kubeconfigPath: "/etc/kube/config")
        #expect(target.arguments(["get", "namespaces"]) == [
            "--kubeconfig=/etc/kube/config",
            "--context=prod-cluster",
            "get", "namespaces"
        ])
    }

    @Test("Kubeconfig path expands tilde")
    func kubeconfigTildeExpansion() {
        let target = KubectlTarget(kubeconfigPath: "~/.kube/other")
        let expected = (NSHomeDirectory() as NSString).appendingPathComponent(".kube/other")
        #expect(target.resolvedKubeconfigPath == expected)
        #expect(target.globalArguments == ["--kubeconfig=\(expected)"])
    }

    @Test("Values that look like flags or shell syntax stay in one argument")
    func injectionSafeArguments() {
        let target = KubectlTarget(context: "--all; rm -rf /", kubeconfigPath: nil)
        #expect(target.globalArguments == ["--context=--all; rm -rf /"])
    }

    @Test("kubeconfigOnly drops the context")
    func kubeconfigOnly() {
        let target = KubectlTarget(context: "dev", kubeconfigPath: "/tmp/kc")
        #expect(target.kubeconfigOnly.globalArguments == ["--kubeconfig=/tmp/kc"])
    }

    @Test("Port-forward arguments include the target")
    func portForwardArguments() {
        let args = PortForwardProcessManager.portForwardArguments(
            namespace: "default",
            service: "api",
            portMapping: "8080:80",
            target: KubectlTarget(context: "staging", kubeconfigPath: "/tmp/kc")
        )
        #expect(args == [
            "--kubeconfig=/tmp/kc",
            "--context=staging",
            "port-forward", "-n", "default", "svc/api", "8080:80", "--address=127.0.0.1"
        ])
    }

    @Test("Port-forward arguments are unchanged for the default target")
    func portForwardArgumentsDefault() {
        let args = PortForwardProcessManager.portForwardArguments(
            namespace: "default",
            service: "api",
            portMapping: "8080:80",
            target: .default
        )
        #expect(args == ["port-forward", "-n", "default", "svc/api", "8080:80", "--address=127.0.0.1"])
    }

    // MARK: - Wrapper Script

    @Test("Shell quoting escapes single quotes")
    func shellQuote() {
        #expect(PortForwardProcessManager.shellQuote("abc") == "'abc'")
        #expect(PortForwardProcessManager.shellQuote("it's") == "'it'\\''s'")
        #expect(PortForwardProcessManager.shellQuote("$(whoami)") == "'$(whoami)'")
    }

    @Test("Wrapper script passes quoted context and kubeconfig to kubectl")
    func wrapperScriptIncludesTarget() {
        let script = PortForwardProcessManager().createWrapperScript(
            kubectlPath: "/usr/local/bin/kubectl",
            socatPath: "/usr/local/bin/socat",
            namespace: "default",
            service: "api",
            remotePort: 80,
            target: KubectlTarget(context: "my ctx; echo pwned", kubeconfigPath: "/tmp/kc")
        )
        #expect(script.contains(
            "'/usr/local/bin/kubectl' '--kubeconfig=/tmp/kc' '--context=my ctx; echo pwned' 'port-forward' '-n' 'default' 'svc/api' \"$PORT:80\" '--address=127.0.0.1' >/dev/null 2>&1 &"
        ))
        #expect(script.contains("'/usr/local/bin/socat' - TCP:127.0.0.1:$PORT"))
    }

    // MARK: - Context Parsing

    @Test("Parses context names from get-contexts output")
    func parseContextNames() {
        let output = "kind-dev\n\ngke_project_zone_prod\r\nkind-dev\n  minikube  \n"
        #expect(KubernetesContextParser.parseContextNames(output) == [
            "kind-dev", "gke_project_zone_prod", "minikube"
        ])
    }

    // MARK: - Codable

    @Test("Decodes saved connections without context fields")
    func decodesLegacyConfig() throws {
        let json = """
        {
            "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "name": "api",
            "namespace": "default",
            "service": "api",
            "localPort": 8080,
            "remotePort": 80,
            "isEnabled": true,
            "autoReconnect": true,
            "useDirectExec": false,
            "notifyOnConnect": true,
            "notifyOnDisconnect": false
        }
        """
        let config = try JSONDecoder().decode(PortForwardConnectionConfig.self, from: Data(json.utf8))
        #expect(config.kubeContext == nil)
        #expect(config.kubeconfigPath == nil)
        #expect(config.kubectlTarget == .default)
        #expect(config.notifyOnDisconnect == false)
    }

    @Test("Round-trips context and kubeconfig")
    func roundTripsTarget() throws {
        let config = PortForwardConnectionConfig(
            name: "db",
            namespace: "data",
            service: "postgres",
            localPort: 5432,
            remotePort: 5432,
            kubeContext: "prod",
            kubeconfigPath: "/Users/me/.kube/prod.yaml"
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PortForwardConnectionConfig.self, from: data)
        #expect(decoded == config)
        #expect(decoded.kubectlTarget == KubectlTarget(context: "prod", kubeconfigPath: "/Users/me/.kube/prod.yaml"))
    }

    @Test("Omits context fields when unset")
    func omitsUnsetFields() throws {
        let config = PortForwardConnectionConfig(
            name: "api", namespace: "default", service: "api", localPort: 8080, remotePort: 80
        )
        let json = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        #expect(!json.contains("kubeContext"))
        #expect(!json.contains("kubeconfigPath"))
    }
}
