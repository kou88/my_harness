import Foundation

enum ProductOpsMarkdownFormatter {
    static func proposal(_ detail: VentureProposalDetail) -> String {
        var document = ProductOpsMarkdownDocument(title: detail.proposal.title)

        document.section("今決めること", text: detail.proposal.decisionAgenda.question)
        document.section("現在の見立て", text: detail.proposal.decisionAgenda.currentPosition)
        if let alternative = detail.proposal.decisionAgenda.alternativeExplanation {
            document.section("反対の可能性", text: alternative)
        }
        document.section("判断を止めている未知", text: detail.proposal.decisionAgenda.primaryUnknown)
        document.section("今回の行動", text: detail.proposal.summary)
        document.keyValues([
            ("対象", detail.proposal.actionSpec.target),
            ("方法", detail.proposal.actionSpec.method),
            ("量", detail.proposal.actionSpec.quantity),
            ("期限", detail.proposal.actionSpec.timebox),
            ("成果物", detail.proposal.actionSpec.deliverableKind),
        ])
        document.section("期待する観測", text: detail.proposal.expectedObservation)
        document.heading("結果別の判断", level: 2)
        document.keyValues([
            ("進む", detail.proposal.decisionRule.proceedWhen),
            ("止める", detail.proposal.decisionRule.stopWhen),
            ("見直す", detail.proposal.decisionRule.reconsiderWhen),
        ])
        document.listSection(
            "根拠の参照",
            items: detail.proposal.groundingRefs.map { "\($0.kind):\($0.id) [\($0.relation)]" }
        )
        document.listSection("推奨する成功条件", items: detail.proposal.suggestedSuccessCriteria)
        document.listSection("推奨する停止条件", items: detail.proposal.suggestedStopConditions)

        document.heading("Opportunity", level: 2)
        document.section("課題", text: detail.opportunity.problemStatement, level: 3)
        document.section("望ましい結果", text: detail.opportunity.desiredOutcomeStatement, level: 3)
        document.section("根拠の要約", text: detail.opportunity.evidenceSummary, level: 3)
        document.listSection("未確認事項", items: detail.opportunity.unknowns, level: 3)
        document.keyValues([
            ("状態", detail.opportunity.status),
            ("確信度", detail.opportunity.confidence),
            ("Opportunity ID", detail.opportunity.id),
        ])

        document.heading("検証する仮説", level: 2)
        document.paragraph(detail.hypothesis.statement)
        document.listSection("仮説の未確認事項", items: detail.hypothesis.unknowns, level: 3)
        document.keyValues([
            ("状態", detail.hypothesis.status),
            ("重要度", String(detail.hypothesis.criticality)),
            ("確信度", String(detail.hypothesis.confidence)),
            ("Hypothesis ID", detail.hypothesis.id),
        ])

        if let change = detail.proposal.decisionFrameChange {
            document.heading("判断軸の変更", level: 2)
            document.paragraph(change.rationale)
            let currentByKey = Dictionary(uniqueKeysWithValues: change.currentLenses.map { ($0.key, $0) })
            let changes = change.proposedLenses.compactMap { proposed -> String? in
                guard let current = currentByKey[proposed.key], current.weight != proposed.weight else { return nil }
                return "\(proposed.label): \(percentage(current.weight)) -> \(percentage(proposed.weight))"
            }
            document.listSection("変更内容", items: changes, level: 3)
            document.keyValues([
                ("変更前Version", change.baseDecisionFrameVersionId),
                ("変更後Version", change.proposedDecisionFrameVersionId),
            ])
        }

        document.heading("プロダクト方針", level: 2)
        document.section("Mission", text: detail.strategy.mission, level: 3)
        document.listSection(
            "対象ユーザー",
            items: detail.strategy.targetSegments.map { segment in
                segment.description.isEmpty ? segment.label : "\(segment.label): \(segment.description)"
            },
            level: 3
        )
        document.listSection("望ましい結果", items: detail.strategy.desiredOutcomes, level: 3)
        document.listSection("重点領域", items: detail.strategy.focusAreas, level: 3)
        document.listSection("対象外", items: detail.strategy.exclusions, level: 3)
        document.keyValues([("Strategy Version ID", detail.strategy.id)])

        document.heading("Decision Frame", level: 2)
        document.keyValues([
            ("Stage", detail.decisionFrame.stage),
            ("最大推薦件数", String(detail.decisionFrame.maxRecommendations)),
            ("Decision Frame Version ID", detail.decisionFrame.id),
        ])

        if !detail.learnings.isEmpty {
            document.heading("過去のLearning", level: 2)
            for learning in detail.learnings.sorted(by: { $0.createdAt < $1.createdAt }) {
                document.heading(dateText(learning.createdAt), level: 3)
                document.paragraph(learning.summary)
                document.keyValues([("Learning ID", learning.id)])
            }
        }

        document.heading("評価", level: 2)
        document.keyValues([
            ("順位", String(detail.assessment.rank)),
            ("最終評価", decimal(detail.assessment.finalScore)),
            ("事業評価", decimal(detail.assessment.businessScore)),
            ("内容評価", decimal(detail.assessment.substanceScore)),
            ("評価理由", detail.assessment.whyNow),
            ("評価方式", detail.assessment.algorithmKey),
            ("評価日時", dateText(detail.assessment.assessedAt)),
        ])
        document.listSection(
            "評価軸",
            items: detail.assessment.scores.keys.sorted().compactMap { key in
                guard let score = detail.assessment.scores[key] else { return nil }
                return "\(key): \(decimal(score))"
            },
            level: 3
        )

        document.heading("生成情報", level: 2)
        document.keyValues([
            ("Recommendation Set ID", detail.recommendation.recommendationSetId),
            ("生成日時", dateText(detail.recommendation.generatedAt)),
            ("生成Policy", detail.recommendation.metadata.draftingPolicyKey),
            ("Prompt Version", detail.recommendation.metadata.draftingPromptVersion),
            ("生成モデル", detail.recommendation.metadata.draftingModel),
            ("Rating Policy", detail.recommendation.metadata.ratingPolicyKey),
            ("Rating Version", detail.recommendation.metadata.ratingAlgorithmVersion),
        ])

        document.heading("Proposal情報", level: 2)
        document.keyValues([
            ("Proposal ID", detail.proposal.proposalId),
            ("状態", detail.proposal.status),
            ("Version", String(detail.proposal.version)),
            ("Action", "\(detail.proposal.actionKind) / \(detail.proposal.actionChannel)"),
            ("承認リスク", detail.proposal.approvalRisk),
            ("Intent", detail.proposal.intentKind),
            ("Bet", detail.proposal.betKind ?? "なし"),
            ("承認時の効果", detail.proposal.approvalEffect),
        ])

        return document.rendered
    }

