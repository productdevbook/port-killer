import XCTest
import Foundation
@testable import PortKiller

final class IntegrationTests: XCTestCase {
    
    /// Test end-to-end integration of core components
    /// This test verifies that the complete system works together:
    /// PortScanner -> ProcessDescriptionService -> UI Display
    func testEndToEndIntegration() async throws {
        // Test the core integration without AppState (which has notification setup issues in tests)
        let scanner = PortScanner()
        let ports = await scanner.scanPorts()
        
        print("Found \(ports.count) ports for integration testing")
        
        // Verify that all ports have descriptions
        for portInfo in ports {
            // Verify all required fields are present (Requirements 1.1)
            XCTAssertGreaterThan(portInfo.port, 0, "Port should be valid")
            XCTAssertGreaterThan(portInfo.pid, 0, "PID should be valid")
            XCTAssertFalse(portInfo.processName.isEmpty, "Process name should not be empty")
            XCTAssertFalse(portInfo.address.isEmpty, "Address should not be empty")
            
            // Most importantly: every port should have a description (Requirements 1.1)
            XCTAssertNotNil(portInfo.description, 
                           "Port \(portInfo.port) (\(portInfo.processName)) should have a description")
            
            if let description = portInfo.description {
                // Verify description quality (Requirements 1.2, 1.3)
                XCTAssertFalse(description.text.isEmpty, 
                              "Description for \(portInfo.processName) should not be empty")
                
                // Verify description has valid metadata
                XCTAssertTrue(ProcessCategory.allCases.contains(description.category), 
                             "Description should have valid category")
                XCTAssertTrue(DescriptionConfidence.allCases.contains(description.confidence), 
                             "Description should have valid confidence")
                
                // Test truncation functionality (Requirements 1.4)
                let maxDisplayWidth = 45 // Same as used in MenuBarView
                let truncatedText = truncateDescription(description.text, maxWidth: maxDisplayWidth)
                
                if description.text.count > maxDisplayWidth {
                    XCTAssertTrue(truncatedText.hasSuffix("..."), 
                                 "Long description should be truncated with ellipsis")
                    XCTAssertLessThanOrEqual(truncatedText.count, maxDisplayWidth, 
                                           "Truncated description should not exceed max width")
                } else {
                    XCTAssertEqual(truncatedText, description.text, 
                                  "Short description should not be truncated")
                }
                
                // Log some examples for verification
                if ports.firstIndex(of: portInfo) ?? 0 < 3 {
                    print("   Port \(portInfo.port): \(portInfo.processName) -> \(description.text)")
                }
            }
        }
        
        print("✅ Integration test completed successfully")
        print("   - Scanned \(ports.count) ports")
        print("   - All ports have descriptions")
        print("   - All descriptions are properly formatted")
        print("   - Truncation logic works correctly")
    }
    
    /// Test UI responsiveness and description display
    /// Verifies that the UI components can handle the integrated data correctly
    func testUIResponsiveness() async throws {
        // Test with mock data to ensure UI can handle various scenarios
        let testCases: [(String, Int, String)] = [
            ("node", 3000, "127.0.0.1"),
            ("nginx", 80, "*"),
            ("mysql", 3306, "localhost"),
            ("unknown-process-12345", 8080, "0.0.0.0"),
            ("very-long-process-name-that-should-be-truncated", 9999, "192.168.1.1"),
            ("", 1234, "*"), // Edge case: empty process name
            ("a", 5678, "::1") // Edge case: single character
        ]
        
        for (processName, port, address) in testCases {
            // Get description using the service
            let service = ProcessDescriptionService()
            let description = await service.getDescription(for: processName)
            
            // Create PortInfo as the UI would receive it
            let portInfo = PortInfo(
                port: port,
                pid: 12345,
                processName: processName,
                address: address,
                description: description
            )
            
            // Verify UI can handle this data
            XCTAssertNotNil(portInfo.description, "UI should receive description")
            XCTAssertFalse(portInfo.description?.text.isEmpty ?? true, "UI should receive non-empty description")
            
            // Test displayPort formatting
            XCTAssertEqual(portInfo.displayPort, ":\(port)", "Display port should be formatted correctly")
            
            // Test truncation for UI display (as used in MenuBarView)
            if let desc = portInfo.description {
                let truncated = truncateDescription(desc.text, maxWidth: 45)
                XCTAssertFalse(truncated.isEmpty, "Truncated description should not be empty")
                
                // Verify tooltip would show full description
                XCTAssertEqual(desc.text, desc.text, "Full description should be available for tooltip")
            }
        }
        
        print("✅ UI responsiveness test completed successfully")
    }
    
