import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Mode 3: Text + Multimodal UI
struct TextMultimodalView: View {
    @StateObject private var viewModel = TextMultimodalViewModel()
    @State private var messageText = ""
    @State private var showImagePicker = false
    @State private var showDocumentPicker = false
    @State private var selectedImages: [PhotosPickerItem] = []
    @State private var showAttachmentMenu = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderBar(viewModel: viewModel)
            
            // Messages
            MessagesList(viewModel: viewModel)
            
            // Attachments preview
            if !viewModel.attachments.isEmpty {
                AttachmentsPreview(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Input area
            InputArea(
                messageText: $messageText,
                isTextFieldFocused: $isTextFieldFocused,
                showAttachmentMenu: $showAttachmentMenu,
                viewModel: viewModel
            )
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showImagePicker) {
            PhotosPicker(
                selection: $selectedImages,
                maxSelectionCount: 5,
                matching: .images
            ) {
                Text("Select Photos")
            }
            .onChange(of: selectedImages) { items in
                viewModel.processSelectedPhotos(items)
                selectedImages = []
            }
        }
        .confirmationDialog("Add Attachment", isPresented: $showAttachmentMenu) {
            Button("Photo Library") {
                showImagePicker = true
            }
            Button("Camera") {
                viewModel.openCamera()
            }
            Button("Document") {
                showDocumentPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [.pdf, .text, .plainText],
            allowsMultipleSelection: false
        ) { result in
            viewModel.processDocument(result)
        }
    }
}

// MARK: - Header Bar
struct HeaderBar: View {
    @ObservedObject var viewModel: TextMultimodalViewModel
    @State private var showPrivacySheet = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Text + Multimodal")
                    .font(.title2)
                    .fontWeight(.bold)
                
                HStack(spacing: 6) {
                    PrivacyBadge(icon: "keyboard", text: "Text Mode")
                    PrivacyBadge(icon: "photo", text: "Files")
                    if viewModel.ephemeralMode {
                        PrivacyBadge(icon: "timer", text: "Ephemeral", color: .orange)
                    }
                }
            }
            
            Spacer()
            
            Button(action: { showPrivacySheet = true }) {
                Image(systemName: "shield.checkmark")
                    .font(.title2)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .sheet(isPresented: $showPrivacySheet) {
            PrivacyInfoSheet(mode: .text)
        }
    }
}

struct PrivacyBadge: View {
    let icon: String
    let text: String
    var color: Color = .blue
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .cornerRadius(4)
    }
}

// MARK: - Messages List
struct MessagesList: View {
    @ObservedObject var viewModel: TextMultimodalViewModel
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MultimodalMessageBubble(message: message)
                            .id(message.id)
                    }
                    
                    if viewModel.isTyping {
                        TypingIndicator()
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _ in
                withAnimation {
                    proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Multimodal Message Bubble
struct MultimodalMessageBubble: View {
    let message: MultimodalMessage
    @State private var showFullImage = false
    @State private var selectedImage: Data?
    
    var body: some View {
        HStack {
            if message.isUser { Spacer() }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                // Attachments
                if !message.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(message.attachments) { attachment in
                                AttachmentThumbnail(attachment: attachment) {
                                    if attachment.type == .image {
                                        selectedImage = attachment.data
                                        showFullImage = true
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
                
                // Text content
                if !message.content.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if message.wasRedacted {
                            Label("PHI Redacted", systemImage: "eye.slash")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        
                        Text(message.content)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(message.isUser ? Color.blue : Color(uiColor: .systemGray5))
                            )
                            .foregroundColor(message.isUser ? .white : .primary)
                    }
                }
                
                // Metadata
                HStack(spacing: 8) {
                    if message.processingTime > 0 {
                        Label("\\(String(format: "%.1fs", message.processingTime))", 
                              systemImage: "clock")
                            .font(.caption2)
                    }
                    
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                    
                    if message.ephemeral {
                        Image(systemName: "timer")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: 300, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser { Spacer() }
        }
        .sheet(isPresented: $showFullImage) {
            if let imageData = selectedImage,
               let uiImage = UIImage(data: imageData) {
                ImageViewer(image: uiImage)
            }
        }
    }
}

// MARK: - Attachment Thumbnail
struct AttachmentThumbnail: View {
    let attachment: MessageAttachment
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .systemGray6))
                    .frame(width: 80, height: 80)
                
                if attachment.type == .image,
                   let uiImage = UIImage(data: attachment.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: attachment.type.icon)
                            .font(.title2)
                        Text(attachment.type.rawValue)
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
                
                // Privacy indicator
                if attachment.wasRedacted {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "eye.slash.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.orange)
                                .cornerRadius(4)
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }
        }
    }
}

// MARK: - Attachments Preview
struct AttachmentsPreview: View {
    @ObservedObject var viewModel: TextMultimodalViewModel
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.attachments) { attachment in
                    AttachmentPreviewCard(
                        attachment: attachment,
                        onRemove: {
                            viewModel.removeAttachment(attachment.id)
                        }
                    )
                }
            }
            .padding()
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

