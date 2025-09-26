//
//  PersistentLogger.swift
//  JarvisVertexAI
//
//  Comprehensive Thread-Safe File-Based Logging System
//  Privacy-compliant persistent logging with automatic rotation
//

import Foundation

// MARK: - Log Level and Component Enums

enum LogLevel: String, CaseIterable {
    case error = "ERROR"
    case warn = "WARN"
    case info = "INFO"
    case debug = "DEBUG"

    var priority: Int {
        switch self {
        case .error: return 3
        case .warn: return 2
        case .info: return 1
        case .debug: return 0
        }
    }
}

enum LogComponent: String, CaseIterable {
    case auth = "AUTH"
    case system = "SYSTEM"
    case audit = "AUDIT"
    case vertex = "VERTEX"

    var fileName: String {
        return "\(self.rawValue.lowercased()).log"
    }
}

// MARK: - Log Entry Structure

struct LogEntry {
    let timestamp: Date
    let level: LogLevel
    let component: LogComponent
    let message: String
    let threadId: String

    init(level: LogLevel, component: LogComponent, message: String) {
        self.timestamp = Date()
        self.level = level
        self.component = component
        self.message = message
        self.threadId = Thread.isMainThread ? "main" : "bg-\(Thread.current.hash)"
    }

    var formattedString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return "[\(dateFormatter.string(from: timestamp))] [\(level.rawValue)] [\(component.rawValue)] [\(threadId)] \(message)"
    }
}

// MARK: - Persistent Logger

final class PersistentLogger {

    // MARK: - Singleton

    static let shared = PersistentLogger()

    // MARK: - Configuration

    private let maxFileSize: UInt64 = 10 * 1024 * 1024 // 10MB
    private let maxFileCount: Int = 5
    private let logRetentionDays: Int = 7
    private let minLogLevel: LogLevel = .debug

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let logsDirectory: URL
    private let writeQueue = DispatchQueue(label: "com.jarvisvertexai.logging", qos: .utility)
    private var isEnabled = true

    // Thread-safe logging state
    private var logHandles: [LogComponent: FileHandle] = [:]
    private let handlesLock = NSLock()

    // MARK: - Initialization

    private init() {
        // Create logs directory in Documents
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.logsDirectory = documentsPath.appendingPathComponent("JarvisVertexAI/logs")

        setupLogsDirectory()
        cleanupOldLogs()
        setupFileHandles()

        // Log system initialization
        logSystem(.info, "PersistentLogger initialized - logs directory: \(logsDirectory.path)")
    }

    deinit {
        closeAllFileHandles()
    }

    // MARK: - Directory Setup

    private func setupLogsDirectory() {
        do {
            try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create logs directory: \(error)")
        }
    }

