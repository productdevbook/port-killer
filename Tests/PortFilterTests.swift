import Testing
@testable import PortKiller

/**
 * Tests for PortFilter matching logic.
 *
 * These tests verify that the PortFilter correctly filters ports
 * based on various criteria including search text, port ranges,
 * process types, favorites, and watched ports.
 */
struct PortFilterTests {

    // MARK: - Test Fixtures

    /// Creates a sample active port for testing
    func createPort(
        port: Int = 3000,
        pid: Int = 12345,
        processName: String = "node",
        address: String = "127.0.0.1",
        user: String = "testuser",
        command: String = "node server.js"
    ) -> PortInfo {
        PortInfo.active(
            port: port,
            pid: pid,
            processName: processName,
            address: address,
            user: user,
            command: command,
            fd: "19u"
        )
    }

    // MARK: - isActive Tests

    @Test("Empty filter is not active")
    func emptyFilterNotActive() {
        let filter = PortFilter()
        #expect(!filter.isActive)
    }

    @Test("Filter with search text is active")
    func searchTextMakesActive() {
        var filter = PortFilter()
        filter.searchText = "node"
        #expect(filter.isActive)
    }

    @Test("Filter with port range is active")
    func portRangeMakesActive() {
        var filter = PortFilter()
        filter.minPort = 3000
        #expect(filter.isActive)

        var filter2 = PortFilter()
        filter2.maxPort = 9000
        #expect(filter2.isActive)
    }

    @Test("Filter with process types is active")
    func processTypesMakesActive() {
        var filter = PortFilter()
        filter.processTypes = [.development]
        #expect(filter.isActive)
    }

    @Test("Filter with favorites flag is active")
    func favoritesFlagMakesActive() {
        var filter = PortFilter()
        filter.showOnlyFavorites = true
        #expect(filter.isActive)
    }

    @Test("Filter with watched flag is active")
    func watchedFlagMakesActive() {
        var filter = PortFilter()
        filter.showOnlyWatched = true
        #expect(filter.isActive)
    }

    // MARK: - Search Text Tests

    @Test("Search matches process name")
    func searchMatchesProcessName() {
        let filter = PortFilter(searchText: "node")
        let port = createPort(processName: "node")
        #expect(filter.matches(port, favorites: [], watched: []))
    }

    @Test("Search matches port number")
    func searchMatchesPortNumber() {
        let filter = PortFilter(searchText: "3000")
        let port = createPort(port: 3000)
        #expect(filter.matches(port, favorites: [], watched: []))
    }

    @Test("Search matches PID")
    func searchMatchesPID() {
        let filter = PortFilter(searchText: "12345")
        let port = createPort(pid: 12345)
        #expect(filter.matches(port, favorites: [], watched: []))
    }

    @Test("Search matches address")
    func searchMatchesAddress() {
        let filter = PortFilter(searchText: "127.0.0.1")
        let port = createPort(address: "127.0.0.1")
        #expect(filter.matches(port, favorites: [], watched: []))
    }

    @Test("Search matches user")
    func searchMatchesUser() {
        let filter = PortFilter(searchText: "testuser")
        let port = createPort(user: "testuser")
        #expect(filter.matches(port, favorites: [], watched: []))
    }

    @Test("Search matches command")
    func searchMatchesCommand() {
        let filter = PortFilter(searchText: "server.js")
        let port = createPort(command: "node server.js")
        #expect(filter.matches(port, favorites: [], watched: []))
    }

    @Test("Search is case insensitive")
    func searchCaseInsensitive() {
        let filter = PortFilter(searchText: "NODE")
        let port = createPort(processName: "node")
        #expect(filter.matches(port, favorites: [], watched: []))
    }

    @Test("Search with no match returns false")
    func searchNoMatch() {
        let filter = PortFilter(searchText: "python")
        let port = createPort(processName: "node")
        #expect(!filter.matches(port, favorites: [], watched: []))
    }

    // MARK: - Port Range Tests

    @Test("Min port filter")
    func minPortFilter() {
        var filter = PortFilter()
        filter.minPort = 5000

        let portBelow = createPort(port: 3000)
        let portEqual = createPort(port: 5000)
        let portAbove = createPort(port: 8000)

        #expect(!filter.matches(portBelow, favorites: [], watched: []))
        #expect(filter.matches(portEqual, favorites: [], watched: []))
        #expect(filter.matches(portAbove, favorites: [], watched: []))
    }

    @Test("Max port filter")
    func maxPortFilter() {
        var filter = PortFilter()
        filter.maxPort = 5000

        let portBelow = createPort(port: 3000)
        let portEqual = createPort(port: 5000)
        let portAbove = createPort(port: 8000)

        #expect(filter.matches(portBelow, favorites: [], watched: []))
        #expect(filter.matches(portEqual, favorites: [], watched: []))
        #expect(!filter.matches(portAbove, favorites: [], watched: []))
    }

