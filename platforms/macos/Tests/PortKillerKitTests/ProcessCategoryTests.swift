import Testing
@testable import PortKillerKit

struct ProcessCategoryTests {
    @Test(arguments: ["nginx", "apache2", "httpd", "caddy", "traefik", "/usr/sbin/nginx", "/usr/local/apache2/bin/httpd"])
    func detectsWebServers(_ name: String) {
        #expect(ProcessCategory.detect(name) == .webServer)
    }

    @Test(arguments: ["postgres", "mysqld", "mariadbd", "redis-server", "mongod", "cockroach", "postgresql-12", "/usr/lib/postgresql/14/bin/postgres", "/usr/local/mysql/bin/mysqld"])
    func detectsDatabases(_ name: String) {
        #expect(ProcessCategory.detect(name) == .database)
    }

    @Test(arguments: ["node", "npm", "python3", "ruby", "java", "go", "vite", "webpack-dev-server", "next-server", "node_exporter", "/usr/local/bin/node", "/opt/homebrew/bin/python3.11", "bun", "deno"])
    func detectsDevelopmentTools(_ name: String) {
        #expect(ProcessCategory.detect(name) == .development)
    }

    @Test(arguments: ["launchd", "rapportd", "sharingd", "ControlCenter", "mDNSResponder"])
    func detectsSystemProcesses(_ name: String) {
        #expect(ProcessCategory.detect(name) == .system)
    }

    @Test(arguments: ["", "unknown_process", "custom-app", "foobar", "com.docker.backend", "Google Chrome Helper"])
    func fallsBackToOther(_ name: String) {
        #expect(ProcessCategory.detect(name) == .other)
    }

    @Test func detectionIgnoresCase() {
        #expect(ProcessCategory.detect("NODE") == .development)
        #expect(ProcessCategory.detect("Nginx") == .webServer)
    }
}