    private func setupFileHandles() {
        handlesLock.lock()
        defer { handlesLock.unlock() }

        for component in LogComponent.allCases {
            let fileURL = logsDirectory.appendingPathComponent(component.fileName)

            // Create file if it doesn't exist
            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }

            // Open file handle
            do {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                logHandles[component] = handle
            } catch {
                print("❌ Failed to open log file for \(component.rawValue): \(error)")
            }
        }
    }

    private func closeAllFileHandles() {
        handlesLock.lock()
        defer { handlesLock.unlock() }

        for handle in logHandles.values {
            handle.closeFile()
        }
        logHandles.removeAll()
    }

    // MARK: - Log Cleanup

    private func cleanupOldLogs() {
        writeQueue.async { [weak self] in
            self?.performLogCleanup()
        }
    }

    private func performLogCleanup() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -logRetentionDays, to: Date()) ?? Date()

        do {
            let files = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey])

            for file in files {
                if file.pathExtension == "log" {
                    let attributes = try file.resourceValues(forKeys: [.creationDateKey])
                    if let creationDate = attributes.creationDate, creationDate < cutoffDate {
                        try fileManager.removeItem(at: file)
                        print("🗑️ Removed old log file: \(file.lastPathComponent)")
                    }
                }
            }
        } catch {
            print("⚠️ Failed to cleanup old logs: \(error)")
        }
    }

    // MARK: - Log Rotation

    private func checkAndRotateLog(for component: LogComponent) {
        let fileURL = logsDirectory.appendingPathComponent(component.fileName)

        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? UInt64, fileSize > maxFileSize {
                rotateLogFile(for: component)
            }
        } catch {
            // File might not exist yet, which is fine
        }
    }

    private func rotateLogFile(for component: LogComponent) {
        handlesLock.lock()
        defer { handlesLock.unlock() }

        // Close current handle
        logHandles[component]?.closeFile()

        let baseFileName = component.fileName
        let baseName = String(baseFileName.dropLast(4)) // Remove .log extension

        // Rotate existing files
        for i in (1..<maxFileCount).reversed() {
            let oldFile = logsDirectory.appendingPathComponent("\(baseName).\(i).log")
            let newFile = logsDirectory.appendingPathComponent("\(baseName).\(i+1).log")

            if fileManager.fileExists(atPath: oldFile.path) {
                do {
                    if fileManager.fileExists(atPath: newFile.path) {
                        try fileManager.removeItem(at: newFile)
                    }
                    try fileManager.moveItem(at: oldFile, to: newFile)
                } catch {
                    print("⚠️ Failed to rotate log file \(oldFile.lastPathComponent): \(error)")
                }
            }
        }

        // Move current log to .1
        let currentFile = logsDirectory.appendingPathComponent(baseFileName)
        let rotatedFile = logsDirectory.appendingPathComponent("\(baseName).1.log")

        do {
            if fileManager.fileExists(atPath: rotatedFile.path) {
                try fileManager.removeItem(at: rotatedFile)
            }
            try fileManager.moveItem(at: currentFile, to: rotatedFile)
        } catch {
            print("⚠️ Failed to rotate current log file: \(error)")
        }

        // Create new file and handle
        fileManager.createFile(atPath: currentFile.path, contents: nil)

        do {
            let newHandle = try FileHandle(forWritingTo: currentFile)
            logHandles[component] = newHandle
        } catch {
            print("❌ Failed to create new log handle for \(component.rawValue): \(error)")
        }

        print("🔄 Rotated log file for \(component.rawValue)")
    }

    // MARK: - Core Logging Method

    private func log(_ level: LogLevel, component: LogComponent, message: String) {
        guard isEnabled, level.priority >= minLogLevel.priority else { return }

        // Create log entry
        let entry = LogEntry(level: level, component: component, message: sanitizeMessage(message))

        // Write asynchronously
        writeQueue.async { [weak self] in
            self?.writeLogEntry(entry)
        }

        // Also print to console for immediate debugging (can be disabled in production)
        if level.priority >= LogLevel.warn.priority {
            print("\(entry.formattedString)")
        }
    }

    private func writeLogEntry(_ entry: LogEntry) {
        handlesLock.lock()
        defer { handlesLock.unlock() }

        guard let handle = logHandles[entry.component] else {
            print("❌ No file handle for component \(entry.component.rawValue)")
            return
        }

        let logLine = entry.formattedString + "\n"
        guard let data = logLine.data(using: .utf8) else { return }

        handle.write(data)

        // Check for rotation after writing
        checkAndRotateLog(for: entry.component)
    }

    // MARK: - Privacy-Compliant Message Sanitization

    private func sanitizeMessage(_ message: String) -> String {
        var sanitized = message

        // Remove API keys (ya29.*, AIza*, GOCSPX-*)
        sanitized = sanitized.replacingOccurrences(
            of: "ya29\\.[a-zA-Z0-9_-]+",
            with: "[REDACTED_ACCESS_TOKEN]",
            options: .regularExpression
        )

        sanitized = sanitized.replacingOccurrences(
            of: "AIza[a-zA-Z0-9_-]+",
            with: "[REDACTED_API_KEY]",
            options: .regularExpression
        )

        sanitized = sanitized.replacingOccurrences(
            of: "GOCSPX-[a-zA-Z0-9_-]+",
            with: "[REDACTED_CLIENT_SECRET]",
            options: .regularExpression
        )

        // Remove Bearer tokens
        sanitized = sanitized.replacingOccurrences(
            of: "Bearer [a-zA-Z0-9._-]+",
            with: "Bearer [REDACTED]",
            options: .regularExpression
        )

        // Remove potential PHI patterns (basic email, phone, SSN patterns)
        sanitized = sanitized.replacingOccurrences(
            of: "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b",
            with: "[REDACTED_EMAIL]",
            options: .regularExpression
        )

        sanitized = sanitized.replacingOccurrences(
            of: "\\b\\d{3}[-.]?\\d{3}[-.]?\\d{4}\\b",
            with: "[REDACTED_PHONE]",
            options: .regularExpression
        )

        sanitized = sanitized.replacingOccurrences(
            of: "\\b\\d{3}[-]?\\d{2}[-]?\\d{4}\\b",
            with: "[REDACTED_SSN]",
            options: .regularExpression
        )

        return sanitized
    }

    // MARK: - Public Logging Interface

    func logAuth(_ level: LogLevel, _ message: String) {
        log(level, component: .auth, message: message)
    }

    func logSystem(_ level: LogLevel, _ message: String) {
        log(level, component: .system, message: message)
    }

    func logAudit(_ level: LogLevel, _ message: String) {
        log(level, component: .audit, message: message)
    }

    func logVertex(_ level: LogLevel, _ message: String) {
        log(level, component: .vertex, message: message)
    }

    // MARK: - Log Reading Interface

    func getRecentLogs(component: LogComponent, limit: Int = 100) -> [String] {
        var logs: [String] = []

        let fileURL = logsDirectory.appendingPathComponent(component.fileName)

        do {
            let content = try String(contentsOf: fileURL)
            let lines = content.components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
                .suffix(limit)

            logs = Array(lines)
        } catch {
            logSystem(.warn, "Failed to read logs for \(component.rawValue): \(error)")
        }

        return logs
    }

    func getAllRecentLogs(limit: Int = 50) -> [String: [String]] {
        var allLogs: [String: [String]] = [:]

        for component in LogComponent.allCases {
            allLogs[component.rawValue] = getRecentLogs(component: component, limit: limit)
        }

        return allLogs
    }

    // MARK: - Export Functionality

    func exportLogs() -> URL? {
        let tempDir = fileManager.temporaryDirectory
        let exportURL = tempDir.appendingPathComponent("JarvisVertexAI_Logs_\(Date().timeIntervalSince1970).zip")

        // For now, create a simple text export (can be enhanced to ZIP later)
        var exportContent = "# JarvisVertexAI Log Export\n"
        exportContent += "# Generated: \(Date())\n"
        exportContent += "# Logs Directory: \(logsDirectory.path)\n\n"

        for component in LogComponent.allCases {
            let logs = getRecentLogs(component: component, limit: 1000)
            exportContent += "## \(component.rawValue.uppercased()) LOGS\n"
            exportContent += logs.joined(separator: "\n")
            exportContent += "\n\n"
        }

        do {
            try exportContent.write(to: exportURL, atomically: true, encoding: .utf8)
            logSystem(.info, "Logs exported to: \(exportURL.path)")
            return exportURL
        } catch {
            logSystem(.error, "Failed to export logs: \(error)")
            return nil
        }
    }

    // MARK: - Log Management

    func clearLogs() {
        writeQueue.async { [weak self] in
            self?.performClearLogs()
        }
    }

    private func performClearLogs() {
        handlesLock.lock()
        defer { handlesLock.unlock() }

        // Close all handles
        for handle in logHandles.values {
            handle.closeFile()
        }
        logHandles.removeAll()

        // Remove all log files
        do {
            let files = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)

            for file in files {
                if file.pathExtension == "log" {
                    try fileManager.removeItem(at: file)
                }
            }
        } catch {
            print("⚠️ Failed to clear logs: \(error)")
        }

        // Recreate file handles
        setupFileHandles()

        logSystem(.info, "All logs cleared")
    }

    // MARK: - Configuration

    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        logSystem(.info, "Logging \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - Debug Information

    func getLogStats() -> [String: Any] {
        var stats: [String: Any] = [:]

        stats["logsDirectory"] = logsDirectory.path
        stats["isEnabled"] = isEnabled
        stats["maxFileSize"] = maxFileSize
        stats["maxFileCount"] = maxFileCount
        stats["retentionDays"] = logRetentionDays

        var fileSizes: [String: UInt64] = [:]

        for component in LogComponent.allCases {
            let fileURL = logsDirectory.appendingPathComponent(component.fileName)

            do {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                if let size = attributes[.size] as? UInt64 {
                    fileSizes[component.rawValue] = size
                }
            } catch {
                fileSizes[component.rawValue] = 0
            }
        }

        stats["fileSizes"] = fileSizes

        return stats
    }
}

// MARK: - Convenience Extensions

extension PersistentLogger {

    /// Quick method to log authentication events
    func authEvent(_ message: String, level: LogLevel = .info) {
        logAuth(level, message)
    }

    /// Quick method to log system events
    func systemEvent(_ message: String, level: LogLevel = .info) {
        logSystem(level, message)
    }

    /// Quick method to log audit events
    func auditEvent(_ message: String, level: LogLevel = .info) {
        logAudit(level, message)
    }

    /// Quick method to log vertex AI events
    func vertexEvent(_ message: String, level: LogLevel = .info) {
        logVertex(level, message)
    }
}