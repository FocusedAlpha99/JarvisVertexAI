//
//  TextMultimodalView.swift
//  JarvisVertexAI
//
//  Mode 3: Text + Multimodal Chat Interface
//  Supports text input, file attachments, drag/drop, conversation history
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct TextMultimodalView: View {
    // MARK: - State Properties
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var conversationHistory: [ConversationMessage] = []
    @State private var attachments: [FileAttachment] = []
    @State private var isDragOver = false
    @State private var uploadProgress: [UUID: Double] = [:]
    @State private var showingExportOptions = false
    @State private var showingImagePicker = false
    @State private var showingFilePicker = false
    @State private var ephemeralFileCount = 0
    @State private var lastCleanupTime: Date?

    // MARK: - Computed Properties
    private var canSendMessage: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private var hasAttachments: Bool {
        !attachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with privacy indicators
            headerView

            // Conversation history
            conversationScrollView

            // Attachments preview
            if hasAttachments {
                attachmentsPreview
            }

            // Input area
            inputArea
        }
        .navigationTitle("Text + Multimodal")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupNotificationObservers()
            updateEphemeralFileStatus()
        }
        .onDisappear {
            cleanup()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .sheet(isPresented: $showingExportOptions) {
            exportOptionsView
        }
        .photosPicker(
            isPresented: $showingImagePicker,
            selection: Binding<PhotosPickerItem?>(
                get: { nil },
                set: { item in
                    if let item = item {
                        loadPhotoPickerItem(item)
                    }
                }
            ),
            matching: .images
        )
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack {
            // Privacy indicators
            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .foregroundColor(.green)
                    .font(.caption)

                Text("PHI Protected")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if ephemeralFileCount > 0 {
                    Text("• \(ephemeralFileCount) files")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            // Export button
            Button(action: { showingExportOptions = true }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16))
            }
            .disabled(conversationHistory.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    // MARK: - Conversation Scroll View
    private var conversationScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if conversationHistory.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(conversationHistory) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onChange(of: conversationHistory.count) {
                if let lastMessage = conversationHistory.last {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Start a multimodal conversation")
                .font(.title2)
                .fontWeight(.medium)

            Text("Send text messages, attach images, or upload documents for analysis")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "camera")
                    Text("Images are analyzed with vision AI")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "doc.text")
                    Text("Documents are processed for content")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "timer")
                    Text("Files auto-delete after 24 hours")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 40)
    }

    // MARK: - Attachments Preview
    private var attachmentsPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(attachments) { attachment in
                    AttachmentPreviewView(
                        attachment: attachment,
                        uploadProgress: uploadProgress[attachment.id] ?? 0.0,
                        onRemove: { removeAttachment(attachment) }
                    )
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    // MARK: - Input Area
    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                // Attachment button
                Menu {
                    Button(action: { showingImagePicker = true }) {
                        Label("Add Image", systemImage: "photo")
                    }

                    Button(action: { showingFilePicker = true }) {
                        Label("Add Document", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }

                // Text input
                HStack(alignment: .bottom) {
                    TextField("Type your message...", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .disabled(isLoading)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(canSendMessage ? .blue : .gray)
                        }
                        .disabled(!canSendMessage)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(20)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .onDrop(of: [.image, .pdf, .data], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
        .overlay(
            isDragOver ? dragOverOverlay : nil
        )
    }

    // MARK: - Drag Over Overlay
    private var dragOverOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [5]))
            .background(Color.blue.opacity(0.1))
            .overlay(
                VStack {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                    Text("Drop files here")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            )
    }

    // MARK: - Export Options View
    private var exportOptionsView: some View {
        NavigationView {
            List {
                Button("Export as Text") {
                    exportConversation(format: .text)
                }

                Button("Export as JSON") {
                    exportConversation(format: .json)
                }

                Button("Share Conversation") {
                    shareConversation()
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingExportOptions = false
                    }
                }
            }
        }
    }
}

