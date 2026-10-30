import AppKit
import SwiftUI
import AsideCore

/// On-demand explanation only. This window never becomes the typing target.
@MainActor final class ExplanationPanel {
    private final class PassiveWindow: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    private final class ClickableHostingView<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
    private var window: PassiveWindow?

    func hide() {
        guard let window else { return }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    @discardableResult func show(_ result: WritingResult, style: ExpressionStyle, candidateFrame: NSRect) -> Bool {
        guard candidateFrame.width > 0, candidateFrame.height > 0 else { return false }
        let window: PassiveWindow
        if let existing = self.window { window = existing }
        else {
            window = PassiveWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "句外讲解"
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.transient, .fullScreenAuxiliary]
            self.window = window
        }
        let matching = NSApp.windows.filter {
            $0 !== window && $0.isVisible && abs($0.frame.width - candidateFrame.width) < 1
                && abs($0.frame.height - candidateFrame.height) < 1
        }
        let parent = matching.first(where: {
            abs($0.frame.minX - candidateFrame.minX) < 1 && abs($0.frame.minY - candidateFrame.minY) < 1
        }) ?? (matching.count == 1 ? matching.first : nil)
        let anchor = parent?.frame ?? candidateFrame
        let screen = parent?.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main
        let usable = (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)).insetBy(dx: 8, dy: 8)
        let width = min(360, usable.width)
        let content = ClickableHostingView(rootView: ExplanationContent(result: result, style: style, width: width) { [weak self] in self?.hide() })
        let naturalHeight = max(120, content.fittingSize.height)
        let height = min(naturalHeight, min(280, usable.height))
        content.setFrameSize(NSSize(width: width, height: naturalHeight))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.documentView = content
        scroll.hasVerticalScroller = naturalHeight > height
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        let backdrop = NSVisualEffectView(frame: scroll.frame)
        backdrop.material = .popover
        backdrop.state = .active
        backdrop.blendingMode = .behindWindow
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 12
        backdrop.layer?.masksToBounds = true
        backdrop.addSubview(scroll)
        window.contentView = backdrop
        let x = max(usable.minX, min(anchor.minX, usable.maxX - width))
        let below = anchor.minY - height - 6
        let proposedY = below >= usable.minY ? below : anchor.maxY + 6
        let y = max(usable.minY, min(proposedY, usable.maxY - height))
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        window.parent?.removeChildWindow(window)
        if let parent {
            window.level = NSWindow.Level(rawValue: parent.level.rawValue + 1)
            parent.addChildWindow(window, ordered: .above)
        } else { window.level = .popUpMenu }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: content.isFlipped ? 0 : max(0, naturalHeight - height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        window.orderFrontRegardless()
        if window.isVisible { imeDiagnostic("explanation window: \(window.windowNumber)") }
        return window.isVisible
    }
}

private struct ExplanationContent: View {
    let result: WritingResult
    let style: ExpressionStyle
    let width: CGFloat
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(style.title).font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(red: 0.30, green: 0.42, blue: 0.34), in: Capsule())
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark").font(.caption) }
                    .buttonStyle(.plain).accessibilityLabel("收起讲解")
            }
            Text(result.expression).font(.system(size: 15, weight: .medium))
            Divider()
            Text(result.explanation).font(.system(size: 13))
            Text("Esc 收起 · 原文保持不变").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: width, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}
