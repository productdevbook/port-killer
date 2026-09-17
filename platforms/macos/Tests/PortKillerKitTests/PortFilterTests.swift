import Testing
@testable import PortKillerKit

struct PortFilterTests {
    func port(_ number: Int = 3000, pid: Int32 = 12345, name: String = "node", address: String = "127.0.0.1", user: String = "testuser", command: String = "node server.js") -> ListeningPort {
        ListeningPort(port: number, addresses: [address], process: ProcessSnapshot(pid: pid, name: name, commandLine: command, user: user))
    }

    @Test func emptyFilterIsInactive() {
        #expect(!PortFilter().isActive)
    }

    @Test func searchRangeAndCategoriesActivateTheFilter() {
        #expect(PortFilter(searchText: "node").isActive)
        #expect(PortFilter(minPort: 3000).isActive)
        #expect(PortFilter(maxPort: 9000).isActive)
        #expect(PortFilter(categories: [.development]).isActive)
        #expect(!PortFilter(searchText: "   ").isActive)
    }

    @Test(arguments: ["node", "3000", "12345", "127.0.0.1", "testuser", "server.js", "NODE", "serv"])
    func searchMatchesEveryField(_ query: String) {
        #expect(PortFilter(searchText: query).matches(port(), category: .development))
    }

    @Test func searchMatchesLabels() {
        #expect(PortFilter(searchText: "frontend").matches(port(), category: .development, label: "Frontend"))
        #expect(!PortFilter(searchText: "frontend").matches(port(), category: .development))
    }

    @Test func searchWithoutMatchFails() {
        #expect(!PortFilter(searchText: "python").matches(port(), category: .development))
    }

    @Test func portRangeIsInclusive() {
        let filter = PortFilter(minPort: 3000, maxPort: 5000)
        #expect(!filter.matches(port(2000), category: .other))
        #expect(filter.matches(port(3000), category: .other))
        #expect(filter.matches(port(4000), category: .other))
        #expect(filter.matches(port(5000), category: .other))
        #expect(!filter.matches(port(6000), category: .other))
    }

    @Test func categoriesFilterByProcessCategory() {
        let filter = PortFilter(categories: [.development, .webServer])
        #expect(filter.matches(port(), category: .development))
        #expect(filter.matches(port(), category: .webServer))
        #expect(!filter.matches(port(), category: .database))
    }

    @Test func criteriaCombine() {
        let filter = PortFilter(searchText: "node", minPort: 3000, maxPort: 5000)
        #expect(filter.matches(port(3000), category: .development))
        #expect(!filter.matches(port(3000, name: "python", command: "python app.py"), category: .development))
        #expect(!filter.matches(port(8000), category: .development))
    }

    @Test func resetClearsEverything() {
        var filter = PortFilter(searchText: "node", minPort: 3000, maxPort: 5000, categories: [.development])
        filter.reset()
        #expect(filter == PortFilter())
    }
}