// MARK: - Message Actions
extension TextMultimodalView {
    private func sendMessage() {
        guard canSendMessage else { return }

        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentAttachments = attachments

        // Clear input immediately
        messageText = ""
        attachments = []
        uploadProgress = [:]

        // Add user message to history
        let userMessage = ConversationMessage(
            id: UUID(),
            content: text.isEmpty ? "[Attachments only]" : text,
            isUser: true,
            timestamp: Date(),
            attachments: currentAttachments.map { $0.filename }
        )
        conversationHistory.append(userMessage)

        Task {
            await performSendMessage(text: text, fileAttachments: currentAttachments)
        }
    }

    @MainActor
    private func performSendMessage(text: String, fileAttachments: [FileAttachment]) async {
        isLoading = true

        do {
            // Convert FileAttachments to Attachments
            let multimodalAttachments = fileAttachments.map { fileAttachment in
                Attachment(
                    type: fileAttachment.type == .image ? .image : .document,
                    data: fileAttachment.data,
                    filename: fileAttachment.filename
                )
            }

            // Send message
            let response = await MultimodalChat.shared.sendMessage(
                text: text.isEmpty ? "Please analyze the attached files." : text,
                attachments: multimodalAttachments
            )

            // Add assistant response
            if let response = response {
                let assistantMessage = ConversationMessage(
                    id: UUID(),
                    content: response,
                    isUser: false,
                    timestamp: Date(),
                    attachments: []
                )
                conversationHistory.append(assistantMessage)
            } else {
                showError("Failed to get response from the AI assistant. Please try again.")
            }

            // Update ephemeral file count
            updateEphemeralFileStatus()

        } catch {
            showError("Failed to send message: \(error.localizedDescription)")
        }

        isLoading = false
    }

}

// MARK: - File Handling
extension TextMultimodalView {
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            handleItemProvider(provider)
        }
        return true
    }

    private func handleItemProvider(_ provider: NSItemProvider) {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                DispatchQueue.main.async {
                    if let data = data, error == nil {
                        self.addImageAttachment(data: data, filename: "dropped_image.jpg")
                    }
                }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.pdf.identifier) { data, error in
                DispatchQueue.main.async {
                    if let data = data, error == nil {
                        self.addDocumentAttachment(data: data, filename: "dropped_document.pdf")
                    }
                }
            }
        }
    }

    private func loadPhotoPickerItem(_ item: PhotosPickerItem) {
        item.loadTransferable(type: Data.self) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    if let data = data {
                        self.addImageAttachment(data: data, filename: "selected_image.jpg")
                    }
                case .failure(let error):
                    self.showError("Failed to load image: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                loadFile(from: url)
            }
        case .failure(let error):
            showError("Failed to import file: \(error.localizedDescription)")
        }
    }

    private func loadFile(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            showError("Unable to access selected file")
            return
        }

        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent

            if url.pathExtension.lowercased() == "pdf" {
                addDocumentAttachment(data: data, filename: filename)
            } else {
                addDocumentAttachment(data: data, filename: filename)
            }
        } catch {
            showError("Failed to read file: \(error.localizedDescription)")
        }
    }

    private func addImageAttachment(data: Data, filename: String) {
        let attachment = FileAttachment(
            id: UUID(),
            data: data,
            filename: filename,
            type: .image,
            size: data.count
        )
        attachments.append(attachment)
        simulateUploadProgress(for: attachment.id)
    }

    private func addDocumentAttachment(data: Data, filename: String) {
        let attachment = FileAttachment(
            id: UUID(),
            data: data,
            filename: filename,
            type: .document,
            size: data.count
        )
        attachments.append(attachment)
        simulateUploadProgress(for: attachment.id)
    }

    private func simulateUploadProgress(for id: UUID) {
        uploadProgress[id] = 0.0

        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            DispatchQueue.main.async {
                if let currentProgress = self.uploadProgress[id] {
                    let newProgress = min(currentProgress + 0.1, 1.0)
                    self.uploadProgress[id] = newProgress

                    if newProgress >= 1.0 {
                        timer.invalidate()
                    }
                }
            }
        }
    }

    private func removeAttachment(_ attachment: FileAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        uploadProgress.removeValue(forKey: attachment.id)
    }
}

