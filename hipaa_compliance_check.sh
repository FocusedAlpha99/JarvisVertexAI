#!/bin/bash
# JarvisVertexAI HIPAA Compliance Validation
# Tests HIPAA requirements: encryption, audit logging, access controls, data retention

set -e

echo "🏥 JarvisVertexAI HIPAA Compliance Validation"
echo "============================================"
echo "Starting HIPAA compliance check at $(date)"
echo ""

PROJECT_DIR="/Users/tim/JarvisVertexAI"
BUNDLE_ID="com.focusedalpha.jarvisvertexai"
SIMULATOR_UDID="3641BCA1-C9BE-493D-8ED6-1D04EB394D10"
EXIT_CODE=0

cd "$PROJECT_DIR"

# Test 1: Encryption at Rest Verification
echo "🔐 Testing Encryption at Rest..."

# Check for encryption implementation in code
if grep -r -q -E "(AES|encrypt|cipher)" "$PROJECT_DIR/JarvisVertexAI/Core/" 2>/dev/null; then
    echo "✅ Encryption implementation found in codebase"
else
    echo "⚠️  Encryption implementation not clearly identified"
    EXIT_CODE=1
fi

# Check ObjectBox encryption configuration
if grep -r -q -E "(encrypted|encryption)" "$PROJECT_DIR/JarvisVertexAI/Core/Database/" 2>/dev/null; then
    echo "✅ Database encryption configuration found"
else
    echo "⚠️  Database encryption configuration not found"
    EXIT_CODE=1
fi

# Test 2: Encryption in Transit Verification
echo ""
echo "🌐 Testing Encryption in Transit..."

# Check for HTTPS enforcement
if grep -r -q -E "(https://|TLS|SSL)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ HTTPS/TLS configuration found"
else
    echo "⚠️  HTTPS/TLS configuration not clearly identified"
    EXIT_CODE=1
fi

# Check for certificate pinning or secure transport
if grep -r -q -E "(NSAppTransportSecurity|certificate.*pinning)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ App Transport Security configuration found"
else
    echo "ℹ️  App Transport Security configuration not found (may use defaults)"
fi

# Test 3: Access Controls Verification
echo ""
echo "🔒 Testing Access Controls..."

# Check for device-level security
if grep -q -E "(biometric|TouchID|FaceID|LocalAuthentication)" "$PROJECT_DIR/JarvisVertexAI/"* 2>/dev/null; then
    echo "✅ Biometric authentication implementation found"
else
    echo "ℹ️  Biometric authentication not implemented (device-level security may be sufficient)"
fi

# Check file permissions in app structure
APP_CONTAINER=$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" data 2>/dev/null || echo "")

if [ -n "$APP_CONTAINER" ] && [ -d "$APP_CONTAINER" ]; then
    PERMS=$(stat -f "%OLp" "$APP_CONTAINER" 2>/dev/null || echo "")
    if [ "$PERMS" = "700" ] || [ "$PERMS" = "755" ]; then
        echo "✅ App container has secure permissions ($PERMS)"
    else
        echo "⚠️  App container permissions may be insufficient ($PERMS)"
        EXIT_CODE=1
    fi
else
    echo "ℹ️  Cannot verify runtime access controls (app container not accessible)"
fi

# Test 4: Audit Logging Implementation
echo ""
echo "📝 Testing Audit Logging..."

# Check for audit logging in code
if grep -r -q -E "(audit|log|event.*tracking)" "$PROJECT_DIR/JarvisVertexAI/Core/" 2>/dev/null; then
    echo "✅ Audit logging implementation found"
else
    echo "⚠️  Audit logging implementation not found"
    EXIT_CODE=1
fi

# Check for specific audit events
AUDIT_EVENTS=("login" "access" "data.*modification" "export" "delete")
AUDIT_FOUND=0

for event in "${AUDIT_EVENTS[@]}"; do
    if grep -r -q -i "$event" "$PROJECT_DIR/JarvisVertexAI/Core/" 2>/dev/null; then
        ((AUDIT_FOUND++))
    fi
done

if [ $AUDIT_FOUND -ge 2 ]; then
    echo "✅ Multiple audit event types found ($AUDIT_FOUND)"
else
    echo "⚠️  Limited audit event coverage found ($AUDIT_FOUND)"
    EXIT_CODE=1
fi

# Test 5: Data Retention Controls
echo ""
echo "⏰ Testing Data Retention Controls..."