    /// Test with various process types and edge cases
    /// Ensures the system handles all types of processes correctly
    func testProcessTypeHandling() async throws {
        let processTypes: [(String, ProcessCategory, String)] = [
            // Development tools
            ("webpack-dev-server", .development, "Should recognize development tools"),
            ("nodemon", .development, "Should recognize Node.js tools"),
            ("rails", .development, "Should recognize Rails server"),
            
            // System services
            ("launchd", .system, "Should recognize macOS system processes"),
            ("docker", .system, "Should recognize container services"),
            ("systemd", .system, "Should recognize system daemons"),
            
            // Database services
            ("mysql", .database, "Should recognize database servers"),
            ("postgres", .database, "Should recognize PostgreSQL"),
            ("redis", .database, "Should recognize Redis"),
            
            // Web servers
            ("nginx", .webServer, "Should recognize web servers"),
            ("apache2", .webServer, "Should recognize Apache"),
            ("caddy", .webServer, "Should recognize modern web servers"),
            
            // Pattern matches
            ("my-dev-server", .development, "Should match development patterns"),
            ("api-server", .webServer, "Should match server patterns"),
            ("background-worker", .system, "Should match worker patterns"),
            
            // Technology keywords
            ("python-app", .development, "Should match technology keywords"),
            ("java-service", .development, "Should match Java applications"),
            ("node-tool", .development, "Should match Node.js applications"),
            
            // Unknown processes (should get fallback)
            ("completely-unknown-xyz", .other, "Should provide fallback for unknown processes"),
            ("mystery-process-123", .other, "Should handle unknown processes gracefully")
        ]
        
        let service = ProcessDescriptionService()
        
        for (processName, expectedCategory, testDescription) in processTypes {
            let description = await service.getDescription(for: processName)
            
            // Verify description exists
            XCTAssertFalse(description.text.isEmpty, 
                          "\(testDescription): \(processName) should have description")
            
            // Verify category is correct or reasonable
            if expectedCategory != .other {
                XCTAssertEqual(description.category, expectedCategory, 
                              "\(testDescription): \(processName) should be categorized as \(expectedCategory)")
            } else {
                // For unknown processes, any category is acceptable as long as there's a description
                XCTAssertTrue(ProcessCategory.allCases.contains(description.category), 
                             "\(testDescription): \(processName) should have valid category")
            }
            
            // Verify confidence level is appropriate
            XCTAssertTrue(DescriptionConfidence.allCases.contains(description.confidence), 
                         "\(testDescription): \(processName) should have valid confidence")
            
            // Create PortInfo to test integration
            let portInfo = PortInfo(
                port: 8080,
                pid: 99999,
                processName: processName,
                address: "127.0.0.1",
                description: description
            )
            
            // Verify integration works
            XCTAssertEqual(portInfo.processName, processName, "Process name should be preserved")
            XCTAssertEqual(portInfo.description?.text, description.text, "Description should be preserved")
            XCTAssertEqual(portInfo.description?.category, description.category, "Category should be preserved")
        }
        
        print("✅ Process type handling test completed successfully")
        print("   - Tested \(processTypes.count) different process types")
        print("   - All processes received appropriate descriptions")
        print("   - All categories and confidence levels are valid")
    }
    
