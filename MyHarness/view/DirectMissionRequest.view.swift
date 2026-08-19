import SwiftUI

@MainActor
struct DirectMissionRequestSheet: View {
    private enum RequestKind: String, CaseIterable, Identifiable {
        case research
        case message

        var id: String { rawValue }
        var label: String { self == .research ? "調査" : "文案" }
    }

    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState

    @State private var requestKind: RequestKind = .research
    @State private var instruction = ""
    @State private var researchChannel = "x"
    @State private var sampleTarget = 20
    @State private var inclusionCriteria = ""
    @State private var exclusionCriteria = ""
    @State private var messageChannel = "x_post"
    @State private var messagePurpose = "question"
    @State private var audience = "小規模大家"
    @State private var sourceURL = ""
    @State private var sourceText = ""
    @State private var tone = "丁寧で簡潔"
    @State private var messageConstraints = ""
    @State private var clientRequestId = UUID().uuidString.lowercased()
    @State private var lastSubmissionSignature: String?
    @State private var errorMessage: String?
    @State private var showsDetails = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("依頼の種類", selection: $requestKind) {
                        ForEach(RequestKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(requestKind == .research ? "調べてほしいこと" : "作ってほしい文案") {
                    TextEditor(text: $instruction)
                        .frame(minHeight: 120)
                        .accessibilityLabel(requestKind == .research ? "調べてほしいこと" : "作ってほしい文案")
                    HStack {
                        Text(requestKind == .research ? "Grokへ渡す依頼本文" : "Codexへ渡す依頼本文")
                        Spacer()
                        Text("\(instructionUTF16Length.formatted()) / \(instructionMaxUTF16Length.formatted())文字")
                            .foregroundStyle(isInstructionTooLong ? .red : .secondary)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .accessibilityElement(children: .combine)
                }

                if requestKind == .research {
                    researchFields
                } else {
                    messageFields
                }

                Section {
                    Label(
                        requestKind == .research
                            ? "公開情報の調査だけを行います。返信やDMは送りません。"
                            : "成果物は下書きです。採用しても投稿・返信・メール・DMは送信されません。",
                        systemImage: "hand.raised"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("エージェントに依頼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    submit()
                } label: {
                    HStack {
                        if state.isCreatingDirectMission {
                            ProgressView()
                        }
                        Text(requestKind == .research ? "調査を依頼" : "文案作成を依頼")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || state.isCreatingDirectMission)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .alert("依頼できませんでした", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var researchFields: some View {
        Group {
            Section("調査先") {
                Picker("調査先", selection: $researchChannel) {
                    Text("X").tag("x")
                    Text("TikTok").tag("tiktok")
                }
                .pickerStyle(.segmented)
            }

            Section {
                DisclosureGroup("詳細設定", isExpanded: $showsDetails) {
                    Stepper("目標件数  \(sampleTarget)件", value: $sampleTarget, in: 1...50)
                    criteriaEditor(
                        title: "含める条件",
                        text: $inclusionCriteria,
                        hint: "1行に1条件"
                    )
                    criteriaEditor(
                        title: "除外する条件",
                        text: $exclusionCriteria,
                        hint: "1行に1条件"
                    )
                }
            }
        }
    }

    private var messageFields: some View {
        Group {
            Section("文案の種類") {
                Picker("チャンネル", selection: $messageChannel) {
                    Text("X投稿").tag("x_post")
                    Text("X返信").tag("x_reply")
                    Text("メール").tag("email")
                    Text("DM").tag("direct_message")
                }
                .pickerStyle(.menu)

                Picker("目的", selection: $messagePurpose) {
                    Text("質問").tag("question")
                    Text("依頼").tag("outreach")
                    Text("お知らせ").tag("announcement")
                    Text("フォローアップ").tag("follow_up")
                }
                .pickerStyle(.menu)

                TextField("想定する相手", text: $audience)
            }

            if messageChannel == "x_reply" {
                Section("返信元") {
                    TextField("元投稿URL", text: $sourceURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextEditor(text: $sourceText)
                        .frame(minHeight: 80)
                        .accessibilityLabel("元投稿本文")
                    Text("URLか本文のどちらかを入力してください")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                DisclosureGroup("詳細設定", isExpanded: $showsDetails) {
                    Picker("文体", selection: $tone) {
                        Text("丁寧で簡潔").tag("丁寧で簡潔")
                        Text("親しみやすく簡潔").tag("親しみやすく簡潔")
                        Text("事務的で明確").tag("事務的で明確")
                    }
                    .pickerStyle(.menu)
                    criteriaEditor(
                        title: "追加の制約",
                        text: $messageConstraints,
                        hint: "1行に1条件"
                    )
                }
            }
        }
    }

    private func criteriaEditor(
        title: String,
        text: Binding<String>,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
            TextEditor(text: text)
                .frame(minHeight: 72)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(hint)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var canSubmit: Bool {
        guard !cleaned(instruction).isEmpty else { return false }
        guard !isInstructionTooLong else { return false }
        if requestKind == .message {
            guard !cleaned(audience).isEmpty else { return false }
            if messageChannel == "x_reply" {
                return !cleaned(sourceURL).isEmpty || !cleaned(sourceText).isEmpty
            }
        }
        return true
    }

    private var instructionMaxUTF16Length: Int {
        requestKind == .research
            ? VentureDirectMissionInputPolicy.researchInstructionMaxUTF16Length
            : VentureDirectMissionInputPolicy.messageInstructionMaxUTF16Length
    }

    private var instructionUTF16Length: Int {
        instruction.utf16.count
    }

    private var isInstructionTooLong: Bool {
        instructionUTF16Length > instructionMaxUTF16Length
    }

    private var requestSignature: String {
        [
            requestKind.rawValue,
            cleaned(instruction),
            researchChannel,
            String(sampleTarget),
            inclusionCriteria,
            exclusionCriteria,
            messageChannel,
            messagePurpose,
            cleaned(audience),
            cleaned(sourceURL),
            cleaned(sourceText),
            tone,
            messageConstraints,
        ].joined(separator: "\u{1f}")
    }

    private func submit() {
        let signature = requestSignature
        if let lastSubmissionSignature, lastSubmissionSignature != signature {
            clientRequestId = UUID().uuidString.lowercased()
        }
        lastSubmissionSignature = signature
        let request = directRequest()
        Task {
            do {
                _ = try await state.createDirectMission(request)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func directRequest() -> VentureDirectMissionRequest {
        switch requestKind {
        case .research:
            return .research(VentureDirectResearchMissionRequest(
                clientRequestId: clientRequestId,
                instruction: cleaned(instruction),
                channel: researchChannel,
                targetSegment: .init(kind: "strategy_primary"),
                sampleTarget: sampleTarget,
                inclusionCriteria: lines(inclusionCriteria),
                exclusionCriteria: lines(exclusionCriteria),
                relatedOpportunityId: nil,
                relatedHypothesisId: nil
            ))
        case .message:
            return .message(VentureDirectMessageMissionRequest(
                clientRequestId: clientRequestId,
                instruction: cleaned(instruction),
                channel: messageChannel,
                purpose: messagePurpose,
                audience: cleaned(audience),
                sourceUrl: cleaned(sourceURL).isEmpty ? nil : cleaned(sourceURL),
                sourceText: cleaned(sourceText).isEmpty ? nil : cleaned(sourceText),
                tone: tone,
                constraints: lines(messageConstraints)
            ))
        }
    }

    private func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lines(_ value: String) -> [String] {
        var seen = Set<String>()
        return value
            .components(separatedBy: .newlines)
            .map(cleaned)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
