#!/bin/bash

# JarvisVertexAI Credential Setup Script
# This script will prompt you for all necessary credentials and save them to .env.local

set -e

echo "🔧 JarvisVertexAI Credential Setup"
echo "=================================="
echo ""
echo "This script will help you configure your Google Cloud credentials for the JarvisVertexAI app."
echo "You'll need to have already set up a Google Cloud project with Vertex AI enabled."
echo ""

# Check if .env.local already exists
if [ -f ".env.local" ]; then
    echo "⚠️  .env.local already exists. Creating backup..."
    cp .env.local .env.local.backup.$(date +%s)
    echo "✅ Backup created"
    echo ""
fi

# Function to prompt for input with validation
prompt_input() {
    local var_name="$1"
    local prompt_text="$2"
    local required="$3"
    local example="$4"

    while true; do
        echo -n "$prompt_text"
        if [ -n "$example" ]; then
            echo -n " (e.g., $example)"
        fi
        echo -n ": "
        read -r input

        if [ "$required" = "true" ] && [ -z "$input" ]; then
            echo "❌ This field is required. Please enter a value."
            continue
        fi

        if [ -n "$input" ]; then
            echo "$var_name=\"$input\"" >> .env.local
            echo "✅ Saved"
        else
            echo "$var_name=" >> .env.local
            echo "⏭️  Skipped (optional)"
        fi
        break
    done
    echo ""
}

# Function to prompt for yes/no
prompt_yes_no() {
    local prompt_text="$1"
    local default="$2"

    while true; do
        echo -n "$prompt_text [y/N]: "
        read -r input

        case "$input" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo]|"")
                return 1
                ;;
            *)
                echo "Please enter y or n."
                ;;
        esac
    done
}

# Create new .env.local file
echo "# JarvisVertexAI Environment Configuration" > .env.local
echo "# Generated on $(date)" >> .env.local
echo "" >> .env.local

echo "📋 Step 1: Google Cloud Project Configuration"
echo "=============================================="
echo ""

prompt_input "VERTEX_PROJECT_ID" "Enter your Google Cloud Project ID" "true" "my-ai-project-12345"

echo "🌍 Step 2: Region Configuration"
echo "==============================="
echo ""
echo "Available regions for Vertex AI:"
echo "  • us-central1 (Iowa, USA)"
echo "  • us-east1 (South Carolina, USA)"
echo "  • us-west1 (Oregon, USA)"
echo "  • europe-west1 (Belgium)"
echo "  • asia-southeast1 (Singapore)"
echo ""
prompt_input "VERTEX_REGION" "Enter your preferred Vertex AI region" "false" "us-central1"

echo "🔐 Step 3: CMEK Encryption (Optional but Recommended)"
echo "===================================================="
echo ""
echo "Customer-Managed Encryption Keys (CMEK) provide additional security."
echo "Format: projects/[PROJECT]/locations/[REGION]/keyRings/[KEYRING]/cryptoKeys/[KEY]"
echo ""
if prompt_yes_no "Do you have a CMEK key configured?"; then
    prompt_input "VERTEX_CMEK_KEY" "Enter your CMEK key path" "false" "projects/my-project/locations/us-central1/keyRings/vertex-ai-keyring/cryptoKeys/vertex-ai-cmek"
else
    echo "VERTEX_CMEK_KEY=" >> .env.local
    echo "⚠️  CMEK not configured - data will use Google-managed encryption"
fi
echo ""

echo "🔑 Step 4: OAuth Configuration"
echo "=============================="
echo ""
echo "You need a Google OAuth 2.0 Client ID for authentication."
echo "Get this from: https://console.cloud.google.com/apis/credentials"
echo ""
prompt_input "GOOGLE_OAUTH_CLIENT_ID" "Enter your OAuth Client ID" "true" "123456789-abcdefghijk.apps.googleusercontent.com"

echo "🎙️ Step 5: Audio Endpoint (Optional)"
echo "===================================="
echo ""
prompt_input "VERTEX_AUDIO_ENDPOINT" "Enter Gemini Live audio endpoint name" "false" "gemini-live-audio"

echo "🔧 Step 6: Development Token (Optional)"
echo "======================================="
echo ""
echo "For development, you can provide an access token directly."
echo "⚠️  WARNING: This should only be used for testing!"
echo ""
if prompt_yes_no "Do you want to set a development access token?"; then
    echo -n "Enter your access token: "
    read -s token
    echo ""
    echo "VERTEX_ACCESS_TOKEN=\"$token\"" >> .env.local
    echo "✅ Token saved (hidden)"
else
    echo "# VERTEX_ACCESS_TOKEN=your-access-token-for-development-only" >> .env.local
    echo "⏭️  Skipped - will use OAuth flow"
fi
echo ""

# Add privacy flags (non-configurable)
echo "" >> .env.local
echo "# Privacy Flags (DO NOT CHANGE - Required for compliance)" >> .env.local
echo "DISABLE_PROMPT_LOGGING=true" >> .env.local
echo "DISABLE_DATA_RETENTION=true" >> .env.local
echo "DISABLE_MODEL_TRAINING=true" >> .env.local
echo "ENABLE_PHI_REDACTION=true" >> .env.local
echo "LOCAL_ONLY_MODE=true" >> .env.local
echo "ZERO_RETENTION_MODE=true" >> .env.local
echo "" >> .env.local
echo "# Cache and Storage Configuration" >> .env.local
echo "VERTEX_AI_EXPLICIT_CACHE_MODE=off" >> .env.local
echo "EPHEMERAL_FILE_RETENTION=24" >> .env.local
echo "DB_ENCRYPTION_ENABLED=true" >> .env.local
echo "DB_CLOUD_SYNC_DISABLED=true" >> .env.local
echo "AUTO_CLEANUP_DAYS=30" >> .env.local

echo "✅ Configuration Complete!"
echo "========================="
echo ""
echo "Your credentials have been saved to .env.local"
echo ""
echo "📋 Summary:"
echo "  • Project ID: $(grep VERTEX_PROJECT_ID .env.local | cut -d'=' -f2 | tr -d '"')"
echo "  • Region: $(grep VERTEX_REGION .env.local | cut -d'=' -f2 | tr -d '"' || echo 'us-central1 (default)')"
echo "  • CMEK: $(if grep -q 'VERTEX_CMEK_KEY=' .env.local && [ -n "$(grep VERTEX_CMEK_KEY .env.local | cut -d'=' -f2)" ]; then echo 'Configured'; else echo 'Not configured'; fi)"
echo "  • OAuth: $(grep GOOGLE_OAUTH_CLIENT_ID .env.local | cut -d'=' -f2 | tr -d '"')"
echo "  • Privacy Mode: ✅ Enabled (all privacy flags set)"
echo ""
echo "🚀 Next Steps:"
echo "  1. Open the project in Xcode"
echo "  2. Build and run on iOS 17+ device/simulator"
echo "  3. The app will use these credentials automatically"
echo ""
echo "🔒 Security Notes:"
echo "  • .env.local contains sensitive data - never commit to git"
echo "  • All privacy flags are enforced for compliance"
echo "  • Database encryption is enabled by default"
echo ""
echo "📖 For more information, see:"
echo "  • README.md - Project overview"
echo "  • IMPLEMENTATION_SUMMARY.md - Technical details"
echo "  • Mac_Claude_Instructions.txt - Original requirements"
echo ""

# Set secure permissions on the .env.local file
chmod 600 .env.local
echo "🔐 Set secure permissions (600) on .env.local"
echo ""
echo "Done! 🎉"