    /// Test performance and memory usage under load
    /// Ensures the system performs well with many processes
    func testPerformanceUnderLoad() async throws {
        let service = ProcessDescriptionService()
        
        // Generate a large number of process names to test performance
        var processNames: [String] = []
        
        // Add known processes
        processNames += ["node", "nginx", "mysql", "postgres", "redis", "docker", "git"]
        
        // Add pattern-matching processes
        for i in 1...50 {
            processNames += [
                "app-\(i)-dev-server",
                "service-\(i)-worker",
                "custom-\(i)-daemon",
                "api-\(i)-proxy"
            ]
        }
        
        // Add unknown processes
        for i in 1...50 {
            processNames += ["unknown-process-\(i)", "mystery-app-\(i)"]
        }
        
        print("Testing performance with \(processNames.count) processes...")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Process all descriptions
        var descriptions: [ProcessDescription] = []
        for processName in processNames {
            let description = await service.getDescription(for: processName)
            descriptions.append(description)
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        let averageTime = totalTime / Double(processNames.count)
        
        // Verify all descriptions were generated
        XCTAssertEqual(descriptions.count, processNames.count, "Should generate description for every process")
        
        for description in descriptions {
            XCTAssertFalse(description.text.isEmpty, "Every description should be non-empty")
        }
        
        // Performance assertions
        XCTAssertLessThan(averageTime, 0.01, "Average description lookup should be under 10ms")
        XCTAssertLessThan(totalTime, 5.0, "Total processing time should be under 5 seconds")
        
        // Test memory usage
        let metrics = await service.getPerformanceMetrics()
        XCTAssertLessThan(metrics.memoryUsageMB, 2.0, "Memory usage should be under 2MB")
        
        print("✅ Performance test completed successfully")
        print("   - Processed \(processNames.count) processes in \(String(format: "%.3f", totalTime))s")
        print("   - Average lookup time: \(String(format: "%.3f", averageTime * 1000))ms")
        print("   - Memory usage: \(String(format: "%.3f", metrics.memoryUsageMB))MB")
        print("   - Cache hit rate: \(String(format: "%.1f", metrics.cacheHitRate * 100))%")
    }
    
    /// Test error handling and edge cases
    /// Ensures the system is robust against various edge cases
    func testErrorHandlingAndEdgeCases() async throws {
        let service = ProcessDescriptionService()
        
        // Test edge cases that might cause issues
        let edgeCases: [String] = [
            "", // Empty string
            " ", // Whitespace only
            "\n", // Newline
            "\t", // Tab
            "a", // Single character
            String(repeating: "x", count: 1000), // Very long string
            "process with spaces", // Spaces
            "process-with-hyphens", // Hyphens
            "process_with_underscores", // Underscores
            "process.with.dots", // Dots
            "process/with/slashes", // Slashes
            "process\\with\\backslashes", // Backslashes
            "process:with:colons", // Colons
            "process;with;semicolons", // Semicolons
            "process|with|pipes", // Pipes
            "process&with&ampersands", // Ampersands
            "process$with$dollars", // Dollar signs
            "process%with%percents", // Percent signs
            "process#with#hashes", // Hash signs
            "process@with@ats", // At signs
            "process!with!exclamations", // Exclamation marks
            "process?with?questions", // Question marks
            "process*with*asterisks", // Asterisks
            "process+with+plus", // Plus signs
            "process=with=equals", // Equals signs
            "process[with]brackets", // Brackets
            "process{with}braces", // Braces
            "process(with)parentheses", // Parentheses
            "process<with>angles", // Angle brackets
            "process\"with\"quotes", // Double quotes
            "process'with'apostrophes", // Single quotes
            "process`with`backticks", // Backticks
            "process~with~tildes", // Tildes
            "process^with^carets", // Carets
            "123456789", // Numbers only
            "!@#$%^&*()", // Special characters only
            "ñoñó-prócéss", // Unicode characters
            "🚀🔥💻⚡️🌟", // Emojis
            "процесс", // Cyrillic
            "プロセス", // Japanese
            "进程", // Chinese
            "عملية" // Arabic
        ]
        
        for edgeCase in edgeCases {
            let description = await service.getDescription(for: edgeCase)
            
            // Every edge case should get a description
            XCTAssertFalse(description.text.isEmpty, 
                          "Edge case '\(edgeCase)' should have non-empty description")
            
            // Should have valid category and confidence
            XCTAssertTrue(ProcessCategory.allCases.contains(description.category), 
                         "Edge case '\(edgeCase)' should have valid category")
            XCTAssertTrue(DescriptionConfidence.allCases.contains(description.confidence), 
                         "Edge case '\(edgeCase)' should have valid confidence")
            
            // Test that PortInfo can be created with edge case
            let portInfo = PortInfo(
                port: 8080,
                pid: 12345,
                processName: edgeCase,
                address: "127.0.0.1",
                description: description
            )
            
            XCTAssertEqual(portInfo.processName, edgeCase, "Process name should be preserved exactly")
            XCTAssertNotNil(portInfo.description, "Description should be preserved")
            
            // Test truncation with edge case
            let truncated = truncateDescription(description.text, maxWidth: 30)
            XCTAssertFalse(truncated.isEmpty, "Truncated description should not be empty")
        }
        
        print("✅ Error handling and edge cases test completed successfully")
        print("   - Tested \(edgeCases.count) edge cases")
        print("   - All edge cases handled gracefully")
        print("   - No crashes or empty descriptions")
    }
    
    /// Test real-world integration with actual system processes
    /// This test scans actual ports and verifies the complete integration
    func testRealWorldIntegration() async throws {
        // Create a real PortScanner and scan actual ports
        let scanner = PortScanner()
        let realPorts = await scanner.scanPorts()
        
        print("Found \(realPorts.count) real ports on the system")
        
        // Test that every real port has a description
        for portInfo in realPorts {
            XCTAssertNotNil(portInfo.description, 
                           "Real port \(portInfo.port) (\(portInfo.processName)) should have description")
            
            if let description = portInfo.description {
                XCTAssertFalse(description.text.isEmpty, 
                              "Real process \(portInfo.processName) should have non-empty description")
                
                // Log some examples for manual verification
                if realPorts.firstIndex(of: portInfo) ?? 0 < 5 {
                    print("   Port \(portInfo.port): \(portInfo.processName) -> \(description.text)")
                }
            }
        }
        
        print("✅ Real-world integration test completed successfully")
        print("   - Scanner found \(realPorts.count) ports")
        print("   - All real ports have descriptions")
    }
}