struct AttachmentPreviewCard: View {
    let attachment: MessageAttachment
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 100, height: 100)
                .overlay(
                    VStack {
                        if attachment.type == .image,
                           let uiImage = UIImage(data: attachment.data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipped()
                        } else {
                            Image(systemName: attachment.type.icon)
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                        }
                    }
                )
                .cornerRadius(12)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .background(Color.white)
                    .clipShape(Circle())
            }
            .offset(x: 8, y: -8)
        }
    }
}

// MARK: - Input Area
struct InputArea: View {
    @Binding var messageText: String
    @FocusState.Binding var isTextFieldFocused: Bool
    @Binding var showAttachmentMenu: Bool
    @ObservedObject var viewModel: TextMultimodalViewModel
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Attachment button
            Button(action: { showAttachmentMenu = true }) {
                Image(systemName: "paperclip")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 8)
            
            // Text field
            TextField("Type a message...", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(uiColor: .systemGray6))
                )
                .focused($isTextFieldFocused)
                .onSubmit {
                    if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        viewModel.sendMessage(messageText)
                        messageText = ""
                    }
                }
            
            // Send button
            Button(action: {
                if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
                   !viewModel.attachments.isEmpty {
                    viewModel.sendMessage(messageText)
                    messageText = ""
                }
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundColor(
                        (!messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
                         !viewModel.attachments.isEmpty) ? .blue : .gray
                    )
            }
            .padding(.bottom, 4)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .offset(y: animationOffset)
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: animationOffset
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .systemGray5))
        )
        .onAppear {
            animationOffset = -8
        }
    }
}

// MARK: - Image Viewer
struct ImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        NavigationView {
            ZoomableScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .background(Color.black)
        }
    }
}

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private var content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5
        scrollView.minimumZoomScale = 1
        scrollView.bouncesZoom = true
        
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        scrollView.addSubview(hostingController.view)
        
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            hostingController.view.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
        
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableScrollView
        
        init(_ parent: ZoomableScrollView) {
            self.parent = parent
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            scrollView.subviews.first
        }
    }
}

// MARK: - Text Multimodal View Model
class TextMultimodalViewModel: ObservableObject {
    @Published var messages: [MultimodalMessage] = []
    @Published var attachments: [MessageAttachment] = []
    @Published var isTyping = false
    @Published var ephemeralMode = false
    
    private let multimodalChat: MultimodalChat
    private let dbManager = ObjectBoxManager.shared
    private let phiRedactor = PHIRedactor()
    
    init() {
        self.multimodalChat = MultimodalChat(
            projectId: VertexConfig.projectId,
            region: VertexConfig.region
        )
        loadRecentMessages()
    }
    
    private func loadRecentMessages() {
        // Load from ObjectBox
        if let sessions = try? dbManager.getRecentSessions(mode: .textMultimodal, limit: 1),
           let lastSession = sessions.first,
           let transcripts = try? dbManager.getTranscripts(sessionId: lastSession.id) {
            
            messages = transcripts.compactMap { transcript in
                MultimodalMessage(
                    id: UUID().uuidString,
                    content: transcript.text,
                    isUser: transcript.speaker == "user",
                    timestamp: transcript.timestamp,
                    attachments: [],
                    wasRedacted: transcript.metadata["redacted"] as? Bool ?? false,
                    ephemeral: transcript.metadata["ephemeral"] as? Bool ?? false,
                    processingTime: 0
                )
            }
        }
    }
    
