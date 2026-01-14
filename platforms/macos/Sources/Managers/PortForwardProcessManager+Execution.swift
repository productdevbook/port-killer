import Foundation

extension PortForwardProcessManager {
    /// Starts a kubectl port-forward process.
    func startPortForward(
        id: UUID,
        namespace: String,
        service: String,
        localPort: Int,
        remotePort: Int
    ) async throws -> Process {
        guard let kubectlPath = DependencyChecker.shared.kubectlPath else {
            throw KubectlError.kubectlNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: kubectlPath)
        process.arguments = [
            "port-forward",
            "-n", namespace,
            "svc/\(service)",
            "\(localPort):\(remotePort)",
            "--address=127.0.0.1"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        if processes[id] == nil {
            processes[id] = [:]
        }
        processes[id]?[.portForward] = process

        startReadingOutput(pipe: pipe, id: id, type: .portForward)

        return process
    }

    /// Starts a standard socat proxy process.
    func startProxy(
        id: UUID,
        externalPort: Int,
        internalPort: Int
    ) async throws -> Process {
        guard let socatPath = DependencyChecker.shared.socatPath else {
            throw KubectlError.executionFailed("socat not found")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: socatPath)
        process.arguments = [
            "TCP-LISTEN:\(externalPort),fork,reuseaddr",
            "TCP:127.0.0.1:\(internalPort)"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        if processes[id] == nil {
            processes[id] = [:]
        }
        processes[id]?[.proxy] = process

        startReadingOutput(pipe: pipe, id: id, type: .proxy)

        return process
    }

    /// Starts a direct exec proxy for multi-connection support.
    func startDirectExecProxy(
        id: UUID,
        namespace: String,
        service: String,
        externalPort: Int,
        remotePort: Int
    ) async throws -> Process {
        guard let kubectlPath = DependencyChecker.shared.kubectlPath else {
            throw KubectlError.kubectlNotFound
        }

        guard let socatPath = DependencyChecker.shared.socatPath else {
            throw KubectlError.executionFailed("socat not found for multi-connection mode")
        }

        let wrapperScript = createWrapperScript(
            kubectlPath: kubectlPath,
            socatPath: socatPath,
            namespace: namespace,
            service: service,
            remotePort: remotePort
        )

        let scriptPath = "/tmp/pf-wrapper-\(id.uuidString).sh"
        try wrapperScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptPath]
        try chmod.run()
        chmod.waitUntilExit()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: socatPath)
        process.arguments = [
            "TCP-LISTEN:\(externalPort),fork,reuseaddr",
            "EXEC:\(scriptPath)"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        if processes[id] == nil {
            processes[id] = [:]
        }
        processes[id]?[.proxy] = process

        startReadingOutput(pipe: pipe, id: id, type: .proxy)

        return process
    }

    /// Creates a bash wrapper script for multi-connection proxy.
    func createWrapperScript(
        kubectlPath: String,
        socatPath: String,
        namespace: String,
        service: String,
        remotePort: Int
    ) -> String {
        """
        #!/bin/bash
        PORT=$((30000 + ($$ % 30000)))
        while /usr/bin/nc -z 127.0.0.1 $PORT 2>/dev/null; do
            PORT=$((PORT + 1))
        done
        \(kubectlPath) port-forward -n \(namespace) svc/\(service) $PORT:\(remotePort) --address=127.0.0.1 >/dev/null 2>&1 &
        KPID=$!
        trap "kill $KPID 2>/dev/null" EXIT
        for i in 1 2 3 4 5 6 7 8 9 10; do
            if /usr/bin/nc -z 127.0.0.1 $PORT 2>/dev/null; then break; fi
            sleep 0.5
        done
        \(socatPath) - TCP:127.0.0.1:$PORT
        """
    }
}
