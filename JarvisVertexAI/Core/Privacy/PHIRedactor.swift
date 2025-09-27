//
//  PHIRedactor.swift
//  JarvisVertexAI
//
//  PHI/PII Detection and Redaction Engine
//  HIPAA & GDPR Compliant Pattern Matching
//

import Foundation
import NaturalLanguage

final class PHIRedactor {

    // MARK: - Properties

    static let shared = PHIRedactor()

    private let redactionQueue = DispatchQueue(label: "com.jarvisvertexai.phiredactor", qos: .userInitiated)

    // Pattern configurations
    private let patterns: [PHIPattern] = [
        // Social Security Numbers
        PHIPattern(name: "SSN",
                  regex: #"\b(?!000|666|9\d{2})\d{3}[-\s]?(?!00)\d{2}[-\s]?(?!0000)\d{4}\b"#,
                  replacement: "[SSN_REDACTED]"),

        // Phone Numbers (US & International)
        PHIPattern(name: "PHONE",
                  regex: #"\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"#,
                  replacement: "[PHONE_REDACTED]"),

        // Email Addresses
        PHIPattern(name: "EMAIL",
                  regex: #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b"#,
                  replacement: "[EMAIL_REDACTED]"),

        // Medical Record Numbers
        PHIPattern(name: "MRN",
                  regex: #"\b(?:MRN|mrn|Medical Record|Patient ID)[\s:#]*([A-Z0-9]{6,12})\b"#,
                  replacement: "[MRN_REDACTED]"),

        // Credit Card Numbers
        PHIPattern(name: "CREDIT_CARD",
                  regex: #"\b(?:\d{4}[-\s]?){3}\d{4}\b"#,
                  replacement: "[CC_REDACTED]"),

        // Date of Birth (various formats)
        PHIPattern(name: "DOB",
                  regex: #"\b(?:DOB|dob|Date of Birth|Birthdate)[\s:]*(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\b"#,
                  replacement: "[DOB_REDACTED]"),

        // Driver's License
        PHIPattern(name: "DL",
                  regex: #"\b(?:DL|dl|Driver'?s? License)[\s:#]*([A-Z0-9]{6,15})\b"#,
                  replacement: "[DL_REDACTED]"),

        // Passport Numbers
        PHIPattern(name: "PASSPORT",
                  regex: #"\b(?:Passport|passport)[\s:#]*([A-Z0-9]{6,9})\b"#,
                  replacement: "[PASSPORT_REDACTED]"),

        // IP Addresses
        PHIPattern(name: "IP_ADDRESS",
                  regex: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#,
                  replacement: "[IP_REDACTED]"),

        // Account Numbers
        PHIPattern(name: "ACCOUNT",
                  regex: #"\b(?:Account|Acct)[\s:#]*(\d{6,12})\b"#,
                  replacement: "[ACCOUNT_REDACTED]"),

        // Insurance IDs
        PHIPattern(name: "INSURANCE",
                  regex: #"\b(?:Policy|Member|Insurance)[\s:#]*([A-Z0-9]{6,15})\b"#,
                  replacement: "[INSURANCE_ID_REDACTED]"),

        // DEA Numbers
        PHIPattern(name: "DEA",
                  regex: #"\b[A-Z]{2}\d{7}\b"#,
                  replacement: "[DEA_REDACTED]"),

        // NPI Numbers
        PHIPattern(name: "NPI",
                  regex: #"\b\d{10}\b"#,
                  replacement: "[NPI_REDACTED]",
                  contextRequired: true)
    ]

    // Medical terms to detect for context
    private let medicalTerms = Set([
        "diagnosis", "treatment", "medication", "prescription", "symptom",
        "patient", "doctor", "physician", "nurse", "hospital", "clinic",
        "surgery", "procedure", "therapy", "disease", "condition",
        "allergy", "vaccine", "immunization", "lab", "test", "result",
        "blood", "pressure", "heart", "rate", "temperature", "weight",
        "mg", "ml", "dose", "tablet", "injection", "infusion"
    ])

