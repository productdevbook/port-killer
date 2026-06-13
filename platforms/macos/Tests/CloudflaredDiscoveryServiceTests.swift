import Testing
@testable import PortKiller

struct CloudflaredDiscoveryServiceTests {
    @Test("Parses local cloudflared config ingress rules")
    func parsesLocalConfigIngressRules() {
        let service = CloudflaredDiscoveryService()
        let config = """
        tunnel: dev-tunnel
        credentials-file: /Users/test/.cloudflared/dev-tunnel.json

        ingress:
          - hostname: api.example.com
            path: /v1/*
            service: http://localhost:3000
          - hostname: app.example.com
            service: http://127.0.0.1:5173
          - service: http_status:404
        """

        let parsed = service.parseConfigYAML(config)

        #expect(parsed?.tunnelRef == "dev-tunnel")
        #expect(parsed?.ingress.count == 3)
        #expect(parsed?.ingress[0].hostname == "api.example.com")
        #expect(parsed?.ingress[0].path == "/v1/*")
        #expect(parsed?.ingress[0].service == "http://localhost:3000")
        #expect(parsed?.ingress[0].localPort == 3000)
        #expect(parsed?.ingress[0].publicURL == "https://api.example.com/v1/*")
        #expect(parsed?.ingress[1].localPort == 5173)
        #expect(parsed?.ingress[2].hostname == nil)
        #expect(parsed?.ingress[2].publicURL == nil)
    }

    @Test("Parses quoted tunnel references and strips comments")
    func parsesQuotedValuesAndComments() {
        let service = CloudflaredDiscoveryService()
        let config = """
        tunnel: "7c48df31-7c1f-4f87-a17d-a1a7f0622b9d" # account tunnel
        ingress:
          - hostname: 'www.example.com'
            path: "admin"
            service: "http://localhost:8080"
        """

        let parsed = service.parseConfigYAML(config)

        #expect(parsed?.tunnelRef == "7c48df31-7c1f-4f87-a17d-a1a7f0622b9d")
        #expect(parsed?.ingress.first?.hostname == "www.example.com")
        #expect(parsed?.ingress.first?.path == "admin")
        #expect(parsed?.ingress.first?.service == "http://localhost:8080")
        #expect(parsed?.ingress.first?.publicURL == "https://www.example.com/admin")
    }

    @Test("Ingress public URL omits an empty path")
    func publicURLOmitsEmptyPath() {
        let rule = CloudflareTunnelIngressRule(hostname: "api.example.com", service: "http://localhost:3000")

        #expect(rule.publicURL == "https://api.example.com")
    }

    @Test("Handles comment-only lines, blank lines and tab indentation")
    func handlesCommentsBlankLinesAndTabs() {
        let service = CloudflaredDiscoveryService()
        // Mixes a full-line comment, blank lines, and tab-indented ingress entries.
        let config = "# top-level comment\n"
            + "tunnel: dev-tunnel\n"
            + "\n"
            + "# ingress below\n"
            + "ingress:\n"
            + "\t- hostname: api.example.com\n"
            + "\t  service: http://localhost:3000 # trailing comment\n"
            + "\t- service: http_status:404\n"

        let parsed = service.parseConfigYAML(config)

        #expect(parsed?.tunnelRef == "dev-tunnel")
        #expect(parsed?.ingress.count == 2)
        #expect(parsed?.ingress[0].hostname == "api.example.com")
        #expect(parsed?.ingress[0].service == "http://localhost:3000")
        #expect(parsed?.ingress[1].hostname == nil)
        #expect(parsed?.ingress[1].service == "http_status:404")
    }

    @Test("Returns nil when no tunnel reference is present")
    func returnsNilWithoutTunnelRef() {
        let service = CloudflaredDiscoveryService()
        let config = """
        ingress:
          - hostname: api.example.com
            service: http://localhost:3000
        """

        #expect(service.parseConfigYAML(config) == nil)
    }
}
