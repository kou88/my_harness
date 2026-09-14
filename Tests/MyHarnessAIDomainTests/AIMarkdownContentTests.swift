import Testing
@testable import MyHarnessAIDomain

@Suite struct AIMarkdownContentTests {
    @Test func parsesGFMTableAndKeepsSurroundingMarkdown() {
        let source = """
        ## 比較

        | 順位 | モデル | サイズ |
        | ---: | :---: | --- |
        | 1位 | **Qwen** | 約50GB |
        | 2位 | `gpt-oss` | 約61GB |

        続きです。
        """

        #expect(AIMarkdownContent.parse(source).map(\.kind) == [
            .markdown("## 比較"),
            .table(.init(
                headers: ["順位", "モデル", "サイズ"],
                alignments: [.trailing, .center, .leading],
                rows: [
                    ["1位", "**Qwen**", "約50GB"],
                    ["2位", "`gpt-oss`", "約61GB"],
                ]
            )),
            .markdown("続きです。"),
        ])
    }

    @Test func supportsTablesWithoutOuterPipes() {
        #expect(AIMarkdownContent.parse("名前 | 値\n--- | ---:\nA | 10").map(\.kind) == [
            .table(.init(headers: ["名前", "値"], alignments: [.leading, .trailing], rows: [["A", "10"]]))
        ])
    }

    @Test func escapedAndInlineCodePipesStayInsideCells() {
        #expect(AIMarkdownContent.parse("| 式 | 説明 |\n| --- | --- |\n| A \\| B | ``x | `y` `` |").map(\.kind) == [
            .table(.init(headers: ["式", "説明"], alignments: [.leading, .leading], rows: [["A | B", "``x | `y` ``"]]))
        ])
    }

    @Test func invalidDelimiterRemainsMarkdown() {
        let source = "順位 | モデル\n-- | ---\n1位 | Qwen"
        #expect(AIMarkdownContent.parse(source).map(\.kind) == [.markdown(source)])
    }

    @Test func shortRowsArePaddedAndExtraCellsFollowGFM() {
        let parts = AIMarkdownContent.parse("| A | B |\n| --- | --- |\n| 1 |\n| 2 | 3 | 4 |")
        #expect(parts.map(\.kind) == [
            .table(.init(headers: ["A", "B"], alignments: [.leading, .leading], rows: [["1", ""], ["2", "3"]]))
        ])
    }

    @Test func proseWithPipesDoesNotBecomeATable() {
        let source = "■ CODING 1位 | Qwen | 約50GB | 2位 | gpt-oss | 約61GB"
        #expect(AIMarkdownContent.parse(source).map(\.kind) == [.markdown(source)])
    }
}
