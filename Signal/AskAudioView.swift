import SwiftUI

struct AskAudioView: View {
    let recording: Recording
    var onNavigateToSegment: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var colors: AppColors {
        AppColors(colorScheme: colorScheme)
    }
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var copiedMessageID: UUID?
    @State private var showDeleteConfirmation = false
    @FocusState private var isInputFocused: Bool

    private var chatContent: some View {
        ZStack(alignment: .bottom) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Add top spacing for content visibility
                        Spacer()
                            .frame(height: 16)
                        
                        if messages.isEmpty && !isLoading {
                            emptyState
                        }

                        ForEach(messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }

                        if isLoading {
                            typingIndicator
                                .id("typing")
                        }

                        if let error = errorMessage {
                            errorBubble(error)
                        }
                        
                        // Add spacing at bottom for floating input bar and bottom bar
                        Spacer()
                            .frame(height: 160)
                    }
                    .padding(.horizontal, AppLayout.horizontalPadding)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture {
                    isInputFocused = false
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: isLoading) { _, loading in
                    if loading { scrollToBottom(proxy: proxy) }
                }
            }

            // Floating input bar
            VStack(spacing: 0) {
                inputBar
                
                // Bottom bar spacing
                Spacer()
                    .frame(height: 68)
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            chatContent
                .background(colors.background.ignoresSafeArea())
                .onAppear(perform: loadMessages)
                .onChange(of: messages) { _, newValue in
                    ChatPersistence.save(newValue, for: recording.uid)
                }
                .environment(\.openURL, OpenURLAction(handler: handleURLOpen))
                .alert("Delete Conversation?", isPresented: $showDeleteConfirmation, actions: deleteAlert, message: deleteAlertMessage)
            
            bottomBar
        }
    }
    
    private func loadMessages() {
        messages = ChatPersistence.load(for: recording.uid)
    }
    
    @ViewBuilder
    private func deleteAlert() -> some View {
        Button("Cancel", role: .cancel) { }
        Button("Delete", role: .destructive) {
            messages.removeAll()
            errorMessage = nil
        }
    }
    
    @ViewBuilder
    private func deleteAlertMessage() -> some View {
        Text("This will permanently delete all messages in this conversation.")
    }
    
    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Done button
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text(L10n.done)
                        .font(AppFont.mono(size: 14, weight: .medium))
                }
                .foregroundStyle(colors.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            
            Spacer()
            
            // Title
            Text(L10n.askYourAudio)
                .font(AppFont.mono(size: 13, weight: .semibold))
                .kerning(1.5)
                .foregroundStyle(colors.primaryText)
            
            Spacer()
            
            // Delete button
            if !messages.isEmpty {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundStyle(colors.secondaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            } else {
                // Invisible spacer to maintain layout symmetry
                Color.clear
                    .frame(width: 48, height: 44)
            }
        }
        .padding(.horizontal, AppLayout.horizontalPadding)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(colors.background.opacity(0.8))
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .fill(colors.glassBorder)
                .frame(height: 0.5),
            alignment: .top
        )
    }
    
    private func handleURLOpen(_ url: URL) -> OpenURLAction.Result {
        if url.scheme == "trace", url.host == "citation",
           let secondsStr = url.pathComponents.last,
           let seconds = TimeInterval(secondsStr) {
            let citation = TimestampCitation(
                text: ChatService.formatSecondsToTimestamp(seconds),
                range: "".startIndex..<"".endIndex,
                timeInterval: seconds
            )
            navigateToCitation(citation)
            return .handled
        }
        return .systemAction
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(colors.mutedText)

            Text(L10n.askAnything)
                .font(AppFont.mono(size: 16, weight: .bold))
                .kerning(1.5)
                .foregroundStyle(colors.secondaryText)

            Text(L10n.askAudioHelp)
                .font(AppFont.mono(size: 12))
                .foregroundStyle(colors.mutedText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Suggested questions
            VStack(spacing: 8) {
                suggestionButton(L10n.suggestedKeyDecisions)
                suggestionButton(L10n.suggestedMainTopics)
                suggestionButton(L10n.suggestedWhoSaid)
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    private func suggestionButton(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            Text(text)
                .font(AppFont.mono(size: 12, weight: .medium))
                .foregroundStyle(colors.secondaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(colors.selection)
                .clipShape(RoundedRectangle(cornerRadius: AppLayout.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppLayout.inputRadius)
                        .stroke(colors.glassBorder, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Message Bubble

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            messageContent(message)

            if message.role == .model { Spacer(minLength: 60) }
        }
    }

    private func messageContent(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        let isCopied = copiedMessageID == message.id
        return Text(styledContent(message.content, isUser: isUser))
            .font(AppFont.mono(size: 14, weight: .regular))
            .lineSpacing(5)
            .tint(colors.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassCard(radius: 14, padding: 0)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isCopied ? colors.glassBorderStrong : .clear, lineWidth: isCopied ? 1.5 : 0)
            )
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.content
                    copiedMessageID = message.id
                    // Reset the visual feedback after a moment
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedMessageID == message.id {
                            copiedMessageID = nil
                        }
                    }
                } label: {
                    Label(L10n.copyToClipboard, systemImage: "doc.on.doc")
                }
            }
    }

    private func styledContent(_ text: String, isUser: Bool) -> AttributedString {
        // For user messages, just return plain text
        if isUser {
            var attributed = AttributedString(text)
            attributed.foregroundColor = colors.primaryText
            return attributed
        }
        
        // For model messages, manually parse markdown and citations
        var attributed = AttributedString(text)
        attributed.foregroundColor = colors.primaryText.opacity(0.85)
        
        // Parse and apply markdown formatting manually
        attributed = applyMarkdownFormatting(to: attributed, originalText: text)
        
        // Parse and apply timestamp citations as tappable links
        attributed = applyTimestampLinks(to: attributed, originalText: text)
        
        return attributed
    }
    
    private func applyMarkdownFormatting(to attributed: AttributedString, originalText: String) -> AttributedString {
        var result = attributed
        
        // Handle **bold** text
        let boldPattern = #"\*\*([^\*]+?)\*\*"#
        if let boldRegex = try? NSRegularExpression(pattern: boldPattern) {
            let matches = boldRegex.matches(in: originalText, range: NSRange(originalText.startIndex..., in: originalText))
            
            // Process in reverse to maintain correct indices
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: originalText),
                      let contentRange = Range(match.range(at: 1), in: originalText) else { continue }
                
                // Get the text content without the ** markers
                let boldText = String(originalText[contentRange])
                
                // Calculate offsets based on already-processed text
                let markersBeforeCount = matches.filter { 
                    guard let r = Range($0.range, in: originalText) else { return false }
                    return r.upperBound <= fullRange.lowerBound
                }.count * 4 // Each ** pair is 4 characters
                
                let startOffset = originalText.distance(from: originalText.startIndex, to: fullRange.lowerBound) - markersBeforeCount
                
                // Safety check
                guard startOffset >= 0, startOffset <= result.characters.count else { continue }
                
                let attrStart = result.index(result.startIndex, offsetByCharacters: startOffset)
                let currentLength = originalText.distance(from: fullRange.lowerBound, to: fullRange.upperBound)
                let endOffset = startOffset + currentLength
                
                guard endOffset <= result.characters.count else { continue }
                let attrEnd = result.index(result.startIndex, offsetByCharacters: endOffset)
                
                // Remove the ** markers and apply bold styling
                var boldStr = AttributedString(boldText)
                boldStr.font = AppFont.monoUI(size: 14, weight: .bold)
                boldStr.foregroundColor = colors.primaryText
                
                result.replaceSubrange(attrStart..<attrEnd, with: boldStr)
            }
        }
        
        return result
    }
    
    private func applyTimestampLinks(to attributed: AttributedString, originalText: String) -> AttributedString {
        var result = attributed
        
        // Parse citations from the CURRENT result string (after markdown processing)
        let resultString = String(result.characters)
        let pattern = #"\[(\d{1,2}:\d{2}(?::\d{2})?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        
        let matches = regex.matches(in: resultString, range: NSRange(resultString.startIndex..., in: resultString))
        
        // Process in reverse to maintain correct indices
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: resultString),
                  let innerRange = Range(match.range(at: 1), in: resultString) else { continue }
            
            let timeString = String(resultString[innerRange])
            guard let timeInterval = parseTimeString(timeString) else { continue }
            
            // Find positions in attributed string
            let startOffset = resultString.distance(from: resultString.startIndex, to: fullRange.lowerBound)
            let endOffset = resultString.distance(from: resultString.startIndex, to: fullRange.upperBound)
            
            // Safety check
            guard startOffset >= 0, endOffset <= result.characters.count, startOffset < endOffset else { continue }
            
            let attrStart = result.index(result.startIndex, offsetByCharacters: startOffset)
            let attrEnd = result.index(result.startIndex, offsetByCharacters: endOffset)
            
            // Style as a tappable link
            result[attrStart..<attrEnd].foregroundColor = colors.primaryText
            result[attrStart..<attrEnd].font = AppFont.monoUI(size: 13, weight: .bold)
            result[attrStart..<attrEnd].underlineStyle = .single
            
            // Make it tappable via a custom URL
            let seconds = Int(timeInterval)
            if let url = URL(string: "trace://citation/\(seconds)") {
                result[attrStart..<attrEnd].link = url
            }
        }
        
        return result
    }
    
    private func parseTimeString(_ time: String) -> TimeInterval? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: return TimeInterval(parts[0] * 60 + parts[1])
        case 3: return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
        default: return nil
        }
    }

    // MARK: - Citation Navigation

    private func navigateToCitation(_ citation: TimestampCitation) {
        guard let segmentIndex = recording.segmentIndex(at: citation.timeInterval) else { return }
        dismiss()
        // Small delay to let the sheet dismiss before navigating
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onNavigateToSegment?(segmentIndex)
        }
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(colors.secondaryText)
                        .frame(width: 7, height: 7)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.2),
                            value: isLoading
                        )
                        .scaleEffect(isLoading ? 1 : 0.5)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(colors.selection)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Spacer()
        }
    }

    // MARK: - Error

    private func errorBubble(_ error: String) -> some View {
        HStack {
            Text(error)
                .font(AppFont.mono(size: 12))
                .foregroundStyle(.red.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(L10n.askAboutRecording, text: $inputText, axis: .vertical)
                .font(AppFont.mono(size: 14))
                .foregroundStyle(colors.primaryText)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(colors.inputField)
                .clipShape(RoundedRectangle(cornerRadius: AppLayout.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppLayout.inputRadius)
                        .stroke(colors.glassBorder, lineWidth: 0.5)
                )
                .focused($isInputFocused)
                .onSubmit { sendMessage() }

            if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(colors.primaryText)
                }
                .disabled(isLoading)
                .opacity(isLoading ? 0.4 : 1)
            }
        }
        .padding(.horizontal, AppLayout.horizontalPadding)
        .padding(.vertical, 12)
        .glassCard(radius: 18, padding: 0)
        .padding(.horizontal, AppLayout.horizontalPadding)
        .padding(.bottom, 16)
        .shadow(color: colors.glassShadow, radius: 10, y: 4)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        errorMessage = nil
        isLoading = true

        Task {
            do {
                let response = try await ChatService.shared.sendMessage(
                    userMessage: text,
                    conversationHistory: Array(messages.dropLast()), // exclude the message we just added
                    transcript: recording.transcriptFullText ?? "",
                    segments: recording.transcriptSegments ?? [],
                    speakerNames: recording.speakerNames
                )
                let modelMessage = ChatMessage(role: .model, content: response)
                messages.append(modelMessage)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) {
            if isLoading {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Flow Layout (kept for potential reuse)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

// MARK: - AppFont UIFont helper

extension AppFont {
    static func monoUI(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

