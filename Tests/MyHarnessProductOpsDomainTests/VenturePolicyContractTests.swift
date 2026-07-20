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
}
