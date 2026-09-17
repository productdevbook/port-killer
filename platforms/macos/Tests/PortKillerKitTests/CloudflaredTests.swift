import Foundation
import Testing
@testable import PortKillerKit

struct CloudflaredTests {
    @Test func parsesLocalIngressRules() throws {
        let configuration = try #require(TunnelDiscovery.parseConfiguration("""
        tunnel: dev-tunnel
        credentials-file: /Users/test/.cloudflared/dev-tunnel.json

        ingress:
          - hostname: api.example.com
            path: /v1/*
            service: http://localhost:3000
          - hostname: app.example.com
            service: http://127.0.0.1:5173
          - service: http_status:404
        """))

        #expect(configuration.tunnel == "dev-tunnel")
        #expect(configuration.ingress.count == 3)
        #expect(configuration.ingress[0].hostname == "api.example.com")
        #expect(configuration.ingress[0].path == "/v1/*")
        #expect(configuration.ingress[0].localPort == 3000)
        #expect(configuration.ingress[0].publicURL == "https://api.example.com/v1/*")
        #expect(configuration.ingress[1].localPort == 5173)
        #expect(configuration.ingress[2].hostname == nil)
        #expect(configuration.ingress[2].publicURL == nil)
    }

    @Test func stripsQuotesAndComments() throws {
        let configuration = try #require(TunnelDiscovery.parseConfiguration("""
        tunnel: "7c48df31-7c1f-4f87-a17d-a1a7f0622b9d" # account tunnel
        ingress:
          - hostname: 'www.example.com'
            path: "admin"
            service: "http://localhost:8080"
        """))

        #expect(configuration.tunnel == "7c48df31-7c1f-4f87-a17d-a1a7f0622b9d")
        #expect(configuration.ingress.first?.hostname == "www.example.com")
        #expect(configuration.ingress.first?.publicURL == "https://www.example.com/admin")
    }

    @Test func handlesCommentLinesBlankLinesAndTabs() throws {
        let configuration = try #require(TunnelDiscovery.parseConfiguration("# top\ntunnel: dev-tunnel\n\n# ingress\ningress:\n\t- hostname: api.example.com\n\t  service: http://localhost:3000 # trailing\n\t- service: http_status:404\n"))

        #expect(configuration.ingress.map(\.service) == ["http://localhost:3000", "http_status:404"])
    }

    @Test func requiresATunnelReference() {
        #expect(TunnelDiscovery.parseConfiguration("ingress:\n  - service: http://localhost:3000\n") == nil)
    }

    @Test func publicURLOmitsAnEmptyPath() {
        #expect(TunnelIngressRule(hostname: "api.example.com", service: "http://localhost:3000").publicURL == "https://api.example.com")
    }
}
