import SwiftUI

struct AskAudioView: View {
    let recording: Recording
    var onNavigateToSegment: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
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
                        }
                        .padding(.horizontal, AppLayout.horizontalPadding)
                        .padding(.vertical, 16)
                    }
                    .onChange(of: messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: isLoading) { _, loading in
                        if loading { scrollToBottom(proxy: proxy) }
                    }
                }

                // Input bar
                inputBar
            }
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.askYourAudio)
                        .font(AppFont.mono(size: 13, weight: .semibold))
                        .kerning(1.5)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.done)
                            .font(AppFont.mono(size: 14))
                            .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // Intercept citation taps via custom URL scheme
            .environment(\.openURL, OpenURLAction { url in
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
            })
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.3))

            Text(L10n.askAnything)
                .font(AppFont.mono(size: 16, weight: .bold))
                .kerning(1.5)
                .foregroundStyle(.white.opacity(0.6))

            Text(L10n.askAudioHelp)
                .font(AppFont.mono(size: 12))
                .foregroundStyle(.white.opacity(0.3))
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
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: AppLayout.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppLayout.inputRadius)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
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
        return Text(styledContent(message.content, isUser: isUser))
            .font(AppFont.mono(size: 14, weight: .regular))
            .lineSpacing(5)
            .tint(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isUser ? Color.white.opacity(0.15) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(isUser ? 0.12 : 0.06), lineWidth: 0.5)
            )
    }

    private func styledContent(_ text: String, isUser: Bool) -> AttributedString {
        // For model messages, parse markdown (bold, italic, lists, etc.)
        var attributed: AttributedString
        if !isUser, let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            attributed = parsed
        } else {
            attributed = AttributedString(text)
        }

        // Apply base styling
        attributed.foregroundColor = isUser ? .white : .white.opacity(0.85)

        // Make [MM:SS] citations tappable inline links in model messages
        if !isUser {
            let citations = ChatService.parseCitations(from: text)
            for citation in citations.reversed() {
                let startOffset = text.distance(from: text.startIndex, to: citation.range.lowerBound)
                let endOffset = text.distance(from: text.startIndex, to: citation.range.upperBound)
                // Safety: ensure offsets are within attributed string bounds
                let attrLength = attributed.characters.count
                guard startOffset >= 0, endOffset <= attrLength, startOffset < endOffset else { continue }
                let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: startOffset)
                let attrEnd = attributed.index(attributed.startIndex, offsetByCharacters: endOffset)

                // Style as a tappable link
                attributed[attrStart..<attrEnd].foregroundColor = .white
                attributed[attrStart..<attrEnd].font = AppFont.monoUI(size: 13, weight: .bold)
                attributed[attrStart..<attrEnd].underlineStyle = .single

                // Make it tappable via a custom URL
                let seconds = Int(citation.timeInterval)
                if let url = URL(string: "trace://citation/\(seconds)") {
                    attributed[attrStart..<attrEnd].link = url
                }
            }
        }
        return attributed
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
                        .fill(Color.white.opacity(0.4))
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
            .background(Color.white.opacity(0.06))
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
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.inputField)
                .clipShape(RoundedRectangle(cornerRadius: AppLayout.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppLayout.inputRadius)
                        .stroke(Color.glassBorder, lineWidth: 0.5)
                )
                .focused($isInputFocused)
                .onSubmit { sendMessage() }

            if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
                .disabled(isLoading)
                .opacity(isLoading ? 0.4 : 1)
            }
        }
        .padding(.horizontal, AppLayout.horizontalPadding)
        .padding(.vertical, 12)
        .background(
            Color.black
                .overlay(Color.white.opacity(0.04))
                .ignoresSafeArea(edges: .bottom)
        )
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