    // Address components
    private let addressComponents = [
        "street", "st", "avenue", "ave", "road", "rd", "boulevard", "blvd",
        "lane", "ln", "drive", "dr", "court", "ct", "place", "pl",
        "suite", "ste", "apartment", "apt", "unit"
    ]

    // MARK: - Initialization

    private init() {}

    // MARK: - Main Redaction Function

    func redactPHI(from text: String) -> String {
        var redactedText = text

        // Apply pattern-based redaction
        for pattern in patterns {
            if pattern.contextRequired {
                // Only apply if medical context detected
                if containsMedicalContext(text) {
                    redactedText = applyPattern(pattern, to: redactedText)
                }
            } else {
                redactedText = applyPattern(pattern, to: redactedText)
            }
        }

        // Redact addresses
        redactedText = redactAddresses(from: redactedText)

        // Redact names (using NLP)
        redactedText = redactNames(from: redactedText)

        // Redact dates (aggressive for medical context)
        if containsMedicalContext(text) {
            redactedText = redactDates(from: redactedText)
        }

        // Log redaction activity
        logRedactionActivity(original: text, redacted: redactedText)

        return redactedText
    }

    // MARK: - Pattern Application

    private func applyPattern(_ pattern: PHIPattern, to text: String) -> String {
        do {
            let regex = try NSRegularExpression(pattern: pattern.regex,
                                              options: [.caseInsensitive])
            let range = NSRange(text.startIndex..., in: text)

            return regex.stringByReplacingMatches(in: text,
                                                 options: [],
                                                 range: range,
                                                 withTemplate: pattern.replacement)
        } catch {
            print("⚠️ Regex error for \(pattern.name): \(error)")
            return text
        }
    }

    // MARK: - Address Redaction

    private func redactAddresses(from text: String) -> String {
        var redactedText = text

        // Pattern for street addresses
        let addressPattern = #"(\d{1,5}\s+[\w\s]{1,30}\s+(?:"# +
            addressComponents.joined(separator: "|") +
            #")\.?)(?:\s+(?:apt|apartment|suite|ste|unit|#)\s*[\w\d]+)?"#

        do {
            let regex = try NSRegularExpression(pattern: addressPattern,
                                              options: [.caseInsensitive])
            let range = NSRange(text.startIndex..., in: text)

            redactedText = regex.stringByReplacingMatches(in: redactedText,
                                                         options: [],
                                                         range: range,
                                                         withTemplate: "[ADDRESS_REDACTED]")
        } catch {
            print("⚠️ Address regex error: \(error)")
        }

        // Redact ZIP codes
        let zipPattern = #"\b\d{5}(?:-\d{4})?\b"#
        if let zipRegex = try? NSRegularExpression(pattern: zipPattern) {
            let range = NSRange(text.startIndex..., in: redactedText)
            redactedText = zipRegex.stringByReplacingMatches(in: redactedText,
                                                            options: [],
                                                            range: range,
                                                            withTemplate: "[ZIP_REDACTED]")
        }

        return redactedText
    }

    // MARK: - Name Redaction

    private func redactNames(from text: String) -> String {
        var redactedText = text

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var namesToRedact: [(String, NSRange)] = []

        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                            unit: .word,
                            scheme: .nameType) { tag, range in
            if let tag = tag,
               tag == .personalName || tag == .placeName || tag == .organizationName {
                let name = String(text[range])
                if name.count > 2 { // Avoid single letters
                    namesToRedact.append((name, NSRange(range, in: text)))
                }
            }
            return true
        }

        // Sort by range location (reverse) to maintain string indices
        namesToRedact.sort { $0.1.location > $1.1.location }

        // Apply redactions
        for (_, range) in namesToRedact {
            if let swiftRange = Range(range, in: redactedText) {
                let replacement = "[NAME_REDACTED]"
                redactedText.replaceSubrange(swiftRange, with: replacement)
            }
        }