    static func mission(_ detail: VentureMissionDetail) -> String {
        let mission = detail.mission
        var document = ProductOpsMarkdownDocument(title: mission.primaryDeliverableSpec.title)

        document.section("目的", text: detail.displayObjective)
        if let approvedInstruction = detail.approvedInstruction {
            document.section("承認済み依頼", text: approvedInstruction)
        }
        let description = mission.primaryDeliverableSpec.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty,
           description != detail.displayObjective,
           description != detail.approvedInstruction {
            document.section("成果物", text: description)
        }
        document.listSection("必要なセクション", items: mission.primaryDeliverableSpec.requiredSections)
        document.listSection("合格条件", items: mission.primaryDeliverableSpec.acceptanceCriteria)

        if !mission.supportingDeliverableSpecs.isEmpty {
            document.heading("補助成果物", level: 2)
            for spec in mission.supportingDeliverableSpecs {
                document.heading(spec.title, level: 3)
                document.paragraph(spec.description)
                document.listSection("必要なセクション", items: spec.requiredSections, level: 4)
                document.listSection("合格条件", items: spec.acceptanceCriteria, level: 4)
            }
        }

        document.heading("Mission情報", level: 2)
        document.keyValues([
            ("状態", missionStatusLabel(mission.status)),
            ("Capability", mission.capability),
            ("成果物種類", mission.primaryDeliverableSpec.kind),
            ("Review Policy", mission.reviewPolicy),
            ("Version", String(mission.version)),
            ("Mission ID", mission.id),
            ("Venture ID", mission.ventureId),
            ("Source Proposal ID", mission.sourceProposalId ?? "なし"),
            ("Source Bet ID", mission.sourceBetId ?? "なし"),
            ("作成日時", dateText(mission.createdAt)),
            ("更新日時", dateText(mission.updatedAt)),
        ])

        document.heading("副作用と承認境界", level: 2)
        document.keyValues([
            ("外部送信", yesNo(mission.sideEffectPolicy.externalSend)),
            ("Repository変更", yesNo(mission.sideEffectPolicy.repositoryWrite)),
            ("データ変更", yesNo(mission.sideEffectPolicy.dataMutation)),
            ("本番変更", yesNo(mission.sideEffectPolicy.productionChange)),
            ("採用時の境界", actionBoundary(mission.primaryDeliverableSpec.kind)),
        ])

        let sortedDeliverables = detail.deliverables.sorted { $0.createdAt < $1.createdAt }
        if sortedDeliverables.isEmpty {
            document.heading("成果物", level: 2)
            if let error = detail.currentAttempt?.error, !error.isEmpty {
                document.paragraph("成果物は作成されませんでした。\n\nエラー: \(error)")
            } else {
                document.paragraph("現在の実行結果を待っています。")
            }
        } else {
            document.heading("成果物", level: 2)
            for deliverable in sortedDeliverables {
                append(deliverable: deliverable, to: &document)
            }
        }

        if let verification = detail.verification {
            document.heading("AIレビュー", level: 2)
            document.keyValues([
                ("状態", missionStatusLabel(verification.status)),
                ("要約", verification.summary),
                ("Source Deliverable ID", verification.sourceDeliverableId),
            ])
            if let report = verification.report {
                append(verificationReport: report, to: &document, headingLevel: 3)
            } else if let error = verification.reportDecodingError {
                document.section("読み込みエラー", text: error, level: 3)
            }
        }

        if !detail.revisionReviews.isEmpty {
            document.heading("修正指示", level: 2)
            for review in detail.revisionReviews {
                guard let feedback = review.feedback else { continue }
                document.bullet("\(feedback)（\(dateText(review.reviewedAt))）")
            }
            document.blankLine()
        }

        if !detail.attempts.isEmpty {
            document.heading("実行履歴", level: 2)
            for attempt in detail.attempts.sorted(by: { $0.attemptNumber < $1.attemptNumber }) {
                document.heading("Attempt \(attempt.attemptNumber)", level: 3)
                document.keyValues([
                    ("状態", attemptStatusLabel(attempt.status)),
                    ("Executor", attempt.executorType),
                    ("Schema", "\(attempt.instructionSnapshot.schemaKey) v\(attempt.instructionSnapshot.schemaVersion)"),
                    ("Context Snapshot Hash", attempt.instructionSnapshot.contextSnapshotHash),
                    ("Agent Task ID", attempt.agentTaskId ?? "なし"),
                    ("Executor Session ID", attempt.executorSessionId ?? "なし"),
                    ("Executor Turn ID", attempt.executorTurnId ?? "なし"),
                    ("作成日時", dateText(attempt.createdAt)),
                    ("更新日時", dateText(attempt.updatedAt)),
                ])
                document.listSection("参照", items: attempt.instructionSnapshot.referenceIds, level: 4)
                if let error = attempt.error, !error.isEmpty {
                    document.section("エラー", text: error, level: 4)
                }

                let reviews = detail.reviews
                    .filter { $0.attemptId == attempt.id }
                    .sorted { $0.reviewedAt < $1.reviewedAt }
                if !reviews.isEmpty {
                    document.heading("レビュー", level: 4)
                    for review in reviews {
                        let feedback = review.decision == "revision_requested"
                            ? "（内容は「修正指示」に記載）"
                            : review.feedback.map { ": \($0)" } ?? ""
                        document.bullet("\(reviewDecisionLabel(review.decision))\(feedback)（\(dateText(review.reviewedAt))）")
                    }
                }
            }
        }

        if !detail.availableActions.isEmpty {
            document.listSection("利用可能な操作", items: detail.availableActions.map(actionLabel))
        }

        return document.rendered
    }

