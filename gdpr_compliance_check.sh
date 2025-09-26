#!/bin/bash
# JarvisVertexAI GDPR Compliance Validation
# Tests GDPR requirements: consent, data portability, right to erasure, privacy by design

set -e

echo "🇪🇺 JarvisVertexAI GDPR Compliance Validation"
echo "============================================="
echo "Starting GDPR compliance check at $(date)"
echo ""

PROJECT_DIR="/Users/tim/JarvisVertexAI"
EXIT_CODE=0

cd "$PROJECT_DIR"

# Test 1: Right to Erasure (Article 17)
echo "🗑️ Testing Right to Erasure..."

# Check for data deletion functionality
if grep -r -q -E "(deleteAllData|eraseData|removeAllData)" "$PROJECT_DIR/JarvisVertexAI/Core/" 2>/dev/null; then
    echo "✅ Data deletion functionality found"
else
    echo "❌ Data deletion functionality not found"
    EXIT_CODE=1
fi

# Check for specific deletion methods
DELETION_METHODS=("deleteSession" "clearDatabase" "removeUser.*Data")
DELETION_FOUND=0

for method in "${DELETION_METHODS[@]}"; do
    if grep -r -q -E "$method" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
        ((DELETION_FOUND++))
    fi
done

if [ $DELETION_FOUND -ge 1 ]; then
    echo "✅ Specific deletion methods implemented ($DELETION_FOUND)"
else
    echo "❌ No specific deletion methods found"
    EXIT_CODE=1
fi

# Test 2: Data Portability (Article 20)
echo ""
echo "📤 Testing Data Portability..."

# Check for data export functionality
if grep -r -q -E "(exportData|exportAllData|dataExport)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ Data export functionality found"
else
    echo "❌ Data export functionality not found"
    EXIT_CODE=1
fi

# Check for structured data formats
EXPORT_FORMATS=("JSON" "CSV" "XML")
FORMAT_FOUND=0

for format in "${EXPORT_FORMATS[@]}"; do
    if grep -r -q -i "$format" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
        ((FORMAT_FOUND++))
    fi
done

if [ $FORMAT_FOUND -ge 1 ]; then
    echo "✅ Structured export formats available ($FORMAT_FOUND formats)"
else
    echo "⚠️  Limited structured export format support"
    EXIT_CODE=1
fi

# Test 3: Lawful Basis and Consent (Article 6)
echo ""
echo "📋 Testing Consent Management..."

# Check for consent tracking
if grep -r -q -E "(consent|UserConsent|agreement)" "$PROJECT_DIR/JarvisVertexAI/Core/" 2>/dev/null; then
    echo "✅ Consent management implementation found"
else
    echo "❌ Consent management not found"
    EXIT_CODE=1
fi

# Check for OAuth consent handling
if [ -f "$PROJECT_DIR/JarvisVertexAI/Core/ToolCalling/GoogleOAuthManager.swift" ]; then
    if grep -q -E "(consent|authorization|permission)" "$PROJECT_DIR/JarvisVertexAI/Core/ToolCalling/GoogleOAuthManager.swift"; then
        echo "✅ OAuth consent handling implemented"
    else
        echo "⚠️  OAuth consent handling may be incomplete"
        EXIT_CODE=1
    fi
else
    echo "❌ OAuth manager not found"
    EXIT_CODE=1
fi

# Test 4: Data Minimization (Article 5)
echo ""
echo "📊 Testing Data Minimization..."

# Check for minimal data collection principles
if grep -r -q -E "(minimal.*data|minimum.*collection|least.*privilege)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ Data minimization principles found"
else
    echo "ℹ️  Data minimization principles not explicitly referenced"
fi

# Check OAuth scopes are minimal
if [ -f "$PROJECT_DIR/JarvisVertexAI/Core/ToolCalling/GoogleOAuthManager.swift" ]; then
    MINIMAL_SCOPES=("readonly" "\.file" "limited")
    SCOPE_FOUND=0

    for scope in "${MINIMAL_SCOPES[@]}"; do
        if grep -q -E "$scope" "$PROJECT_DIR/JarvisVertexAI/Core/ToolCalling/GoogleOAuthManager.swift"; then
            ((SCOPE_FOUND++))
        fi
    done

    if [ $SCOPE_FOUND -ge 1 ]; then
        echo "✅ Minimal OAuth scopes implemented"
    else
        echo "⚠️  OAuth scopes may not be minimal"
        EXIT_CODE=1
    fi
fi

# Test 5: Privacy by Design (Article 25)
echo ""
echo "🛡️ Testing Privacy by Design..."

# Check for privacy-first architecture
PRIVACY_FEATURES=("local.*storage" "on.*device" "zero.*retention" "encryption")
PRIVACY_FOUND=0

for feature in "${PRIVACY_FEATURES[@]}"; do
    if grep -r -q -i -E "$feature" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
        ((PRIVACY_FOUND++))
    fi
done

