import Testing
@testable import PortKiller

/**
 * Tests for ProcessType.detect() functionality.
 *
 * These tests verify that process names are correctly categorized
 * into their appropriate ProcessType categories.
 */
struct ProcessTypeTests {

    // MARK: - Web Server Tests

    @Test("Detects nginx as web server")
    func detectNginx() {
        #expect(ProcessType.detect(from: "nginx") == .webServer)
    }

    @Test("Detects apache as web server")
    func detectApache() {
        #expect(ProcessType.detect(from: "apache2") == .webServer)
    }

    @Test("Detects httpd as web server")
    func detectHttpd() {
        #expect(ProcessType.detect(from: "httpd") == .webServer)
    }

    @Test("Detects caddy as web server")
    func detectCaddy() {
        #expect(ProcessType.detect(from: "caddy") == .webServer)
    }

    @Test("Detects traefik as web server")
    func detectTraefik() {
        #expect(ProcessType.detect(from: "traefik") == .webServer)
    }

    // MARK: - Database Tests

    @Test("Detects postgres as database")
    func detectPostgres() {
        #expect(ProcessType.detect(from: "postgres") == .database)
    }

    @Test("Detects mysql as database")
    func detectMySQL() {
        #expect(ProcessType.detect(from: "mysqld") == .database)
    }

    @Test("Detects mariadb as database")
    func detectMariaDB() {
        #expect(ProcessType.detect(from: "mariadbd") == .database)
    }

    @Test("Detects redis as database")
    func detectRedis() {
        #expect(ProcessType.detect(from: "redis-server") == .database)
    }

    @Test("Detects mongodb as database")
    func detectMongoDB() {
        #expect(ProcessType.detect(from: "mongod") == .database)
    }

    @Test("Detects cockroachdb as database")
    func detectCockroachDB() {
        #expect(ProcessType.detect(from: "cockroach") == .database)
    }

    // MARK: - Development Tests

    @Test("Detects node as development")
    func detectNode() {
        #expect(ProcessType.detect(from: "node") == .development)
    }

    @Test("Detects npm as development")
    func detectNpm() {
        #expect(ProcessType.detect(from: "npm") == .development)
    }

    @Test("Detects python as development")
    func detectPython() {
        #expect(ProcessType.detect(from: "python3") == .development)
    }

    @Test("Detects ruby as development")
    func detectRuby() {
        #expect(ProcessType.detect(from: "ruby") == .development)
    }

    @Test("Detects java as development")
    func detectJava() {
        #expect(ProcessType.detect(from: "java") == .development)
    }

    @Test("Detects go as development")
    func detectGo() {
        #expect(ProcessType.detect(from: "go") == .development)
    }

    @Test("Detects vite as development")
    func detectVite() {
        #expect(ProcessType.detect(from: "vite") == .development)
    }

    @Test("Detects webpack as development")
    func detectWebpack() {
        #expect(ProcessType.detect(from: "webpack-dev-server") == .development)
    }

    @Test("Detects next as development")
    func detectNext() {
        #expect(ProcessType.detect(from: "next-server") == .development)
    }

    // MARK: - System Tests

    @Test("Detects launchd as system")
    func detectLaunchd() {
        #expect(ProcessType.detect(from: "launchd") == .system)
    }

    @Test("Detects rapportd as system")
    func detectRapportd() {
        #expect(ProcessType.detect(from: "rapportd") == .system)
    }

    @Test("Detects sharingd as system")
    func detectSharingd() {
        #expect(ProcessType.detect(from: "sharingd") == .system)
    }

    @Test("Detects controlcenter as system")
    func detectControlCenter() {
        #expect(ProcessType.detect(from: "ControlCenter") == .system)
    }

    // MARK: - Case Insensitivity Tests

    @Test("Process detection is case insensitive")
    func detectCaseInsensitive() {
        #expect(ProcessType.detect(from: "NODE") == .development)
        #expect(ProcessType.detect(from: "Node") == .development)
        #expect(ProcessType.detect(from: "NGINX") == .webServer)
        #expect(ProcessType.detect(from: "Nginx") == .webServer)
    }

    // MARK: - Substring Matching Tests

    @Test("Detects process names containing keywords")
    func detectSubstring() {
        #expect(ProcessType.detect(from: "com.docker.backend") == .other)
        #expect(ProcessType.detect(from: "node_exporter") == .development)
        #expect(ProcessType.detect(from: "postgresql-12") == .database)
    }

    // MARK: - Other/Default Tests

    @Test("Unknown processes default to other")
    func detectUnknown() {
        #expect(ProcessType.detect(from: "unknown_process") == .other)
        #expect(ProcessType.detect(from: "custom-app") == .other)
        #expect(ProcessType.detect(from: "foobar") == .other)
    }

    @Test("Empty process name defaults to other")
    func detectEmpty() {
        #expect(ProcessType.detect(from: "") == .other)
    }

    // MARK: - Real World Examples

    @Test("Detects real world process names")
    func detectRealWorld() {
        // Development servers
        #expect(ProcessType.detect(from: "/usr/local/bin/node") == .development)
        #expect(ProcessType.detect(from: "/opt/homebrew/bin/python3.11") == .development)

        // Databases
        #expect(ProcessType.detect(from: "/usr/lib/postgresql/14/bin/postgres") == .database)
        #expect(ProcessType.detect(from: "/usr/local/mysql/bin/mysqld") == .database)

        // Web servers
        #expect(ProcessType.detect(from: "/usr/sbin/nginx") == .webServer)
        #expect(ProcessType.detect(from: "/usr/local/apache2/bin/httpd") == .webServer)
    }
}
