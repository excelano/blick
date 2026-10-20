// GraphTextTests.swift
// BlickGraphTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
@testable import BlickGraph

struct GraphTextTests {
    @Test func stripsTagsAndKeepsParagraphBreaks() {
        #expect(plainText(fromHTML: "<p>Hello</p><p>World</p>") == "Hello\nWorld")
    }

    @Test func turnsBreaksIntoNewlines() {
        #expect(plainText(fromHTML: "one<br>two<br/>three") == "one\ntwo\nthree")
    }

    @Test func decodesNamedAndNumericEntities() {
        #expect(plainText(fromHTML: "Tom &amp; Jerry &lt;3 &#33; &#x41;") == "Tom & Jerry <3 ! A")
    }

    @Test func doesNotDecodeAmpersandTwice() {
        #expect(plainText(fromHTML: "&amp;lt;") == "&lt;")
    }

    @Test func dropsStyleAndScriptBlocks() {
        #expect(plainText(fromHTML: "<style>p{color:red}</style><p>Hi</p><script>x()</script>") == "Hi")
    }

    @Test func collapsesRunsOfBlankLines() {
        #expect(plainText(fromHTML: "a<br><br><br><br>b") == "a\n\nb")
    }
}
