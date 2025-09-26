# JarvisVertexAI Setup Instructions

Complete setup guide for configuring Google Cloud Vertex AI integration and running the application.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Google Cloud Project Setup](#google-cloud-project-setup)
3. [Authentication Configuration](#authentication-configuration)
4. [Environment Configuration](#environment-configuration)
5. [Build and Run](#build-and-run)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

- macOS 12.0+ or iOS 17.0+
- Xcode 15.0+
- Google Cloud Account
- Swift 5.9+

## Google Cloud Project Setup

### 1. Create a Google Cloud Project

```bash
# Install Google Cloud CLI if not already installed
brew install --cask google-cloud-sdk

# Initialize gcloud and authenticate
gcloud init
gcloud auth login

# Create a new project (optional)
gcloud projects create your-project-id --name="JarvisVertexAI"

# Set the project as default
gcloud config set project your-project-id
```

### 2. Enable Required APIs

```bash
# Enable Vertex AI API
gcloud services enable aiplatform.googleapis.com

# Enable Generative AI API
gcloud services enable generativelanguage.googleapis.com

# Enable Speech-to-Text API (for voice features)
gcloud services enable speech.googleapis.com

# Enable Text-to-Speech API (for voice features)
gcloud services enable texttospeech.googleapis.com

# Verify enabled services
gcloud services list --enabled
```

### 3. Configure Vertex AI Region

Choose a supported region for Vertex AI:

```bash
# Set default region (choose one)
gcloud config set ai/region us-central1    # Recommended
# gcloud config set ai/region us-east1
# gcloud config set ai/region europe-west1
# gcloud config set ai/region asia-northeast1
```

## Authentication Configuration

Choose **one** of the three authentication methods:

### Option 1: Service Account (Recommended for Production)

```bash
# Create a service account
gcloud iam service-accounts create jarvis-vertexai \
    --description="JarvisVertexAI Service Account" \
    --display-name="JarvisVertexAI"

# Grant required permissions
gcloud projects add-iam-policy-binding your-project-id \
    --member="serviceAccount:jarvis-vertexai@your-project-id.iam.gserviceaccount.com" \
    --role="roles/aiplatform.user"

gcloud projects add-iam-policy-binding your-project-id \
    --member="serviceAccount:jarvis-vertexai@your-project-id.iam.gserviceaccount.com" \
    --role="roles/ml.developer"

# Create and download service account key
gcloud iam service-accounts keys create ~/jarvis-service-account.json \
    --iam-account=jarvis-vertexai@your-project-id.iam.gserviceaccount.com

# Secure the key file
chmod 600 ~/jarvis-service-account.json
```

### Option 2: OAuth2 (Development)

```bash
# Create OAuth2 credentials in Google Cloud Console
# 1. Go to: https://console.cloud.google.com/apis/credentials
# 2. Click "Create Credentials" > "OAuth 2.0 Client IDs"
# 3. Choose "iOS" or "macOS" application type
# 4. Add your bundle identifier: com.focusedalpha.jarvisvertexai
# 5. Download the client configuration
```

### Option 3: Access Token (Testing)

```bash
# Generate a temporary access token
gcloud auth application-default print-access-token

# Note: Tokens expire in ~1 hour and are only for testing
```

## Environment Configuration

### 1. Copy Environment File

```bash
# Navigate to project directory
cd /path/to/JarvisVertexAI

# Copy the template (if .env.local doesn't exist)
cp .env.local.template .env.local
```

### 2. Configure Environment Variables

Edit `.env.local` with your specific values:

```bash
# === Required Configuration ===
GOOGLE_CLOUD_PROJECT_ID=your-project-id-here
GOOGLE_CLOUD_REGION=us-central1

# === Choose ONE Authentication Method ===

# Service Account (Option 1)
GOOGLE_SERVICE_ACCOUNT_PATH=/path/to/your/service-account.json

# OAuth2 (Option 2)
# GOOGLE_OAUTH_CLIENT_ID=your-client-id.apps.googleusercontent.com
# GOOGLE_OAUTH_CLIENT_SECRET=your-client-secret

# Access Token (Option 3)
# VERTEX_ACCESS_TOKEN=ya29.your-access-token-here

# === Optional Configuration ===
GEMINI_MODEL=gemini-2.0-flash-exp
ENABLE_PHI_REDACTION=true
DEBUG_LOGGING=false
```

### 3. Secure Environment File

```bash
# Set proper permissions
chmod 600 .env.local

# Add to .gitignore to prevent committing secrets
echo ".env.local" >> .gitignore
```

## Build and Run

### 1. Install Dependencies

The project uses Swift Package Manager. Dependencies should be automatically resolved by Xcode.

### 2. Configure Xcode

1. Open `JarvisVertexAI.xcodeproj` in Xcode
2. Select your development team in Project Settings
3. Update bundle identifier if needed: `com.focusedalpha.jarvisvertexai`
4. Choose your target device or simulator

### 3. Build and Run

```bash
# Build from command line
xcodebuild -scheme JarvisVertexAI -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build

# Or build and run in Xcode (⌘+R)
```

### 4. Test Configuration

The app will automatically validate configuration on startup. Check the console for:

```
✅ VertexConfig: Configuration loaded successfully
🔧 Project: your-project-id, Region: us-central1
🔐 Auth: Service Account
```

## Troubleshooting

### Configuration Issues

#### Missing Project ID
```
❌ Google Cloud Project ID not configured
```
**Solution**: Set `GOOGLE_CLOUD_PROJECT_ID` in `.env.local`

#### Authentication Failed
```
❌ No valid authentication method configured
```
**Solution**: Configure service account, OAuth2, or access token

#### Service Account File Not Found
```
❌ Configuration file not found: /path/to/service-account.json
```
**Solution**:
- Verify file path in `GOOGLE_SERVICE_ACCOUNT_PATH`
- Check file permissions (`chmod 600`)
- Re-download service account key if needed

### API Issues

#### Quota Exceeded
```
❌ Vertex AI quota exceeded
```
**Solution**:
- Check quotas in Google Cloud Console
- Request quota increase if needed
- Implement rate limiting in app

#### Permission Denied
```
❌ Permission denied for Vertex AI API
```
**Solution**:
- Verify APIs are enabled
- Check service account permissions
- Ensure correct project ID

#### Region Not Supported
```
❌ Invalid region format: invalid-region
```
**Solution**: Use supported regions like `us-central1`, `us-east1`, `europe-west1`

### Build Issues

#### Swift Package Manager
If dependencies fail to resolve:
```bash
# Reset package caches
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf .build
```

#### Code Signing
For iOS deployment:
1. Select valid development team
2. Create provisioning profile
3. Enable required capabilities

### Runtime Issues

#### Microphone Permission
The app requires microphone access for voice features:
- iOS will prompt automatically
- Grant permission in Settings > Privacy if needed

#### Network Connectivity
Vertex AI requires internet connection:
- Check network settings
- Verify firewall/VPN configuration
- Test with `curl` to verify API access

## Advanced Configuration

### Privacy & Compliance

The app is configured for maximum privacy by default:

```bash
# Privacy flags in .env.local
DISABLE_PROMPT_LOGGING=true
DISABLE_DATA_RETENTION=true
LOCAL_ONLY_MODE=true
ENABLE_PHI_REDACTION=true
ZERO_RETENTION_MODE=true
```

### Custom Model Configuration

To use different Gemini models:

```bash
# In .env.local
GEMINI_MODEL=gemini-2.0-flash-exp
# GEMINI_MODEL=gemini-1.5-pro
# GEMINI_MODEL=gemini-1.5-flash
```

### Development Mode

Enable debug logging and test features:

```bash
# In .env.local
DEBUG_LOGGING=true
TEST_MODE=true
ENABLE_EXPERIMENTAL_FEATURES=true
```

## Support

For additional help:

1. Check the [Issues](https://github.com/your-repo/issues) page
2. Review Google Cloud documentation
3. Consult Vertex AI API documentation
4. Enable debug logging for detailed error messages

## Security Notes

- Never commit `.env.local` to version control
- Rotate service account keys regularly
- Use least-privilege permissions
- Monitor API usage and costs
- Enable audit logging for production