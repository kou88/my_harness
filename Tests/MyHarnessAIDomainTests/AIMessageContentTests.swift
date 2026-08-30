import Testing
@testable import MyHarnessAIDomain

@Suite struct AIMessageContentTests {
    private func kinds(_ source: String) -> [AIMessageContent.Part.Kind] {
        AIMessageContent.parse(source).map(\.kind)
    }

    @Test func proseRemainsOneSelectionSurfaceAcrossParagraphs() {
        let prose = "# 見出し\n\n日本語 English 🙂\n\n`inline` と **太字**"
        #expect(kinds(prose) == [.text(prose)])
        #expect(kinds("").isEmpty)
    }

    @Test func eachBlockHasItsOwnLiteralCopyPayload() {
        #expect(kinds("前文\n\n```swift\n  print(\"こんにちは\")  \n\n```\n説明\n~~~python title=sample\nprint(2)\n~~~\n後文") == [
            .text("前文\n\n"),
            .code(language: "swift", text: "  print(\"こんにちは\")  \n\n"),
            .text("説明\n"),
            .code(language: "python", text: "print(2)\n"),
            .text("後文")
        ])
    }

    @Test func longerFenceCanContainShorterFencesLiterally() {
        #expect(kinds("````markdown\n```swift\nprint(1)\n```\n`````") == [
            .code(language: "markdown", text: "```swift\nprint(1)\n```\n")
        ])
    }

    @Test func mismatchedOrAnnotatedFenceCannotCloseABlock() {
        #expect(kinds("```text\n~~~\n``\n``` not a closer\n    ```\nend\n``` \t\n続き") == [
            .code(language: "text", text: "~~~\n``\n``` not a closer\n    ```\nend\n"),
            .text("続き")
        ])
    }

    @Test func indentationOnlyRemovesTheOpeningFenceIndent() {
        #expect(kinds("  ```python\n    print(1)\n x\n\tpass\n\n   ```") == [
            .code(language: "python", text: "  print(1)\nx\n\tpass\n\n")
        ])
    }

    @Test func invalidOpenersRemainProse() {
        let prose = "    ```swift\n\t```swift\ninline ```swift\n``swift\n```bad`info\nend"
        #expect(kinds(prose) == [.text(prose)])
    }

    @Test func missingLanguageAndEmptyBodyAreSupported() {
        #expect(kinds("```\n```\n~~~   \t\n~~~") == [
            .code(language: "", text: ""), .code(language: "", text: "")
        ])
        #expect(kinds("``` \t json metadata\n{}\n```") == [.code(language: "json", text: "{}\n")])
    }

    @Test func unclosedStreamCopiesOnlyReceivedContentAndKeepsViewIdentity() {
        let prefix = "回答\n```swift\n"
        let before = AIMessageContent.parse(prefix + "print(")
        let after = AIMessageContent.parse(prefix + "print(42)\n```\n完了")
        #expect(before.map(\.kind) == [.text("回答\n"), .code(language: "swift", text: "print(")])
        #expect(after.map(\.kind) == [.text("回答\n"), .code(language: "swift", text: "print(42)\n"), .text("完了")])
        #expect(before.map(\.id) == Array(after.prefix(2)).map(\.id))
        #expect(kinds("```swift") == [.code(language: "swift", text: "")])
    }

    @Test func lineEndingsNormalizeWithoutTrimmingCode() {
        #expect(kinds("```sh\r\n echo '🙂'  \r\n\r\n```\r\n") == [
            .code(language: "sh", text: " echo '🙂'  \n\n")
        ])
        #expect(kinds("~~~\rline\r~~~") == [.code(language: "", text: "line\n")])
        #expect(kinds("```text\nlast line  ") == [.code(language: "text", text: "last line  ")])
    }
}
