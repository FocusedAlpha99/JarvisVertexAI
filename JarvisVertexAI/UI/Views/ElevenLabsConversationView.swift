import SwiftUI
// TODO: Uncomment when ElevenLabs SDK is properly added to Xcode project
// import ElevenLabs

@available(iOS 17.0, *)
struct ElevenLabsConversationView: View {
    @StateObject private var conversationManager = ConversationManager()
    @State private var showingConfiguration = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header Section
                VStack(spacing: 16) {
                    HStack {
                        Text("Advanced Voice Chat")
                            .font(.title2)
                            .fontWeight(.bold)

                        Spacer()

                        Button(action: { showingConfiguration = true }) {
                            Image(systemName: "gear")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    // Status Section
                    VStack(spacing: 12) {
                        Text(conversationManager.statusMessage)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(conversationManager.isConnected ? .green : conversationManager.isProcessing ? .orange : .primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        // Connection Status Indicator
                        HStack(spacing: 8) {
                            Circle()
                                .fill(conversationManager.isConnected ? Color.green : conversationManager.isProcessing ? Color.orange : Color.gray)
                                .frame(width: 8, height: 8)

                            Text(conversationManager.connectionState)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if conversationManager.isMuted {
                                Image(systemName: "mic.slash.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }

                // Messages Section
                if !conversationManager.messages.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(conversationManager.messages, id: \.id) { message in
                                    MessageBubbleView(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .frame(maxHeight: min(geometry.size.height * 0.5, 400))
                        .onChange(of: conversationManager.messages.count) { _ in
                            if let lastMessage = conversationManager.messages.last {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                } else if conversationManager.isConnected {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("Start speaking to begin the conversation")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: 200)
                    .padding(.top, 32)
                }

                Spacer()

                // Control Section
                VStack(spacing: 20) {
                    // Main Action Button
                    Button(action: {
                        Task {
                            if conversationManager.isConnected {
                                await conversationManager.endConversation()
                            } else {
                                await conversationManager.startConversation()
                            }
                        }
                    }) {
                        ZStack {
                            // Background circle
                            Circle()
                                .fill(conversationManager.isConnected ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                                .frame(width: conversationManager.isProcessing ? 140 : 120,
                                       height: conversationManager.isProcessing ? 140 : 120)
                                .shadow(color: (conversationManager.isConnected ? Color.red : Color.blue).opacity(0.3),
                                        radius: conversationManager.isProcessing ? 20 : 8, x: 0, y: 4)

                            // Processing pulse ring
                            if conversationManager.isProcessing {
                                Circle()
                                    .stroke(Color.orange.opacity(0.4), lineWidth: 3)
                                    .frame(width: 135, height: 135)
                                    .scaleEffect(1.2)
                                    .opacity(0.7)
                                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: conversationManager.isProcessing)
                            }

                            // Icon
                            Image(systemName: conversationManager.isConnected ? "phone.down.fill" : "phone.fill")
                                .font(.system(size: conversationManager.isProcessing ? 50 : 44, weight: .medium))
                                .foregroundColor(conversationManager.isConnected ? .red : .blue)
                        }
                    }
                    .disabled(conversationManager.isProcessing)
                    .scaleEffect(conversationManager.isProcessing ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: conversationManager.isProcessing)

                    // Secondary Controls
                    if conversationManager.isConnected {
                        HStack(spacing: 24) {
                            // Mute Button
                            Button(action: {
                                Task {
                                    await conversationManager.toggleMute()
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: conversationManager.isMuted ? "mic.slash.fill" : "mic.fill")
                                        .font(.title2)
                                        .foregroundColor(conversationManager.isMuted ? .red : .blue)

                                    Text(conversationManager.isMuted ? "Unmute" : "Mute")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(width: 60, height: 60)
                            .background(
                                Circle()
                                    .fill(Color(.systemGray6))
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            )
                        }
                    }

                    // Instruction text
                    Text(getInstructionText())
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, max(geometry.safeAreaInsets.bottom + 32, 48))
            }
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingConfiguration) {
            ConfigurationView(conversationManager: conversationManager)
        }
        .onAppear {
            print("🎤 ElevenLabsConversationView appeared")
        }
        .onDisappear {
            Task {
                if conversationManager.isConnected {
                    await conversationManager.endConversation()
                }
            }
        }
    }

    private func getInstructionText() -> String {
        if !conversationManager.isConfigured {
            return "Configure ElevenLabs API credentials in settings"
        } else if conversationManager.isProcessing {
            return "Connecting to ElevenLabs..."
        } else if conversationManager.isConnected {
            return "Conversation active - speak naturally"
        } else {
            return "Tap to start voice conversation"
        }
    }
}

// MARK: - Message Bubble View
struct MessageBubbleView: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(message.role == .user ? Color.blue : Color(.systemGray5))
                    )

                Text(message.role == .user ? "You" : "Assistant")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

// MARK: - Configuration View
struct ConfigurationView: View {
    @ObservedObject var conversationManager: ConversationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "gear.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.blue)

                    Text("ElevenLabs Configuration")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(conversationManager.configurationStatus)
                        .font(.body)
                        .foregroundColor(conversationManager.isConfigured ? .green : .orange)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Required Environment Variables:")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("• ELEVENLABS_API_KEY")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("• ELEVENLABS_AGENT_ID")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Text("Configure these in your .env.local file or Xcode scheme environment variables.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )

                Spacer()
            }
            .padding()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ElevenLabsConversationView()
}