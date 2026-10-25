import Testing
import SwiftUI
@testable import ReclaimUI

@Suite struct PlaceholderTests {
    @MainActor @Test func panelBuilds() {
        _ = PanelPlaceholder().body
    }
}