# Check for data retention policies in code
if grep -r -q -E "(retention|cleanup|delete.*old|expire)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ Data retention controls found"
else
    echo "⚠️  Data retention controls not found"
    EXIT_CODE=1
fi

# Check for automatic cleanup implementation
if grep -r -q -E "(auto.*delete|cleanup.*schedule|expire.*after)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ Automatic cleanup implementation found"
else
    echo "⚠️  Automatic cleanup not clearly implemented"
    EXIT_CODE=1
fi

# Test 6: Business Associate Agreement Requirements
echo ""
echo "📋 Testing BAA Requirements..."

# Check for zero data retention configuration
if grep -r -q -E "(zero.*retention|no.*retention|disablePromptLogging)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ Zero data retention configuration found"
else
    echo "⚠️  Zero data retention configuration not found"
    EXIT_CODE=1
fi

# Check for CMEK configuration
if [ -f "$PROJECT_DIR/.env.local" ]; then
    source "$PROJECT_DIR/.env.local"
    if [ -n "$VERTEX_CMEK_KEY" ]; then
        echo "✅ CMEK key configuration found"
    else
        echo "⚠️  CMEK key not configured"
        EXIT_CODE=1
    fi
else
    echo "⚠️  Environment configuration not found"
    EXIT_CODE=1
fi

# Test 7: PHI Protection Verification
echo ""
echo "🛡️ Testing PHI Protection..."

# Check for PHI redaction implementation
if [ -f "$PROJECT_DIR/JarvisVertexAI/Core/Privacy/PHIRedactor.swift" ]; then
    echo "✅ PHI redaction module found"

    # Check for specific PHI patterns
    PHI_PATTERNS=("SSN" "social.*security" "credit.*card" "medical.*record" "phone.*number")
    PHI_FOUND=0

    for pattern in "${PHI_PATTERNS[@]}"; do
        if grep -q -i "$pattern" "$PROJECT_DIR/JarvisVertexAI/Core/Privacy/PHIRedactor.swift" 2>/dev/null; then
            ((PHI_FOUND++))
        fi
    done

    if [ $PHI_FOUND -ge 3 ]; then
        echo "✅ Comprehensive PHI patterns found ($PHI_FOUND)"
    else
        echo "⚠️  Limited PHI pattern coverage ($PHI_FOUND)"
        EXIT_CODE=1
    fi
else
    echo "❌ PHI redaction module not found"
    EXIT_CODE=1
fi

# Test 8: Minimum Necessary Standard
echo ""
echo "📊 Testing Minimum Necessary Standard..."

# Check for minimal data collection
if grep -r -q -E "(minimal.*scope|least.*privilege|minimum.*necessary)" "$PROJECT_DIR/JarvisVertexAI/" 2>/dev/null; then
    echo "✅ Minimum necessary principle implementation found"
else
    echo "ℹ️  Minimum necessary principle not explicitly referenced"
fi

# Check OAuth scopes are minimal
if [ -f "$PROJECT_DIR/JarvisVertexAI/Core/ToolCalling/GoogleOAuthManager.swift" ]; then
    if grep -q -E "(readonly|\.file)" "$PROJECT_DIR/JarvisVertexAI/Core/ToolCalling/GoogleOAuthManager.swift"; then
        echo "✅ Minimal OAuth scopes implemented"
    else
        echo "⚠️  OAuth scopes may be too broad"
        EXIT_CODE=1
    fi
fi

echo ""
echo "📋 HIPAA Compliance Summary"
echo "=========================="

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ HIPAA COMPLIANCE: PASSED"
    echo "All critical HIPAA requirements appear to be implemented:"
    echo "  ✓ Encryption at rest and in transit"
    echo "  ✓ Access controls and file permissions"
    echo "  ✓ Audit logging implementation"
    echo "  ✓ Data retention controls"
    echo "  ✓ BAA requirements (zero retention, CMEK)"
    echo "  ✓ PHI protection and redaction"
    echo "  ✓ Minimum necessary standard"
else
    echo "⚠️  HIPAA COMPLIANCE: NEEDS ATTENTION"
    echo "Some HIPAA requirements need review or implementation."
    echo "Please address the warnings above before production deployment."
fi

echo ""
echo "🏥 HIPAA compliance check completed at $(date)"
echo ""
echo "Note: This automated check verifies implementation indicators."
echo "Full HIPAA compliance requires legal review, BAA execution,"
echo "and comprehensive security assessment."

exit $EXIT_CODE