import Foundation
import Testing
@testable import MyHarnessProductOpsDomain

struct VenturePolicyContractTests {
    @Test
    func decodesVenturePolicyProjection() throws {
        let data = Data(policyJSON.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let policy = try decoder.decode(VenturePolicy.self, from: data)

        #expect(policy.ventureId == "landlord-saas")
        #expect(policy.policyText == "# 自由な事業方針")
        #expect(policy.policyTextVersion == 2)
        #expect(policy.strategyVersionId == "strategy-v2")
        #expect(policy.decisionFrameVersionId == "frame-v3")
        #expect(policy.targetSegments.first?.key == "small-landlord")
        #expect(policy.lenses.first?.weight == 40)
        #expect(policy.pendingPolicyChangeCount == 1)
        #expect(policy.policyChangeStatusCounts.awaitingReview == 1)
        #expect(policy.policyChangeStatusCounts.applyFailed == 1)
    }

    @Test
    func decodesStructuredPolicyRevisionDeliverable() throws {
        let metadata = try JSONDecoder().decode(ProductOpsMetadataValue.self, from: Data(policyRevisionJSON.utf8))

        let deliverable = try VentureKnowledgeChangeDeliverable(payload: metadata)

        #expect(deliverable.schemaVersion == 3)
        #expect(deliverable.nextStrategy?.focusAreas == ["入金の対象月割当"])
        #expect(deliverable.nextDecisionFrame?.stage == "validation")
        #expect(deliverable.nextStrategy?.commercialHypotheses == ["月額3,000円の支払意思を検証する"])
        #expect(deliverable.sourceRefs.first?.kind == "learning")
    }

    @Test
    func rejectsLegacyKnowledgeChangePayload() throws {
        let data = Data(#"{"currentState":"旧方針","proposedState":"新方針","reason":"学習","sourceIds":["learning-1"]}"#.utf8)
        let metadata = try JSONDecoder().decode(ProductOpsMetadataValue.self, from: data)

        #expect(throws: VentureDeliverablePayloadDecodingError.self) {
            try VentureKnowledgeChangeDeliverable(payload: metadata)
        }
    }

    @Test
    func decodesPolicyRevisionDiffAndImpactPreview() throws {
        let revision = try JSONDecoder().decode(
            VenturePolicyRevisionDetail.self,
            from: Data(policyRevisionDetailJSON.utf8)
        )

        #expect(revision.reviewDeepLink == "myharness://knowledge-change-missions/mission-1")
        #expect(revision.policyTextDiff.hunks.first?.oldStart == 1)
        #expect(revision.policyTextDiff.hunks.first?.lines.count == 2)
        #expect(revision.structuredChanges.first?.before == ["日々の記録"])
        #expect(revision.structuredChanges.first?.added == ["月次確認"])
        #expect(revision.impactPreview.staleProposalCount == 2)
        #expect(revision.impactPreview.supersededAgendaItemCount == 1)
        #expect(revision.reviewStatus == "awaiting_review")
        #expect(revision.applicationStatus == "not_requested")
    }

    @Test
    func decodesResearchClipWithSourceState() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let item = try decoder.decode(
            VentureResearchClipListItem.self,
            from: Data(researchClipJSON.utf8)
        )

        #expect(item.clip.itemKind == "supporting_evidence")
        #expect(item.clip.relation == "supports")
        #expect(item.clip.sourceSnapshot.type == "x_post")
        #expect(item.sourceState.sourceMissionId == "mission-1")
        #expect(item.sourceState.sourceReviewDecision == "adopted")
        #expect(item.sourceState.verificationVerdict == "review_required")
    }

    @Test
    func decodesResearchClipCandidateWithSavedClip() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(
            VentureResearchClipCandidatePayload.self,
            from: Data(researchClipCandidateJSON.utf8)
        )