    static func monitoringAlert(_ item: VentureMonitoringAlertItem) -> String {
        let payload = item.alertPayload ?? VentureAlertDeliverable(
            severity: item.alert.severity,
            detectedIssue: item.alert.detectedIssue,
            recommendedAction: item.alert.recommendedAction,
            entityRefs: item.alert.entityRefs
        )
        var document = ProductOpsMarkdownDocument(title: payload.detectedIssue)
        document.section("検知した問題", text: payload.detectedIssue)
        document.section("推奨対応", text: payload.recommendedAction)
        document.listSection("関連項目", items: payload.entityRefs)
        if let deliverable = item.alertDeliverable {
            document.section("要約", text: deliverable.displaySummary)
        }
        document.heading("アラート情報", level: 2)
        document.keyValues([
            ("重要度", payload.severity),
            ("状態", item.alert.status),
            ("Alert ID", item.alert.id),
            ("Mission ID", item.alert.missionId),
            ("Deliverable ID", item.alert.deliverableId),
            ("作成日時", dateText(item.alert.createdAt)),
            ("更新日時", dateText(item.alert.updatedAt)),
        ])
        return document.rendered
    }

    private static func append(deliverable: VentureDeliverable, to document: inout ProductOpsMarkdownDocument) {
        document.heading(deliverable.title, level: 3)
        document.keyValues([
            ("種類", deliverable.kind),
            ("要約", deliverable.displaySummary),
            ("Deliverable ID", deliverable.id),
            ("Attempt ID", deliverable.attemptId),
            ("Revision Of", deliverable.revisionOfDeliverableId ?? "なし"),
            ("作成日時", dateText(deliverable.createdAt)),
        ])

        do {
            switch try deliverable.decodePayload() {
            case .decisionBrief(let value):
                document.section("決めたいこと", text: value.decisionQuestion, level: 4)
                document.section("おすすめ", text: value.recommendation, level: 4)
                document.listSection("理由", items: value.reasons, level: 4)
                document.listSection("反対材料", items: value.contraryEvidence, level: 4)
                document.listSection("リスク", items: value.risks, level: 4)
                document.listSection("未知", items: value.unknowns, level: 4)
                document.listSection("次の操作", items: value.nextOperations, level: 4)
            case .productChange(let value):
                document.listSection("変更内容", items: value.changedBehavior, level: 4)
                document.section("ユーザーへの影響", text: value.userVisibleImpact, level: 4)
                document.listSection("変更Repository", items: value.changedRepositories, level: 4)
                document.listSection("Draft PR", items: value.pullRequests, level: 4)
                document.listSection(
                    "検証結果",
                    items: value.checks.map { "[\($0.status)] \($0.name): \($0.detail)" },
                    level: 4
                )
                document.listSection("未解決事項", items: value.unresolvedIssues, level: 4)
            case .researchReport(let value):
                if let artifactMarkdown = value.artifactMarkdown {
                    document.section("成果物本文", text: artifactMarkdown, level: 4)
                }
                document.section("調査テーマ", text: value.researchQuestion, level: 4)
                document.listSection("結論", items: value.conclusionItems.map(\.text), level: 4)
                document.listSection("重要な発見", items: value.findingItems.map(\.text), level: 4)
                document.listSection("支持する根拠", items: value.supportingItems.map(\.text), level: 4)
                document.listSection("反例", items: value.contradictingItems.map(\.text), level: 4)
                document.listSection(
                    "情報源",
                    items: value.externalSources.map(\.url),
                    level: 4
                )
                document.listSection(
                    "まだ分からないこと",
                    items: value.items.filter { $0.kind == .unknown }.map(\.text),
                    level: 4
                )
                document.listSection(
                    "次に確認すること",
                    items: value.items.filter { $0.kind == .nextQuestion }.map(\.text),
                    level: 4
                )
                if let executionLog = value.executionLog {
                    document.heading("実行ログ", level: 4)
                    if let grokExecution = value.grokExecution {
                        document.keyValues([
                            (
                                "要求設定",
                                "\(grokExecution.requested.surface) / \(grokExecution.requested.mode) / \(grokExecution.requested.model) / \(grokExecution.requested.reasoning)"
                            ),
                            (
                                "適用設定",
                                "\(grokExecution.applied.surface) / \(grokExecution.applied.modeLabel) / \(grokExecution.applied.modelLabel ?? "モデル表示なし") / \(grokExecution.applied.reasoningLabel ?? grokExecution.applied.reasoningAppliedBy)"
                            ),
                        ])
                    }
                    document.keyValues([
                        ("確認件数", String(executionLog.checkedCount)),
                        ("採用件数", String(executionLog.selectedCount)),
                        ("除外件数", String(executionLog.excludedCount)),
                    ])
                    document.listSection("検索語", items: executionLog.queries, level: 5)
                    document.listSection("制約・不足", items: executionLog.limitations, level: 5)
                }
            case .message(let value):
                document.keyValues([
                    ("チャネル", value.channel),
                    ("目的", value.purpose),
                    ("件名", value.subject ?? "なし"),
                ])
                document.listSection("送信候補", items: value.candidateRecipients, level: 4)
                document.section("本文", text: value.body, level: 4)
            case .verificationReport(let value):
                append(verificationReport: value, to: &document, headingLevel: 4)
            case .knowledgeChange(let value):
                document.keyValues([
                    ("基準Strategy", value.baseStrategyVersionId),
                    ("基準Decision Frame", value.baseDecisionFrameVersionId),
                    ("リスク", value.risk),
                ])
                document.section("変更理由", text: value.rationale, level: 4)
                document.section("今後の影響", text: value.expectedImpact, level: 4)
                if let strategy = value.nextStrategy {
                    document.section("変更後の目的", text: strategy.mission, level: 4)
                    document.listSection(
                        "変更後の対象顧客",
                        items: strategy.targetSegments.map { "\($0.label): \($0.description)" },
                        level: 4
                    )
                    document.listSection("変更後の期待成果", items: strategy.desiredOutcomes, level: 4)
                    document.listSection("変更後の商業仮説", items: strategy.commercialHypotheses, level: 4)
                    document.listSection("変更後のFocus", items: strategy.focusAreas, level: 4)
                    document.listSection("変更後の除外事項", items: strategy.exclusions, level: 4)
                    document.listSection("変更後の研究制約", items: strategy.researchGuardrails, level: 4)
                    document.listSection("変更後の実装・提供制約", items: strategy.deliveryGuardrails, level: 4)
                }
                if let frame = value.nextDecisionFrame {
                    document.keyValues([
                        ("変更後の事業段階", frame.stage),
                        ("最大推薦数", String(frame.maxRecommendations)),
                    ])
                    document.listSection("変更後の目的", items: frame.objectiveIds, level: 4)
                    document.listSection(
                        "変更後の評価基準",
                        items: frame.lenses.map { "\($0.label)（\($0.weight.formatted())）: \($0.description)" },
                        level: 4
                    )
                    document.listSection(
                        "変更後のHard Gate",
                        items: frame.hardGates.map { "\($0.label): \($0.description)" },
                        level: 4
                    )
                }
                document.listSection("反対材料", items: value.contraryEvidence, level: 4)
                document.listSection(
                    "根拠",
                    items: value.sourceRefs.map { "\($0.kind) / \($0.id) / \($0.relation)" },
                    level: 4
                )
            case .alert(let value):
                document.keyValues([("重要度", value.severity)])
                document.section("検知した問題", text: value.detectedIssue, level: 4)
                document.section("推奨対応", text: value.recommendedAction, level: 4)
                document.listSection("関連項目", items: value.entityRefs, level: 4)
            }
        } catch {
            document.section("成果物の読み込みエラー", text: error.localizedDescription, level: 4)
        }
    }