// MARK: - Export Functionality
extension TextMultimodalView {
    private enum ExportFormat {
        case text
        case json
    }

    private func exportConversation(format: ExportFormat) {
        let content: String

        switch format {
        case .text:
            content = conversationHistory.map { message in
                let timestamp = DateFormatter.localizedString(from: message.timestamp, dateStyle: .short, timeStyle: .short)
                let sender = message.isUser ? "You" : "Assistant"
                var text = "[\(timestamp)] \(sender): \(message.content)"

                if !message.attachments.isEmpty {
                    text += " [Attachments: \(message.attachments.joined(separator: ", "))]"
                }

                return text
            }.joined(separator: "\n\n")

        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601

            if let data = try? encoder.encode(conversationHistory),
               let jsonString = String(data: data, encoding: .utf8) {
                content = jsonString
            } else {
                content = "Failed to export as JSON"
            }
        }

        // Save to files
        let filename = "conversation_\(Date().timeIntervalSince1970).\(format == .text ? "txt" : "json")"
        saveToFiles(content: content, filename: filename)
        showingExportOptions = false
    }

    private func shareConversation() {
        let text = conversationHistory.map { message in
            let sender = message.isUser ? "You" : "Assistant"
            return "\(sender): \(message.content)"
        }.joined(separator: "\n\n")

        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            activityVC.popoverPresentationController?.sourceView = rootVC.view
            rootVC.present(activityVC, animated: true)
        }

        showingExportOptions = false
    }

    private func saveToFiles(content: String, filename: String) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filePath = documentsPath.appendingPathComponent(filename)

        do {
            try content.write(to: filePath, atomically: true, encoding: .utf8)
            // Show success message or open Files app
        } catch {
            showError("Failed to save file: \(error.localizedDescription)")
        }
    }
}

// MARK: - Notifications & Cleanup
extension TextMultimodalView {
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("multimodalResponseReceived"),
            object: nil,
            queue: .main
        ) { _ in
            updateEphemeralFileStatus()
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("multimodalError"),
            object: nil,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?["error"] as? Error {
                showError(error.localizedDescription)
            }
        }
    }

    private func updateEphemeralFileStatus() {
        ephemeralFileCount = attachments.count
        lastCleanupTime = Date()
    }

    private func cleanup() {
        NotificationCenter.default.removeObserver(self)
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Supporting Views
struct MessageBubbleView: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 50)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        message.isUser ? Color.blue : Color(.systemGray5)
                    )
                    .foregroundColor(
                        message.isUser ? .white : .primary
                    )
                    .cornerRadius(18)

                if !message.attachments.isEmpty {
                    Text("📎 \(message.attachments.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(DateFormatter.localizedString(from: message.timestamp, dateStyle: .none, timeStyle: .short))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !message.isUser {
                Spacer(minLength: 50)
            }
        }
    }
}

struct AttachmentPreviewView: View {
    let attachment: FileAttachment
    let uploadProgress: Double
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray4))
                    .frame(width: 60, height: 60)

                if attachment.type == .image {
                    if let uiImage = UIImage(data: attachment.data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipped()
                            .cornerRadius(8)
                    } else {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }

                if uploadProgress < 1.0 {
                    CircularProgressView(progress: uploadProgress)
                }

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .background(Color.white, in: Circle())
                }
                .offset(x: 25, y: -25)
            }

            Text(attachment.filename)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: 60)
        }
    }
}

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 2)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)
        }
        .frame(width: 20, height: 20)
    }
}

// MARK: - Data Models
struct ConversationMessage: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    let attachments: [String]
}

struct FileAttachment: Identifiable {
    enum AttachmentType {
        case image
        case document
    }

    let id: UUID
    let data: Data
    let filename: String
    let type: AttachmentType
    let size: Int
}

// MARK: - Preview
struct TextMultimodalView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            TextMultimodalView()
        }
    }
}