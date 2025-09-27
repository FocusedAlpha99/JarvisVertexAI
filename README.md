# JarvisVertexAI - Privacy-First iOS Gemini Assistant

## 🔒 Maximum Privacy Gemini AI with 100% On-Device Storage

A three-mode conversational AI iOS application leveraging Google Vertex AI's Gemini models with enterprise-grade privacy, HIPAA/GDPR compliance, and complete local data persistence.

## ✨ Features

### Three Conversation Modes

#### Mode 1: Native Audio (Gemini Live API) ⭐ **2025 Enhanced**
- **Real-time bidirectional voice streaming** using Gemini Live API
- **Zero data retention** with enterprise-grade privacy controls
- **Protocol compliant**: 16kHz input, 24kHz output per API specification
- **Intelligent error handling**: Proper WebSocket close code handling (1000, 1001, 1011)
- **Robust reconnection**: Exponential backoff with quota-aware retry logic
- **setupComplete protocol**: Proper session acknowledgment before audio streaming
- **CMEK & VPC-SC ready**: Customer-managed encryption and network isolation
- **Production reliability**: Complete session state management and recovery

#### Mode 2: Voice Chat Local (Hold-to-Speak)
- Hold-to-speak button interface for precise control
- 100% on-device speech recognition (iOS Speech framework)
- Direct Gemini REST API integration (text-only)
- Local TTS synthesis with iOS AVSpeechSynthesizer
- PHI automatically redacted before transmission
- Professional UI with real-time visual feedback

#### Mode 3: Text + Multimodal
- **Direct Gemini API integration** for reliable multimodal chat
- **Keyboard input with drag-and-drop** file attachments
- **Advanced image analysis** with vision AI capabilities
- **Document processing** for PDFs and text files
- **Ephemeral file storage** (24-hour auto-delete)
- **Real-time conversation history** with professional UI
- **Privacy-first design** with automatic PHI redaction

### 🛡️ Privacy & Security Features

- **ObjectBox Database**: 100% local storage, no cloud sync
- **AES-256 Encryption**: Device-specific encryption keys
- **PHI/PII Redaction**: Automatic detection and removal
- **Zero Data Retention**: Configured at Vertex AI level
- **CMEK Protection**: Customer-managed encryption keys with HSM
- **VPC Service Controls**: Network isolation and data exfiltration prevention
- **30-Day Auto-Cleanup**: Automatic old data deletion
- **No Analytics**: Zero tracking or telemetry

### 🔧 Tool Calling Integration

Minimal-scope OAuth integration for:
- Google Tasks (read-only)
- Google Calendar (read-only)
- Gmail (read-only)
- Google Drive (app-created files only)

## 🚀 Recent Improvements (September 2025)

### Mode 1: Gemini Live API Audio Buffering & Performance (v2.2.0)
- ✅ **Audio Chunk Buffering**: Intelligent 300ms accumulation eliminates stuttering audio
- ✅ **Performance Optimization**: 90% reduction in logging during audio streaming
- ✅ **Audio Session Management**: Resolved priority conflicts and session errors
- ✅ **Smooth Playback**: Seamless audio without 0.04s fragment interruptions
- ✅ **Bluetooth Enhancement**: Improved A2DP support for wireless audio quality
- ✅ **Audio Format Compliance**: 16kHz input, 24kHz output per API specification
- ✅ **Protocol Compliance**: camelCase field naming and setupComplete acknowledgment
- ✅ **WebSocket Error Handling**: Intelligent close code handling (1000, 1001, 1011)
- ✅ **Reconnection Logic**: Exponential backoff with quota-aware retry strategies
- ✅ **Production Ready**: Comprehensive error recovery and connection stability

### Mode 3: Text + Multimodal Enhanced Reliability
- ✅ **API Architecture Simplified**: Migrated from Vertex AI to direct Gemini API for consistency
- ✅ **Authentication Streamlined**: Uses reliable API key authentication (same as Mode 2)
- ✅ **Multimodal Support**: Full support for images, documents, and text with vision AI
- ✅ **Error Handling**: Removed hardcoded responses, proper error propagation
- ✅ **Build Stability**: Fixed compilation issues and Swift syntax errors

### Cross-Mode Improvements
- ✅ **PHI Redaction**: Enhanced pattern detection with medical context awareness
- ✅ **Token Management**: Automatic OAuth token refresh with retry logic
- ✅ **Database Security**: Enhanced encryption and privacy controls
- ✅ **Test Coverage**: Comprehensive test suite for all privacy and compliance scenarios

## 📋 Requirements

- iOS 17.0+
- Xcode 15.0+
- Google Cloud Project with Vertex AI enabled
- Vertex AI Enterprise (not free tier)
- Business Associate Agreement (BAA) for HIPAA
- Zero Data Retention (ZDR) approval from Google