    func sendMessage(_ text: String) {
        let startTime = Date()
        
        // Redact PHI
        let redactedText = phiRedactor.redactPHI(from: text)
        let wasRedacted = redactedText != text
        
        // Create user message
        let userMessage = MultimodalMessage(
            id: UUID().uuidString,
            content: text,
            isUser: true,
            timestamp: Date(),
            attachments: attachments,
            wasRedacted: wasRedacted,
            ephemeral: ephemeralMode,
            processingTime: 0
        )
        
        messages.append(userMessage)
        
        // Clear attachments after sending
        let sentAttachments = attachments
        attachments = []
        
        // Save to local DB
        let sessionId = getCurrentSessionId()
        try? dbManager.addTranscript(
            sessionId: sessionId,
            speaker: "user",
            text: text,
            metadata: [
                "redacted": wasRedacted,
                "attachments": sentAttachments.count,
                "ephemeral": ephemeralMode
            ]
        )
        
        // Show typing indicator
        isTyping = true
        
        // Send to Gemini
        Task {
            let response = await multimodalChat.sendMessage(
                text: redactedText,
                attachments: sentAttachments
            )
            
            let processingTime = Date().timeIntervalSince(startTime)
            
            await MainActor.run {
                isTyping = false
                
                let assistantMessage = MultimodalMessage(
                    id: UUID().uuidString,
                    content: response ?? "Error processing request",
                    isUser: false,
                    timestamp: Date(),
                    attachments: [],
                    wasRedacted: false,
                    ephemeral: ephemeralMode,
                    processingTime: processingTime
                )
                
                messages.append(assistantMessage)
                
                // Save assistant response
                try? dbManager.addTranscript(
                    sessionId: sessionId,
                    speaker: "assistant",
                    text: response ?? "",
                    metadata: ["processingTime": processingTime]
                )
                
                // Clean up ephemeral attachments
                if ephemeralMode {
                    cleanupEphemeralData(sentAttachments)
                }
            }
        }
    }
    
    func processSelectedPhotos(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let attachment = MessageAttachment(
                        id: UUID().uuidString,
                        type: .image,
                        data: data,
                        wasRedacted: false
                    )
                    
                    await MainActor.run {
                        attachments.append(attachment)
                    }
                }
            }
        }
    }
    
    func processDocument(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            do {
                let data = try Data(contentsOf: url)
                let attachment = MessageAttachment(
                    id: UUID().uuidString,
                    type: .document,
                    data: data,
                    wasRedacted: false
                )
                attachments.append(attachment)
            } catch {
                print("Error loading document: \\(error)")
            }
        }
    }
    
    func openCamera() {
        // Camera implementation would go here
    }
    
    func removeAttachment(_ id: String) {
        attachments.removeAll { $0.id == id }
    }
    
    private func cleanupEphemeralData(_ attachments: [MessageAttachment]) {
        // Overwrite attachment data
        for attachment in attachments {
            var mutableData = attachment.data
            let count = mutableData.count
            mutableData.withUnsafeMutableBytes { bytes in
                _ = SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
            }
        }
    }
    
    private func getCurrentSessionId() -> String {
        "text_multimodal_\\(Date().timeIntervalSince1970)"
    }
}

// MARK: - Models
struct MultimodalMessage: Identifiable {
    let id: String
    let content: String
    let isUser: Bool
    let timestamp: Date
    let attachments: [MessageAttachment]
    let wasRedacted: Bool
    let ephemeral: Bool
    let processingTime: TimeInterval
}

struct MessageAttachment: Identifiable {
    let id: String
    let type: AttachmentType
    let data: Data
    let wasRedacted: Bool
    
    enum AttachmentType: String {
        case image = "Image"
        case document = "Document"
        case audio = "Audio"
        
        var icon: String {
            switch self {
            case .image: return "photo"
            case .document: return "doc.text"
            case .audio: return "waveform"
            }
        }
    }
}