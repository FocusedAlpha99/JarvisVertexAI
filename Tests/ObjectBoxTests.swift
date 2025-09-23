import XCTest
import ObjectBox
@testable import JarvisVertexAI

final class ObjectBoxTests: XCTestCase {
    var dbManager: ObjectBoxManager!
    
    override func setUp() {
        super.setUp()
        // Initialize test database
        dbManager = ObjectBoxManager.shared
        dbManager.initialize(testMode: true)
    }
    
    override func tearDown() {
        // Clean up test data
        try? dbManager.deleteAllData()
        super.tearDown()
    }
    
    // MARK: - Session Management Tests
    
    func testCreateSession() throws {
        // Create session
        let sessionId = try dbManager.createSession(
            mode: .nativeAudio,
            metadata: ["test": true]
        )
        
        XCTAssertFalse(sessionId.isEmpty)
        
        // Verify session exists
        let sessions = try dbManager.getRecentSessions(mode: .nativeAudio, limit: 1)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, sessionId)
    }
    
    func testSessionPrivacy() throws {
        // Create session with PHI
        let sessionId = try dbManager.createSession(
            mode: .voiceChatLocal,
            metadata: [
                "contains_phi": true,
                "patient_name": "John Doe"
            ]
        )
        
        // Verify PHI is not exposed
        let sessions = try dbManager.getRecentSessions(mode: .voiceChatLocal, limit: 1)
        guard let session = sessions.first else {
            XCTFail("Session not found")
            return
        }
        
        // Check that sensitive data is encrypted
        XCTAssertNil(session.metadata["patient_name"])
        XCTAssertEqual(session.metadata["contains_phi"] as? Bool, true)
    }
    
    func testAutoCleanup() throws {
        // Create old session (simulated)
        let oldSessionId = try dbManager.createSession(
            mode: .textMultimodal,
            metadata: ["created_at": Date().addingTimeInterval(-31 * 24 * 60 * 60)] // 31 days ago
        )
        
        // Create recent session
        let recentSessionId = try dbManager.createSession(
            mode: .textMultimodal,
            metadata: [:]
        )
        
        // Run cleanup
        try dbManager.performMaintenance()
        
        // Verify old session is deleted
        let sessions = try dbManager.getRecentSessions(mode: .textMultimodal, limit: 10)
        XCTAssertFalse(sessions.contains { $0.id == oldSessionId })
        XCTAssertTrue(sessions.contains { $0.id == recentSessionId })
    }
    
    // MARK: - Transcript Tests
    
    func testTranscriptStorage() throws {
        let sessionId = try dbManager.createSession(mode: .nativeAudio, metadata: [:])
        
        // Add transcripts
        try dbManager.addTranscript(
            sessionId: sessionId,
            speaker: "user",
            text: "Hello, how are you?",
            metadata: [:]
        )
        
        try dbManager.addTranscript(
            sessionId: sessionId,
            speaker: "assistant",
            text: "I'm doing well, thank you!",
            metadata: [:]
        )
        
        // Retrieve transcripts
        let transcripts = try dbManager.getTranscripts(sessionId: sessionId)
        XCTAssertEqual(transcripts.count, 2)
        XCTAssertEqual(transcripts[0].speaker, "user")
        XCTAssertEqual(transcripts[1].speaker, "assistant")
    }
    
    func testPHIRedactionInTranscripts() throws {
        let sessionId = try dbManager.createSession(mode: .voiceChatLocal, metadata: [:])
        let phiRedactor = PHIRedactor()
        
        // Text with PHI
        let textWithPHI = "My SSN is 123-45-6789 and phone is 555-123-4567"
        let redactedText = phiRedactor.redactPHI(from: textWithPHI)
        
        // Store redacted transcript
        try dbManager.addTranscript(
            sessionId: sessionId,
            speaker: "user",
            text: redactedText,
            metadata: ["was_redacted": true]
        )
        
        // Verify PHI is not stored
        let transcripts = try dbManager.getTranscripts(sessionId: sessionId)
        XCTAssertFalse(transcripts[0].text.contains("123-45-6789"))
        XCTAssertFalse(transcripts[0].text.contains("555-123-4567"))
        XCTAssertTrue(transcripts[0].text.contains("[SSN_REDACTED]"))
        XCTAssertTrue(transcripts[0].text.contains("[PHONE_REDACTED]"))
    }
    
    // MARK: - Memory Vector Tests
    
    func testVectorStorage() throws {
        let sessionId = try dbManager.createSession(mode: .textMultimodal, metadata: [:])
        
        // Create test embedding
        let embedding = (0..<768).map { _ in Float.random(in: -1...1) }
        
        // Store memory
        try dbManager.storeMemory(
            sessionId: sessionId,
            text: "Important context about the user",
            embedding: embedding,
            metadata: ["importance": 0.9]
        )
        
        // Search for similar memories
        let queryEmbedding = embedding.map { $0 + Float.random(in: -0.1...0.1) } // Slightly modified
        let memories = try dbManager.searchMemories(
            embedding: queryEmbedding,
            limit: 5
        )
        
        XCTAssertGreaterThan(memories.count, 0)
        XCTAssertEqual(memories[0].text, "Important context about the user")
    }
    
    func testVectorSimilaritySearch() throws {
        let sessionId = try dbManager.createSession(mode: .nativeAudio, metadata: [:])
        
        // Store multiple memories with different embeddings
        let baseEmbedding = (0..<768).map { _ in Float.random(in: -1...1) }
        
        // Very similar
        var similar1 = baseEmbedding
        similar1[0] += 0.01
        try dbManager.storeMemory(
            sessionId: sessionId,
            text: "Very similar memory",
            embedding: similar1,
            metadata: [:]
        )
        
        // Somewhat similar
        var similar2 = baseEmbedding
        for i in 0..<10 {
            similar2[i] += Float.random(in: -0.5...0.5)
        }
        try dbManager.storeMemory(
            sessionId: sessionId,
            text: "Somewhat similar memory",
            embedding: similar2,
            metadata: [:]
        )
        
        // Very different
        let different = (0..<768).map { _ in Float.random(in: -1...1) }
        try dbManager.storeMemory(
            sessionId: sessionId,
            text: "Very different memory",
            embedding: different,
            metadata: [:]
        )
        
        // Search
        let results = try dbManager.searchMemories(
            embedding: baseEmbedding,
            limit: 3
        )
        
        // Verify ordering by similarity
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].text, "Very similar memory")
        XCTAssertEqual(results[1].text, "Somewhat similar memory")
        XCTAssertEqual(results[2].text, "Very different memory")
    }
    
    // MARK: - Privacy & Encryption Tests
    
    func testDataEncryption() throws {
        // Verify database is encrypted
        let dbPath = dbManager.getDatabasePath()
        XCTAssertNotNil(dbPath)
        
        // Try to read raw database file
        if let data = try? Data(contentsOf: URL(fileURLWithPath: dbPath)) {
            // Convert to string to check for plaintext
            let rawString = String(data: data, encoding: .utf8) ?? ""
            
            // Store test data
            let sessionId = try dbManager.createSession(
                mode: .nativeAudio,
                metadata: ["secret": "ThisShouldBeEncrypted"]
            )
            
            try dbManager.addTranscript(
                sessionId: sessionId,
                speaker: "user",
                text: "Sensitive information here",
                metadata: [:]
            )
            
            // Read raw file again
            if let newData = try? Data(contentsOf: URL(fileURLWithPath: dbPath)) {
                let newRawString = String(data: newData, encoding: .utf8) ?? ""
                
                // Verify sensitive data is not in plaintext
                XCTAssertFalse(newRawString.contains("ThisShouldBeEncrypted"))
                XCTAssertFalse(newRawString.contains("Sensitive information here"))
            }
        }
    }
    
    func testNoCloudSync() throws {
        // Verify cloud sync is disabled
        let config = dbManager.getConfiguration()
        XCTAssertFalse(config["enableSync"] as? Bool ?? true)
        XCTAssertNil(config["syncServerUrl"])
    }
    
    // MARK: - Data Export Tests
    
    func testDataExport() async throws {
        // Create test data
        let sessionId = try dbManager.createSession(mode: .voiceChatLocal, metadata: [:])
        
        try dbManager.addTranscript(
            sessionId: sessionId,
            speaker: "user",
            text: "Test export",
            metadata: [:]
        )
        
        // Export as JSON
        let jsonData = await dbManager.exportAllData(
            format: "JSON",
            includeMetadata: true
        )
        
        XCTAssertNotNil(jsonData)
        
        // Verify JSON structure
        if let json = try? JSONSerialization.jsonObject(with: jsonData!, options: []) as? [String: Any] {
            XCTAssertNotNil(json["sessions"])
            XCTAssertNotNil(json["transcripts"])
            XCTAssertNotNil(json["exportDate"])
            XCTAssertEqual(json["encrypted"] as? Bool, true)
        }
    }
    
    func testCompleteDataDeletion() async throws {
        // Create data
        let sessionId = try dbManager.createSession(mode: .textMultimodal, metadata: [:])
        try dbManager.addTranscript(
            sessionId: sessionId,
            speaker: "user",
            text: "To be deleted",
            metadata: [:]
        )
        
        // Delete all data
        try await dbManager.deleteAllData()
        
        // Verify deletion
        let sessions = try dbManager.getRecentSessions(mode: .textMultimodal, limit: 10)
        XCTAssertEqual(sessions.count, 0)
    }
    
    // MARK: - Performance Tests
    
    func testLargeDatasetPerformance() throws {
        measure {
            do {
                let sessionId = try dbManager.createSession(mode: .nativeAudio, metadata: [:])
                
                // Add 1000 transcripts
                for i in 0..<1000 {
                    try dbManager.addTranscript(
                        sessionId: sessionId,
                        speaker: i % 2 == 0 ? "user" : "assistant",
                        text: "Message \(i)",
                        metadata: [:]
                    )
                }
                
                // Retrieve all
                let transcripts = try dbManager.getTranscripts(sessionId: sessionId)
                XCTAssertEqual(transcripts.count, 1000)
            } catch {
                XCTFail("Performance test failed: \(error)")
            }
        }
    }
    
    func testVectorSearchPerformance() throws {
        let sessionId = try dbManager.createSession(mode: .nativeAudio, metadata: [:])
        
        // Store 100 vectors
        for i in 0..<100 {
            let embedding = (0..<768).map { _ in Float.random(in: -1...1) }
            try dbManager.storeMemory(
                sessionId: sessionId,
                text: "Memory \(i)",
                embedding: embedding,
                metadata: [:]
            )
        }
        
        // Measure search performance
        let queryEmbedding = (0..<768).map { _ in Float.random(in: -1...1) }
        
        measure {
            do {
                let results = try dbManager.searchMemories(
                    embedding: queryEmbedding,
                    limit: 10
                )
                XCTAssertEqual(results.count, 10)
            } catch {
                XCTFail("Vector search failed: \(error)")
            }
        }
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentAccess() async throws {
        let sessionId = try dbManager.createSession(mode: .voiceChatLocal, metadata: [:])
        
        // Concurrent writes
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try? self.dbManager.addTranscript(
                        sessionId: sessionId,
                        speaker: "user",
                        text: "Concurrent message \(i)",
                        metadata: [:]
                    )
                }
            }
        }
        
        // Verify all writes succeeded
        let transcripts = try dbManager.getTranscripts(sessionId: sessionId)
        XCTAssertEqual(transcripts.count, 10)
    }
    
    // MARK: - Storage Info Tests
    
    func testStorageInfo() async throws {
        // Create test data
        let sessionId = try dbManager.createSession(mode: .nativeAudio, metadata: [:])
        
        for i in 0..<10 {
            try dbManager.addTranscript(
                sessionId: sessionId,
                speaker: "user",
                text: "Message \(i)",
                metadata: [:]
            )
        }
        
        // Get storage info
        let info = try await dbManager.getStorageInfo()
        
        XCTAssertGreaterThan(info.totalSize, 0)
        XCTAssertEqual(info.sessionCount, 1)
        XCTAssertEqual(info.transcriptCount, 10)
        XCTAssertNotNil(info.oldestData)
    }
}