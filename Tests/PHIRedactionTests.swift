import XCTest
@testable import JarvisVertexAI

final class PHIRedactionTests: XCTestCase {
    var phiRedactor: PHIRedactor!

    override func setUp() {
        super.setUp()
        phiRedactor = PHIRedactor.shared
    }

    // MARK: - Basic PHI Redaction Tests

    func testSSNRedaction() {
        let text = "My SSN is 123-45-6789"
        let redacted = phiRedactor.redactPHI(from: text)

        XCTAssertFalse(redacted.contains("123-45-6789"))
        XCTAssertTrue(redacted.contains("[SSN_REDACTED]"))
    }

    func testPhoneRedaction() {
        let text = "Call me at 555-123-4567"
        let redacted = phiRedactor.redactPHI(from: text)

        XCTAssertFalse(redacted.contains("555-123-4567"))
        XCTAssertTrue(redacted.contains("[PHONE_REDACTED]"))
    }

    func testEmailRedaction() {
        let text = "Email me at john.doe@example.com"
        let redacted = phiRedactor.redactPHI(from: text)

        XCTAssertFalse(redacted.contains("john.doe@example.com"))
        XCTAssertTrue(redacted.contains("[EMAIL_REDACTED]"))
    }

    func testMedicalRecordNumberRedaction() {
        let text = "Patient MRN: ABC123456"
        let redacted = phiRedactor.redactPHI(from: text)

        XCTAssertFalse(redacted.contains("ABC123456"))
        XCTAssertTrue(redacted.contains("[MRN_REDACTED]"))
    }

    // MARK: - Multiple PHI Pattern Tests

    func testMultiplePHIRedaction() {
        let text = "Patient John Doe, SSN: 123-45-6789, Phone: 555-123-4567, Email: john@example.com"
        let redacted = phiRedactor.redactPHI(from: text)

        XCTAssertFalse(redacted.contains("123-45-6789"))
        XCTAssertFalse(redacted.contains("555-123-4567"))
        XCTAssertFalse(redacted.contains("john@example.com"))
        XCTAssertTrue(redacted.contains("[SSN_REDACTED]"))
        XCTAssertTrue(redacted.contains("[PHONE_REDACTED]"))
        XCTAssertTrue(redacted.contains("[EMAIL_REDACTED]"))
        XCTAssertTrue(redacted.contains("[NAME_REDACTED]"))
    }

    // MARK: - Address Redaction Tests

    func testAddressRedaction() {
        let text = "I live at 123 Main Street, Apt 4B"
        let redacted = phiRedactor.redactPHI(from: text)

        XCTAssertTrue(redacted.contains("[ADDRESS_REDACTED]"))
    }

    func testZipCodeRedaction() {
        let text = "ZIP code is 12345-6789"
        let redacted = phiRedactor.redactPHI(from: text)

        XCTAssertTrue(redacted.contains("[ZIP_REDACTED]"))
    }

    // MARK: - Medical Context Tests

    func testMedicalContextDetection() {
        let medicalText = "Patient has diabetes and high blood pressure"
        let nonMedicalText = "I like the number 1234567890"

        let medicalRedacted = phiRedactor.redactPHI(from: medicalText)
        let nonMedicalRedacted = phiRedactor.redactPHI(from: nonMedicalText)

        // Medical context should trigger name redaction
        XCTAssertTrue(medicalRedacted.contains("[NAME_REDACTED]"))

        // Non-medical context should not trigger aggressive redaction
        XCTAssertFalse(nonMedicalRedacted.contains("[NPI_REDACTED]"))
    }

    // MARK: - Validation Tests

    func testRedactionValidation() {
        let text = "Call me at 555-123-4567"
        let redacted = phiRedactor.redactPHI(from: text)

        let report = phiRedactor.validateRedaction(redacted)

        XCTAssertTrue(report.isFullyRedacted)
        XCTAssertTrue(report.redactionMarkersFound.contains("[PHONE_REDACTED]"))
        XCTAssertEqual(report.confidence, 1.0)
    }

    // MARK: - Batch Processing Tests

    func testBatchRedaction() {
        let texts = [
            "My SSN is 123-45-6789",
            "Call 555-123-4567",
            "Email test@example.com"
        ]

        let redacted = phiRedactor.redactPHIBatch(texts)

        XCTAssertEqual(redacted.count, 3)
        XCTAssertTrue(redacted[0].contains("[SSN_REDACTED]"))
        XCTAssertTrue(redacted[1].contains("[PHONE_REDACTED]"))
        XCTAssertTrue(redacted[2].contains("[EMAIL_REDACTED]"))
    }

    // MARK: - Performance Tests

    func testRedactionPerformance() {
        let text = "Patient John Doe, SSN: 123-45-6789, Phone: 555-123-4567, lives at 123 Main St, ZIP 12345"

        measure {
            _ = phiRedactor.redactPHI(from: text)
        }
    }

    // MARK: - Edge Cases

    func testEmptyStringRedaction() {
        let redacted = phiRedactor.redactPHI(from: "")
        XCTAssertEqual(redacted, "")
    }

    func testNoRedactionNeeded() {
        let text = "Hello, how are you today?"
        let redacted = phiRedactor.redactPHI(from: text)
        XCTAssertEqual(redacted, text)
    }

    func testSpecialCharacters() {
        let text = "Phone: (555) 123-4567"
        let redacted = phiRedactor.redactPHI(from: text)
        XCTAssertTrue(redacted.contains("[PHONE_REDACTED]"))
    }
}