    private static func append(
        verificationReport: VentureVerificationReportDeliverable,
        to document: inout ProductOpsMarkdownDocument,
        headingLevel: Int
    ) {
        document.keyValues([("判定", verificationReport.verdict)])
        document.listSection(
            "確認結果",
            items: verificationReport.checkedCriteria.map {
                "[\($0.status)] \($0.criterion): \($0.detail)"
            },
            level: headingLevel
        )
        document.listSection("リスク", items: verificationReport.risks, level: headingLevel)
        document.listSection("必要な対応", items: verificationReport.requiredFollowUps, level: headingLevel)
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func percentage(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "あり" : "なし"
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func missionStatusLabel(_ status: String) -> String {
        switch status {
        case "queued": return "待機中"
        case "dispatching": return "依頼中"
        case "running": return "実行中"
        case "awaiting_review": return "結果確認"
        case "completed": return "採用済み"
        case "failed": return "失敗"
        case "canceled": return "キャンセル"
        case "rejected": return "却下"
        default: return status
        }
    }

    private static func attemptStatusLabel(_ status: String) -> String {
        switch status {
        case "queued": return "待機中"
        case "dispatching": return "依頼中"
        case "running": return "実行中"
        case "succeeded": return "実行成功"
        case "failed": return "失敗"
        case "canceled": return "中断"
        default: return status
        }
    }

    private static func reviewDecisionLabel(_ decision: String) -> String {
        switch decision {
        case "adopted": return "採用"
        case "revision_requested": return "修正依頼"
        case "rejected": return "却下"
        default: return decision
        }
    }

    private static func actionLabel(_ action: String) -> String {
        switch action {
        case "adopt": return "採用する"
        case "request_revision": return "修正して再実行"
        case "reject": return "却下して終了"
        case "retry": return "再実行"
        case "cancel": return "キャンセル"
        default: return action
        }
    }

    private static func actionBoundary(_ kind: String) -> String {
        switch kind {
        case "message": return "採用しても外部へ送信しません。送信には別の承認が必要です。"
        case "product_change": return "採用してもPRマージや本番反映は行いません。"
        case "knowledge_change": return "採用すると事業方針の新しいVersionを作成します。外部送信や本番変更は行いません。"
        default: return "採用後の副作用はMissionの承認境界に従います。"
        }
    }
}

private struct ProductOpsMarkdownDocument {
    private var lines: [String]

    init(title: String) {
        lines = ["# \(Self.cleaned(title))", ""]
    }

    mutating func heading(_ title: String, level: Int) {
        let value = Self.cleaned(title)
        guard !value.isEmpty else { return }
        lines.append(String(repeating: "#", count: max(1, min(level, 6))) + " " + value)
        lines.append("")
    }

    mutating func paragraph(_ text: String) {
        let value = Self.cleaned(text)
        guard !value.isEmpty else { return }
        lines.append(value)
        lines.append("")
    }

    mutating func section(_ title: String, text: String, level: Int = 2) {
        let value = Self.cleaned(text)
        guard !value.isEmpty else { return }
        heading(title, level: level)
        paragraph(value)
    }

    mutating func listSection(_ title: String, items: [String], level: Int = 2) {
        let values = items.map(Self.cleaned).filter { !$0.isEmpty }
        guard !values.isEmpty else { return }
        heading(title, level: level)
        for value in values {
            bullet(value)
        }
        lines.append("")
    }

    mutating func keyValues(_ values: [(String, String)]) {
        let nonempty = values.compactMap { label, value -> (String, String)? in
            let normalized = Self.cleaned(value)
            return normalized.isEmpty ? nil : (label, normalized)
        }
        guard !nonempty.isEmpty else { return }
        for (label, value) in nonempty {
            bullet("**\(label)**: \(value)")
        }
        lines.append("")
    }

    mutating func bullet(_ value: String) {
        let parts = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first else { return }
        lines.append("- \(first)")
        lines.append(contentsOf: parts.dropFirst().map { "  \($0)" })
    }

    mutating func blankLine() {
        if lines.last != "" {
            lines.append("")
        }
    }

    mutating func codeSection(_ title: String, code: String, language: String, level: Int) {
        let value = Self.cleaned(code)
        guard !value.isEmpty else { return }
        heading(title, level: level)
        lines.append("```\(language)")
        lines.append(value)
        lines.append("```")
        lines.append("")
    }

    var rendered: String {
        lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n"
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