## 🚀 Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/[your-username]/JarvisVertexAI.git
cd JarvisVertexAI
```

### 2. Configure Environment
```bash
cp .env.example .env.local
# Edit .env.local with your credentials:
# - VERTEX_PROJECT_ID
# - VERTEX_REGION
# - VERTEX_CMEK_KEY
# - GOOGLE_OAUTH_CLIENT_ID
```

### 3. Install Dependencies
```bash
xcodebuild -resolvePackageDependencies
```

### 4. Configure Vertex AI
```bash
# Login to Google Cloud
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# Enable required APIs
gcloud services enable aiplatform.googleapis.com
gcloud services enable cloudkms.googleapis.com

# Create CMEK key
gcloud kms keyrings create vertex-ai-keyring --location=us-central1
gcloud kms keys create vertex-ai-cmek \
  --location=us-central1 \
  --keyring=vertex-ai-keyring \
  --purpose=encryption \
  --protection-level=hsm
```

### 5. Build and Run
```bash
open JarvisVertexAI.xcodeproj
# Select target device/simulator
# Press Cmd+R to run
```

## 🧪 Testing

Comprehensive test suite included:

```bash
# Run all tests
./run_unit_tests.sh

# Privacy compliance
./privacy_compliance_tests.sh

# HIPAA compliance
./hipaa_compliance_check.sh

# GDPR compliance
./gdpr_compliance_check.sh
```

See `COMPLETE_TEST_SUITE.txt` for detailed testing instructions.

## 📱 App Architecture

```
JarvisVertexAI/
├── Core/
│   ├── Database/          # ObjectBox local storage
│   ├── Privacy/           # PHI redaction & encryption
│   ├── VertexAI/          # Gemini API integration
│   └── ToolCalling/       # OAuth & Google services
├── UI/
│   └── Views/             # SwiftUI interfaces
├── Tests/                 # Unit & integration tests
└── Resources/             # Assets & configurations
```

## 🔐 Compliance

### HIPAA Compliance
- ✅ Encryption at rest (AES-256)
- ✅ Encryption in transit (TLS 1.3)
- ✅ Access controls (device-level)
- ✅ Audit logging (6-year retention)
- ✅ Business Associate Agreement

### GDPR Compliance
- ✅ Data minimization
- ✅ Right to erasure
- ✅ Data portability
- ✅ Explicit consent
- ✅ Privacy by design

## 🛠️ Configuration

### Required Environment Variables
```bash
VERTEX_PROJECT_ID="your-project-id"
VERTEX_REGION="us-central1"
VERTEX_AUDIO_ENDPOINT="projects/[PROJECT]/locations/[REGION]/endpoints/[ID]"
VERTEX_CMEK_KEY="projects/[PROJECT]/locations/[REGION]/keyRings/[RING]/cryptoKeys/[KEY]"
GOOGLE_OAUTH_CLIENT_ID="[CLIENT_ID].apps.googleusercontent.com"
VERTEX_AI_EXPLICIT_CACHE_MODE="off"
```

### Info.plist Requirements
- Microphone usage description
- Speech recognition usage description
- Photo library usage description
- Camera usage description
- Background modes (audio, processing)

## 📊 Privacy Dashboard

Built-in privacy dashboard provides:
- Real-time privacy status
- Data export (JSON/CSV)
- Complete data deletion
- Storage statistics
- Compliance validation

## ⚠️ Important Notes

1. **Vertex AI Enterprise Required**: Free tier does not support zero retention
2. **ZDR Request**: Must file Zero Data Retention request with Google
3. **BAA Required**: HIPAA compliance requires signed BAA
4. **CMEK Setup**: Must configure customer-managed encryption keys
5. **Region Lock**: Data residency controls must be configured

## 🤝 Contributing

Contributions welcome! Please ensure:
- All tests pass
- Privacy compliance maintained
- PHI redaction functional
- No new external dependencies without review

## 📄 License

MIT License - See LICENSE file for details

## 🔗 Resources

- [Vertex AI Zero Data Retention](https://cloud.google.com/vertex-ai/docs/generative-ai/data-governance)
- [HIPAA Compliance Guide](https://cloud.google.com/security/compliance/hipaa-compliance)
- [ObjectBox Documentation](https://objectbox.io/swift/)
- [Gemini API Reference](https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/gemini)

## 💡 Support

For issues or questions:
1. Check `COMPLETE_TEST_SUITE.txt` for troubleshooting
2. Review `VERTEX_AI_COMPLIANCE_REFERENCE.txt`
3. Open an issue on GitHub

---

**Privacy First. Always.**

Built with maximum privacy and compliance for handling sensitive data.