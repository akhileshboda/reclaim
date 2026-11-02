import AppKit

/// The fields inside the feedback alert: what happened, and an optional address for a reply.
@MainActor
final class FeedbackForm {
    let view: NSView
    let messageView = NSTextView()
    private let contactField = NSTextField()

    var message: String { messageView.string }
    var contact: String { contactField.stringValue }

    init() {
        messageView.isRichText = false
        messageView.isAutomaticQuoteSubstitutionEnabled = false
        messageView.font = .systemFont(ofSize: NSFont.systemFontSize)
        messageView.isVerticallyResizable = true
        messageView.autoresizingMask = [.width]
        messageView.textContainerInset = NSSize(width: 4, height: 4)
        messageView.setAccessibilityLabel("What happened")

        let scroll = NSScrollView()
        scroll.documentView = messageView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        contactField.placeholderString = "Your email, only if you’d like a reply (optional)"
        contactField.setAccessibilityLabel("Your email address, optional")

        let stack = NSStackView(views: [scroll, contactField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 150)
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: 360),
            scroll.heightAnchor.constraint(equalToConstant: 112),
            contactField.widthAnchor.constraint(equalToConstant: 360),
        ])
        view = stack
    }
}
