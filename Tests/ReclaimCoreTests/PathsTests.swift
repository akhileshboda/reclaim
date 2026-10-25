import Foundation
import Testing
@testable import ReclaimCore

@Suite struct PathsTests {
    /// Regression: Foundation's standardizing rewrote /private/tmp to /tmp, so every
    /// canonical comparison in SafetyPolicy failed (closed). Normalisation must be lexical.
    @Test func keepsPrivatePrefix() {
        #expect(Paths.normalized(URL(fileURLWithPath: "/private/tmp/a/b")) == "/private/tmp/a/b")
        #expect(Paths.normalized(URL(fileURLWithPath: "/private/var/folders/x")) == "/private/var/folders/x")
    }

    @Test func resolvesDotsLexically() {
        #expect(Paths.normalized(URL(fileURLWithPath: "/Volumes/X/.Trashes/501/../../../..")) == "/")
        #expect(Paths.normalized(URL(fileURLWithPath: "/a/./b//c/../d")) == "/a/b/d")
    }

    @Test func strictContainment() {
        #expect(Paths.isStrictlyInside("/a/b/c", root: "/a/b"))
        #expect(!Paths.isStrictlyInside("/a/b", root: "/a/b"))
        #expect(!Paths.isStrictlyInside("/a/bc", root: "/a/b"))
        #expect(Paths.isStrictlyInside("/a/b/c", root: "/a/b/"))
    }
}