        return redactedText
    }

    // MARK: - Date Redaction

    private func redactDates(from text: String) -> String {
        var redactedText = text

        // Various date patterns
        let datePatterns = [
            #"\b\d{1,2}[-/]\d{1,2}[-/]\d{2,4}\b"#, // MM/DD/YYYY or MM-DD-YYYY
            #"\b\d{2,4}[-/]\d{1,2}[-/]\d{1,2}\b"#, // YYYY/MM/DD or YYYY-MM-DD
            #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{2,4}\b"#, // Month DD, YYYY
            #"\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{2,4}\b"# // DD Month YYYY
        ]

        for pattern in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: redactedText)
                redactedText = regex.stringByReplacingMatches(in: redactedText,
                                                             options: [],
                                                             range: range,
                                                             withTemplate: "[DATE_REDACTED]")
            }
        }

        return redactedText
    }

    // MARK: - Context Detection

    private func containsMedicalContext(_ text: String) -> Bool {
        let lowercasedText = text.lowercased()
        for term in medicalTerms {
            if lowercasedText.contains(term) {
                return true
            }
        }
        return false
    }

    // MARK: - Batch Processing

    func redactPHIBatch(_ texts: [String]) -> [String] {
        var results: [String] = []

        redactionQueue.sync {
            results = texts.map { redactPHI(from: $0) }
        }

        return results
    }

    // MARK: - Validation

    func validateRedaction(_ text: String) -> RedactionReport {
        var report = RedactionReport()

        // Check for remaining patterns
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern.regex,
                                                   options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: range)

                if !matches.isEmpty {
                    report.unreductedPatterns.append(pattern.name)
                    report.isFullyRedacted = false
                }
            }
        }

        // Check for redaction markers
        let redactionMarkers = ["_REDACTED]", "[REDACTED]", "[NAME_", "[ADDRESS_", "[DATE_"]
        for marker in redactionMarkers {
            if text.contains(marker) {
                report.redactionMarkersFound.append(marker)
            }
        }

        report.confidence = report.isFullyRedacted ? 1.0 : 0.7

        return report
    }

    // MARK: - Logging

    private func logRedactionActivity(original: String, redacted: String) {
        // Count redactions
        let redactionCount = redacted.components(separatedBy: "_REDACTED]").count - 1

        if redactionCount > 0 {
            print("🔒 PHI Redaction: \(redactionCount) items redacted")

            // Log to audit system
            SimpleDataManager.shared.logAudit(
                sessionId: "system",
                action: "PHI_REDACTION",
                details: "PHI redaction performed",
                metadata: [
                    "redactionCount": "\(redactionCount)",
                    "originalLength": "\(original.count)",
                    "redactedLength": "\(redacted.count)"
                ]
            )
        }
    }
}

// MARK: - Supporting Types

private struct PHIPattern {
    let name: String
    let regex: String
    let replacement: String
    let contextRequired: Bool

    init(name: String, regex: String, replacement: String, contextRequired: Bool = false) {
        self.name = name
        self.regex = regex
        self.replacement = replacement
        self.contextRequired = contextRequired
    }
}

struct RedactionReport {
    var isFullyRedacted: Bool = true
    var unreductedPatterns: [String] = []
    var redactionMarkersFound: [String] = []
    var confidence: Double = 0.0
}

// MARK: - Extensions

extension PHIRedactor {

    // Convenience method for streaming redaction
    func redactStream(_ text: String, completion: @escaping (String) -> Void) {
        redactionQueue.async { [weak self] in
            guard let self = self else { return }
            let redacted = self.redactPHI(from: text)
            DispatchQueue.main.async {
                completion(redacted)
            }
        }
    }

    // Test function for validation
    func testRedaction() {
        let testCases = [
            "My SSN is 123-45-6789",
            "Call me at 555-123-4567",
            "Email: john.doe@example.com",
            "Patient MRN: ABC123456",
            "DOB: 01/15/1980",
            "Address: 123 Main Street, Apt 4B",
            "Credit card: 1234-5678-9012-3456",
            "The patient John Smith has diabetes"
        ]

        print("\n🧪 PHI Redaction Test Results:")
        for test in testCases {
            let redacted = redactPHI(from: test)
            print("Original: \(test)")
            print("Redacted: \(redacted)")
            print("---")
        }
    }
}