        #expect(payload.items.count == 1)
        #expect(payload.items[0].savedClip?.id == "clip-1")
        #expect(payload.items[0].savedClip?.version == 2)
    }

    private let policyJSON = #"""
    {
      "ventureId": "landlord-saas",
      "policyText": "# 自由な事業方針",
      "policyTextVersionId": "policy-text-v2",
      "policyTextVersion": 2,
      "policyTextUpdatedAt": "2026-07-20T00:00:00Z",
      "strategyVersionId": "strategy-v2",
      "decisionFrameVersionId": "frame-v3",
      "mission": "小規模大家の日常事務を減らす",
      "targetSegments": [
        {"key":"small-landlord","label":"小規模大家","description":"1〜10室を自己管理"}
      ],
      "desiredOutcomes": ["入金確認の負担を減らす"],
      "commercialHypotheses": ["月額3,000円で提供できる可能性がある"],
      "focusAreas": ["入金照合"],
      "exclusions": ["一般的なExcel操作支援"],
      "researchGuardrails": ["個人情報を収集しない"],
      "deliveryGuardrails": ["外部送信は別承認"],
      "systemSafetyConstraints": ["本番デプロイは最終確認を必須にする"],
      "stage": "exploration",
      "objectives": ["validate-rent-reconciliation"],
      "lenses": [
        {"key":"strategic_fit","label":"方針一致","weight":40,"direction":"higher_is_better","required":true,"description":"対象顧客と目的への一致"}
      ],
      "hardGates": [
        {"key":"target_segment_match","label":"対象顧客","description":"対象顧客に一致する","parameters":{"required":true}}
      ],
      "maxRecommendations": 1,
      "objectiveDefinitions": [
        {"key":"validate-rent-reconciliation","label":"入金照合を検証","description":"課題の強さを確認する"}
      ],
      "decisionLensDefinitions": [
        {"key":"strategic_fit","label":"方針一致","direction":"higher_is_better","description":"対象顧客と目的への一致"}
      ],
      "hardGateDefinitions": [
        {"key":"target_segment_match","label":"対象顧客","description":"対象顧客に一致する"}
      ],
      "currentView": "入金照合は有力だが負担量は未確認",
      "synthesisVersionId": "synthesis-v4",
      "pendingPolicyChangeCount": 1,
      "policyChangeStatusCounts": {
        "awaitingReview": 1,
        "awaitingExternalInput": 0,
        "pendingApply": 0,
        "applyFailed": 1
      },
      "generatedAt": "2026-07-20T00:00:00Z"
    }
    """#

    private let policyRevisionJSON = #"""
    {
      "schemaVersion": 3,
      "kind": "policy_revision",
      "basePolicyTextVersionId": "policy-text-v1",
      "baseStrategyVersionId": "strategy-v2",
      "baseDecisionFrameVersionId": "frame-v3",
      "nextPolicyText": null,
      "nextStrategy": {
        "mission": "小規模大家の日常事務を減らす",
        "targetSegments": [
          {"key":"small-landlord","label":"小規模大家","description":"1〜10室を自己管理"}
        ],
        "desiredOutcomes": ["入金確認の負担を減らす"],
        "commercialHypotheses": ["月額3,000円の支払意思を検証する"],
        "focusAreas": ["入金の対象月割当"],
        "exclusions": ["一般的なExcel操作支援"],
        "researchGuardrails": ["個人情報を収集しない"],
        "deliveryGuardrails": ["外部送信は別承認"]
      },
      "nextDecisionFrame": {
        "stage": "validation",
        "objectiveIds": ["validate-rent-allocation"],
        "lenses": [
          {"key":"strategic_fit","label":"方針一致","weight":100,"direction":"higher_is_better","required":true,"description":"対象顧客と目的への一致"}
        ],
        "hardGates": [
          {"key":"target_segment_match","label":"対象顧客","description":"対象顧客に一致する","parameters":{"required":true}}
        ],
        "maxRecommendations": 1
      },
      "rationale": "対象月判定の事例が名義違いより多かった",
      "expectedImpact": "次回の推薦は入金割当を中心にする",
      "contraryEvidence": ["調査件数はまだ5件"],
      "sourceRefs": [
        {"kind":"learning","id":"learning-1","relation":"supports"}
      ],
      "risk": "high",
      "consultationSummary": null
    }
    """#

    private let policyRevisionDetailJSON = #"""
    {
      "missionId": "mission-1",
      "missionVersion": 1,
      "currentAttempt": null,
      "reviews": [],
      "deliverableId": "deliverable-1",
      "revisionHash": "revision-hash-1",
      "reviewDeepLink": "myharness://knowledge-change-missions/mission-1",
      "origin": "human_consultation",
      "status": "awaiting_review",
      "reviewStatus": "awaiting_review",
      "applicationStatus": "not_requested",
      "applicationError": null,
      "baseVersions": {
        "policyTextVersionId": "policy-text-1",
        "strategyVersionId": "strategy-1",
        "decisionFrameVersionId": "frame-1"
      },
      "currentVersions": {
        "policyTextVersionId": "policy-text-1",
        "strategyVersionId": "strategy-1",
        "decisionFrameVersionId": "frame-1"
      },
      "isStale": false,
      "staleReasons": [],
      "summary": "日々の記録を主軸にする",
      "rationale": "資料準備の負担が大きい",
      "expectedImpact": "次の推薦対象が変わる",
      "contraryEvidence": [],
      "sourceRefs": [],
      "risk": "high",
      "consultationSummary": "ChatGPTで方針を整理した",
      "policyTextDiff": {
        "before": "# 旧方針",
        "after": "# 新方針",
        "hunks": [
          {
            "oldStart": 1,
            "oldLineCount": 1,
            "newStart": 1,
            "newLineCount": 1,
            "lines": [
              {"kind":"removed","oldLineNumber":1,"newLineNumber":null,"text":"# 旧方針"},
              {"kind":"added","oldLineNumber":null,"newLineNumber":1,"text":"# 新方針"}
            ]
          }
        ]
      },
      "structuredChanges": [
        {
          "path": "strategy.focusAreas",
          "label": "現在のFocus",
          "changeType": "list",
          "before": ["日々の記録"],
          "after": ["日々の記録", "月次確認"],
          "added": ["月次確認"],
          "removed": [],
          "reordered": false
        }
      ],
      "impactPreview": {
        "staleProposalCount": 2,
        "supersededRecommendationSetCount": 1,
        "supersededSynthesisCount": 1,
        "supersededAgendaItemCount": 1
      },
      "canAdopt": true,
      "canRequestRevision": true,
      "canReject": true
    }
    """#

    private let researchClipJSON = #"""
    {
      "clip": {
        "id": "clip-1",
        "ownerUserId": "owner-1",
        "ventureId": "landlord-saas",
        "deliverableId": "deliverable-1",
        "itemKey": "research-clip:v1:supporting_evidence:0:hash",
        "extractorSchemaKey": "venture_research_mission_v3",
        "extractorVersion": 1,
        "itemKind": "supporting_evidence",
        "relation": "supports",
        "textSnapshot": "確定申告前に領収書をまとめている",
        "contextSnapshot": "資料整理の負担を示している",
        "sourceUrl": "https://x.com/example/status/1",
        "sourceSnapshot": {
          "type": "x_post",
          "externalKey": "1",
          "author": "example",
          "publishedAt": null,
          "metadata": {"query": "大家 確定申告"}
        },
        "userNote": "有料課題候補",
        "opportunityId": "opportunity-1",
        "hypothesisId": "hypothesis-1",
        "version": 1,
        "createdAt": "2026-07-20T00:00:00Z",
        "updatedAt": "2026-07-20T00:00:00Z",
        "archivedAt": null
      },
      "sourceState": {
        "sourceMissionId": "mission-1",
        "sourceMissionStatus": "completed",
        "sourceReviewDecision": "adopted",
        "isCurrentDeliverable": true,
        "verificationStatus": "awaiting_review",
        "verificationVerdict": "review_required"
      }
    }
    """#

    private let researchClipCandidateJSON = #"""
    {
      "deliverableId": "deliverable-1",
      "ventureId": "landlord-saas",
      "missionId": "mission-1",
      "extractorVersion": 1,
      "items": [
        {
          "itemKey": "research-clip:v1:observation:0:abc",
          "extractorSchemaKey": "venture_research_mission_v3",
          "extractorVersion": 1,
          "kind": "observation",
          "label": "個別の観測結果",
          "relation": "supports",
          "text": "確定申告前に領収書をまとめている",
          "context": "資料整理の負担を示す",
          "sourceUrl": "https://x.com/example/status/1",
          "sourceSnapshot": {
            "type": "x_post",
            "externalKey": "1",
            "author": "example",
            "publishedAt": null,
            "metadata": {}
          },
          "savedClip": {
            "id": "clip-1",
            "ownerUserId": "owner-1",
            "ventureId": "landlord-saas",
            "deliverableId": "deliverable-1",
            "itemKey": "research-clip:v1:observation:0:abc",
            "extractorSchemaKey": "venture_research_mission_v3",
            "extractorVersion": 1,
            "itemKind": "observation",
            "relation": "supports",
            "textSnapshot": "確定申告前に領収書をまとめている",
            "contextSnapshot": "資料整理の負担を示す",
            "sourceUrl": "https://x.com/example/status/1",
            "sourceSnapshot": {
              "type": "x_post",
              "externalKey": "1",
              "author": "example",
              "publishedAt": null,
              "metadata": {}
            },
            "userNote": "保存済み",
            "opportunityId": null,
            "hypothesisId": null,
            "version": 2,
            "createdAt": "2026-07-20T00:00:00.000Z",
            "updatedAt": "2026-07-20T01:00:00.000Z",
            "archivedAt": null
          }
        }
      ]
    }
    """#
}