if [ $PRIVACY_FOUND -ge 3 ]; then
    echo "✅ Privacy-by-design features implemented ($PRIVACY_FOUND features)"
else
    echo "⚠️  Limited privacy-by-design implementation ($PRIVACY_FOUND features)"
    EXIT_CODE=1
fi

# Check for default privacy settings
if grep -r -q -E "(privacy.*default|secure.*default)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ Privacy-by-default configuration found"
else
    echo "ℹ️  Privacy-by-default not explicitly configured"
fi

# Test 6: Data Subject Rights Implementation
echo ""
echo "👤 Testing Data Subject Rights..."

# Check for privacy dashboard or user control interface
if grep -r -q -E "(PrivacyDashboard|UserControl|privacy.*settings)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ Privacy dashboard/controls found"
else
    echo "❌ Privacy dashboard/controls not found"
    EXIT_CODE=1
fi

# Check for data access functionality
if grep -r -q -E "(viewData|accessData|showData)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ Data access functionality found"
else
    echo "⚠️  Data access functionality limited"
    EXIT_CODE=1
fi

# Test 7: Cross-Border Data Transfer Compliance
echo ""
echo "🌍 Testing Cross-Border Transfer Compliance..."

# Check for data residency controls
if [ -f "$PROJECT_DIR/.env.local" ]; then
    source "$PROJECT_DIR/.env.local"
    if [ -n "$VERTEX_REGION" ]; then
        echo "✅ Data region configuration found: $VERTEX_REGION"

        # Check if it's an EU region
        if echo "$VERTEX_REGION" | grep -q -E "(europe|eu|frankfurt|london|paris|milan|zurich|finland|belgium|netherlands|ireland)"; then
            echo "✅ EU/EEA region configured for data processing"
        else
            echo "⚠️  Non-EU region configured - ensure adequate safeguards"
        fi
    else
        echo "⚠️  Data region not configured"
        EXIT_CODE=1
    fi
else
    echo "❌ Environment configuration not found"
    EXIT_CODE=1
fi

# Test 8: Data Retention Limits (Article 5)
echo ""
echo "⏰ Testing Data Retention Limits..."

# Check for retention period configuration
if grep -r -q -E "(retention.*period|delete.*after|expire.*days)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ Data retention limits implemented"
else
    echo "⚠️  Data retention limits not clearly defined"
    EXIT_CODE=1
fi

# Check for automatic cleanup
if grep -r -q -E "(auto.*cleanup|automatic.*delete|scheduled.*cleanup)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ Automatic data cleanup implemented"
else
    echo "⚠️  Automatic cleanup not implemented"
    EXIT_CODE=1
fi

# Test 9: Record of Processing Activities (Article 30)
echo ""
echo "📝 Testing Processing Records..."

# Check for data processing documentation
PROCESSING_DOCS=("README.md" "PRIVACY_ANALYSIS.md" "COMPLIANCE_ANALYSIS.md")
DOCS_FOUND=0

for doc in "${PROCESSING_DOCS[@]}"; do
    if [ -f "$PROJECT_DIR/$doc" ]; then
        ((DOCS_FOUND++))
        echo "✅ Processing documentation found: $doc"
    fi
done

if [ $DOCS_FOUND -ge 2 ]; then
    echo "✅ Adequate processing documentation ($DOCS_FOUND docs)"
else
    echo "⚠️  Limited processing documentation ($DOCS_FOUND docs)"
    EXIT_CODE=1
fi

# Test 10: Breach Notification Preparedness (Article 33-34)
echo ""
echo "🚨 Testing Breach Notification Preparedness..."

# Check for incident response mechanisms
if grep -r -q -E "(incident|breach|security.*event|audit.*log)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ Incident response mechanisms found"
else
    echo "⚠️  Incident response mechanisms not clearly implemented"
    EXIT_CODE=1
fi

echo ""
echo "📋 GDPR Compliance Summary"
echo "========================="

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ GDPR COMPLIANCE: PASSED"
    echo "All critical GDPR requirements appear to be implemented:"
    echo "  ✓ Right to erasure (data deletion)"
    echo "  ✓ Data portability (export functionality)"
    echo "  ✓ Consent management"
    echo "  ✓ Data minimization"
    echo "  ✓ Privacy by design"
    echo "  ✓ Data subject rights"
    echo "  ✓ Cross-border transfer compliance"
    echo "  ✓ Data retention limits"
    echo "  ✓ Processing activity records"
    echo "  ✓ Breach notification preparedness"
else
    echo "⚠️  GDPR COMPLIANCE: NEEDS ATTENTION"
    echo "Some GDPR requirements need review or implementation."
    echo "Please address the issues above before processing EU personal data."
fi

echo ""
echo "🇪🇺 GDPR compliance check completed at $(date)"
echo ""
echo "Note: This automated check verifies technical implementation indicators."
echo "Full GDPR compliance requires legal review, privacy impact assessment,"
echo "and ongoing compliance monitoring."

exit $EXIT_CODE