import Foundation
import Testing
@testable import ReclaimCore

/// These tests only *validate* paths; nothing here deletes anything.
@Suite struct SafetyPolicyTests {
    let realHome = FileManager.default.homeDirectoryForCurrentUser

    // MARK: Real locations must be refused

    @Test func sandboxPolicyRejectsRealHomeTrash() {
        let policy = SafetyPolicy(mode: .sandbox)
        #expect(throws: SafetyPolicy.Violation.self) {
            try policy.validateTrashRoot(realHome.appendingPathComponent(".Trash"))
        }
    }

    @Test(arguments: ["/", "/Users", "/Volumes", "/System", "/Applications"])
    func rejectsSystemPaths(_ path: String) {
        for mode in [RuntimeMode.live, .sandbox] {
            #expect(throws: SafetyPolicy.Violation.self) {
                try SafetyPolicy(mode: mode).validateTrashRoot(URL(fileURLWithPath: path))
            }
        }
    }

    @Test func rejectsHomeFolderItself() {
        for mode in [RuntimeMode.live, .sandbox] {
            #expect(throws: SafetyPolicy.Violation.self) {
                try SafetyPolicy(mode: mode).validateTrashRoot(realHome)
            }
        }
    }

    @Test func livePolicyAcceptsHomeTrashLocation() throws {
        // Validation only: proves the live app may target ~/.Trash, which the sandbox mode refuses.
        let fixture = try Fixture()
        let trash = fixture.home.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        #expect(throws: Never.self) { try fixture.policy(.live).validateTrashRoot(trash) }
        #expect(throws: SafetyPolicy.Violation.notAllowedInSandbox(trash.path)) {
            try fixture.policy(.sandbox).validateTrashRoot(trash)
        }
    }

    // MARK: Volume trash rules

    @Test func acceptsSandboxVolumeTrash() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        #expect(try fixture.policy().validateTrashRoot(trash) == trash.path)
    }

    @Test func sandboxRejectsNonTestVolume() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "Backup SSD")
        #expect(throws: SafetyPolicy.Violation.notAllowedInSandbox(trash.path)) {
            try fixture.policy(.sandbox).validateTrashRoot(trash)
        }
        #expect(throws: Never.self) { try fixture.policy(.live).validateTrashRoot(trash) }
    }

    @Test func rejectsOtherUsersTrashAndParents() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        let otherUser = trash.deletingLastPathComponent().appendingPathComponent("0")
        try FileManager.default.createDirectory(at: otherUser, withIntermediateDirectories: true)
        let policy = fixture.policy()
        for path in [otherUser, trash.deletingLastPathComponent(), trash.deletingLastPathComponent().deletingLastPathComponent()] {
            #expect(throws: SafetyPolicy.Violation.self) { try policy.validateTrashRoot(path) }
        }
    }

    @Test func rejectsTrashReachedThroughSymlink() throws {
        let fixture = try Fixture()
        let volume = try fixture.makeVolume("RTEST-LINK")
        // .Trashes is a symlink to a folder outside the volume.
        let target = fixture.outside.appendingPathComponent("\(fixture.uid)")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: volume.appendingPathComponent(".Trashes"), withDestinationURL: fixture.outside)
        #expect(throws: SafetyPolicy.Violation.self) {
            try fixture.policy().validateTrashRoot(volume.appendingPathComponent(".Trashes/\(fixture.uid)"))
        }
    }

    @Test func rejectsDotDotTraversal() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        let sneaky = URL(fileURLWithPath: trash.path + "/../../../../home")
        #expect(throws: SafetyPolicy.Violation.self) { try fixture.policy().validateTrashRoot(sneaky) }
    }

    // MARK: Targets

    @Test func targetMustBeInsideRoot() throws {
        let fixture = try Fixture()
        let root = try fixture.policy().validateTrashRoot(try fixture.makeTrash(onVolume: "RTEST-UNIT"))
        let policy = fixture.policy()
        let inside = URL(fileURLWithPath: root).appendingPathComponent("file.mov")
        try fixture.write(inside, bytes: 10)
        #expect(throws: Never.self) { try policy.validateTarget(inside, withinCanonicalRoot: root) }
        #expect(throws: SafetyPolicy.Violation.self) {
            try policy.validateTarget(fixture.outside.appendingPathComponent("x"), withinCanonicalRoot: root)
        }
        #expect(throws: SafetyPolicy.Violation.self) {
            try policy.validateTarget(URL(fileURLWithPath: root), withinCanonicalRoot: root)
        }
        #expect(throws: SafetyPolicy.Violation.self) {
            try policy.validateTarget(URL(fileURLWithPath: root + "/../escape"), withinCanonicalRoot: root)
        }
    }

    @Test func targetInsideSymlinkedFolderIsRejected() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        let root = try fixture.policy().validateTrashRoot(trash)
        try fixture.write(fixture.outside.appendingPathComponent("precious.txt"), bytes: 5)
        let link = trash.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.outside)
        // The link itself may be removed; something reached *through* it may not.
        #expect(throws: Never.self) { try fixture.policy().validateTarget(link, withinCanonicalRoot: root) }
        #expect(throws: SafetyPolicy.Violation.self) {
            try fixture.policy().validateTarget(link.appendingPathComponent("precious.txt"), withinCanonicalRoot: root)
        }
    }

    // MARK: Junk volumes

    @Test func junkVolumeRules() throws {
        let fixture = try Fixture()
        let policy = fixture.policy()
        let testVolume = try fixture.makeVolume("RTEST-USB")
        let realVolume = try fixture.makeVolume("Camera")
        #expect(throws: Never.self) { try policy.validateExternalVolume(testVolume) }
        #expect(throws: SafetyPolicy.Violation.notAllowedInSandbox(realVolume.path)) { try policy.validateExternalVolume(realVolume) }
        #expect(throws: SafetyPolicy.Violation.self) { try policy.validateExternalVolume(fixture.home) }
        #expect(throws: SafetyPolicy.Violation.self) { try policy.validateExternalVolume(testVolume.appendingPathComponent("sub")) }
        #expect(throws: SafetyPolicy.Violation.self) { try SafetyPolicy(mode: .live).validateExternalVolume(URL(fileURLWithPath: "/")) }
    }
}