    @Test("Port range filter")
    func portRangeFilter() {
        var filter = PortFilter()
        filter.minPort = 3000
        filter.maxPort = 5000

        let portBelow = createPort(port: 2000)
        let portInRange = createPort(port: 4000)
        let portAbove = createPort(port: 6000)

        #expect(!filter.matches(portBelow, favorites: [], watched: []))
        #expect(filter.matches(portInRange, favorites: [], watched: []))
        #expect(!filter.matches(portAbove, favorites: [], watched: []))
    }

    // MARK: - Process Type Tests

    @Test("Process type filter")
    func processTypeFilter() {
        var filter = PortFilter()
        filter.processTypes = [.development]

        let nodePort = createPort(processName: "node") // Development
        let nginxPort = createPort(processName: "nginx") // Web server

        #expect(filter.matches(nodePort, favorites: [], watched: []))
        #expect(!filter.matches(nginxPort, favorites: [], watched: []))
    }

    @Test("Multiple process types filter")
    func multipleProcessTypesFilter() {
        var filter = PortFilter()
        filter.processTypes = [.development, .webServer]

        let nodePort = createPort(processName: "node") // Development
        let nginxPort = createPort(processName: "nginx") // Web server
        let postgresPort = createPort(processName: "postgres") // Database

        #expect(filter.matches(nodePort, favorites: [], watched: []))
        #expect(filter.matches(nginxPort, favorites: [], watched: []))
        #expect(!filter.matches(postgresPort, favorites: [], watched: []))
    }

    // MARK: - Favorites Filter Tests

    @Test("Show only favorites filter")
    func showOnlyFavoritesFilter() {
        var filter = PortFilter()
        filter.showOnlyFavorites = true

        let port = createPort(port: 3000)
        let favorites: Set<Int> = [3000, 8080]

        #expect(filter.matches(port, favorites: favorites, watched: []))

        let nonFavoritePort = createPort(port: 5000)
        #expect(!filter.matches(nonFavoritePort, favorites: favorites, watched: []))
    }

    // MARK: - Watched Filter Tests

    @Test("Show only watched filter")
    func showOnlyWatchedFilter() {
        var filter = PortFilter()
        filter.showOnlyWatched = true

        let port = createPort(port: 3000)
        let watched = [WatchedPort(port: 3000), WatchedPort(port: 8080)]

        #expect(filter.matches(port, favorites: [], watched: watched))

        let nonWatchedPort = createPort(port: 5000)
        #expect(!filter.matches(nonWatchedPort, favorites: [], watched: watched))
    }

    // MARK: - Combined Filter Tests

    @Test("Multiple filters combine with AND logic")
    func combinedFilters() {
        var filter = PortFilter()
        filter.searchText = "node"
        filter.minPort = 3000
        filter.maxPort = 5000

        // Matches all criteria
        let matchingPort = createPort(port: 3000, processName: "node")
        #expect(filter.matches(matchingPort, favorites: [], watched: []))

        // Fails search (command also shouldn't contain "node")
        let failsSearch = createPort(port: 3000, processName: "python", command: "python app.py")
        #expect(!filter.matches(failsSearch, favorites: [], watched: []))

        // Fails range
        let failsRange = createPort(port: 8000, processName: "node")
        #expect(!filter.matches(failsRange, favorites: [], watched: []))
    }

    // MARK: - Reset Tests

    @Test("Reset clears all filters")
    func resetClearsFilters() {
        var filter = PortFilter()
        filter.searchText = "node"
        filter.minPort = 3000
        filter.maxPort = 5000
        filter.processTypes = [.development]
        filter.showOnlyFavorites = true
        filter.showOnlyWatched = true

        #expect(filter.isActive)

        filter.reset()

        #expect(!filter.isActive)
        #expect(filter.searchText.isEmpty)
        #expect(filter.minPort == nil)
        #expect(filter.maxPort == nil)
        #expect(filter.processTypes == Set(ProcessType.allCases))
        #expect(!filter.showOnlyFavorites)
        #expect(!filter.showOnlyWatched)
    }

    // MARK: - Edge Cases

    @Test("Empty search matches everything")
    func emptySearchMatchesAll() {
        let filter = PortFilter(searchText: "")
        let port = createPort()
        #expect(filter.matches(port, favorites: [], watched: []))
    }

    @Test("Partial matches work")
    func partialMatches() {
        let filter = PortFilter(searchText: "serv")
        let port = createPort(command: "node server.js")
        #expect(filter.matches(port, favorites: [], watched: []))
    }
}
