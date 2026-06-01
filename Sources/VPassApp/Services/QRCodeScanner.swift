import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import Vision

enum QRCodeScannerError: LocalizedError {
    case noImageSelected
    case selectionCancelled
    case unreadableImage
    case noQRCodeFound
    case screenCaptureFailed
    case screenCapturePermissionRequested

    var errorDescription: String? {
        switch self {
        case .noImageSelected:
            return "No image was selected."
        case .selectionCancelled:
            return "QR scan was cancelled."
        case .unreadableImage:
            return "The selected image could not be read."
        case .noQRCodeFound:
            return "No QR code was found in the selected area. Draw the rectangle around the MFA QR code, or use Choose Image."
        case .screenCaptureFailed:
            return "The screen could not be captured. You may need to allow Screen Recording for VPass in System Settings."
        case .screenCapturePermissionRequested:
            return "Allow Screen Recording for VPass, then quit and reopen the app before scanning again."
        }
    }
}

struct QRCodeScanner {
    static var hasScreenCaptureAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @MainActor
    static func scanImageFromDisk() throws -> String {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose an MFA QR code image"

        guard panel.runModal() == .OK, let url = panel.url else {
            throw QRCodeScannerError.noImageSelected
        }
        guard let image = NSImage(contentsOf: url), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw QRCodeScannerError.unreadableImage
        }
        return try scan(cgImage: cgImage)
    }

    static func scanCurrentScreen() throws -> String {
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
            throw QRCodeScannerError.screenCaptureFailed
        }
        return try scan(cgImage: image)
    }

    @MainActor
    static func scanVisibleDesktop() async throws -> String {
        NSApp.hide(nil)
        try await Task.sleep(for: .milliseconds(450))
        defer {
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return try scanCurrentScreen()
    }

    @MainActor
    static func scanSelectedScreenRegion() async throws -> String {
        guard hasScreenCaptureAccess else {
            _ = CGRequestScreenCaptureAccess()
            throw QRCodeScannerError.screenCapturePermissionRequested
        }

        let windowsToRestore = NSApp.windows.filter { window in
            window.isVisible && !(window is ScreenRegionSelectionWindow)
        }
        windowsToRestore.forEach { $0.orderOut(nil) }

        defer {
            for window in windowsToRestore {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }

        try await Task.sleep(for: .milliseconds(200))
        guard let selectedRect = await ScreenRegionSelectionController.selectRegion() else {
            throw QRCodeScannerError.selectionCancelled
        }
        try await Task.sleep(for: .milliseconds(120))
        guard let image = captureMainDisplay(rect: selectedRect) else {
            throw QRCodeScannerError.screenCaptureFailed
        }
        return try scan(cgImage: image)
    }

    private static func scan(cgImage: CGImage) throws -> String {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        guard let payload = request.results?.compactMap(\.payloadStringValue).first else {
            throw QRCodeScannerError.noQRCodeFound
        }
        return payload
    }

    private static func captureMainDisplay(rect: CGRect) -> CGImage? {
        guard let screen = NSScreen.main,
              let fullImage = CGDisplayCreateImage(CGMainDisplayID()) else {
            return nil
        }

        let scale = screen.backingScaleFactor
        let screenFrame = screen.frame
        let pixelRect = CGRect(
            x: (rect.minX - screenFrame.minX) * scale,
            y: (screenFrame.maxY - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral

        let imageBounds = CGRect(x: 0, y: 0, width: fullImage.width, height: fullImage.height)
        let croppedRect = pixelRect.intersection(imageBounds)
        guard croppedRect.width > 0, croppedRect.height > 0 else {
            return nil
        }
        return fullImage.cropping(to: croppedRect)
    }
}

@MainActor
private final class ScreenRegionSelectionController {
    private static var activeController: ScreenRegionSelectionController?

    private var window: ScreenRegionSelectionWindow?
    private var continuation: CheckedContinuation<CGRect?, Never>?

    static func selectRegion() async -> CGRect? {
        await withCheckedContinuation { continuation in
            guard let screen = NSScreen.main else {
                continuation.resume(returning: nil)
                return
            }

            let controller = ScreenRegionSelectionController()
            activeController = controller
            controller.continuation = continuation
            controller.show(on: screen)
        }
    }

    private func show(on screen: NSScreen) {
        let window = ScreenRegionSelectionWindow(contentRect: screen.frame)
        let view = ScreenRegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size)) { [weak self] selectedRect in
            self?.finish(selectedRect)
        }

        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSCursor.crosshair.set()
        self.window = window
    }

    private func finish(_ selectedRect: CGRect?) {
        NSCursor.arrow.set()
        window?.orderOut(nil)
        window = nil
        continuation?.resume(returning: selectedRect)
        continuation = nil
        Self.activeController = nil
    }
}

private final class ScreenRegionSelectionWindow: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
        isOpaque = false
        level = .screenSaver
        title = "Select QR Code"
    }

    override var canBecomeKey: Bool {
        true
    }
}

private final class ScreenRegionSelectionView: NSView {
    private let onComplete: (CGRect?) -> Void
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isFlipped: Bool {
        true
    }

    init(frame frameRect: NSRect, onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()

        if let selectionRect {
            NSColor.white.withAlphaComponent(0.18).setFill()
            selectionRect.fill()

            NSColor.white.setStroke()
            let path = NSBezierPath(rect: selectionRect)
            path.lineWidth = 2
            path.stroke()
        }

        drawInstruction()
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let selectionRect, selectionRect.width >= 24, selectionRect.height >= 24 else {
            onComplete(nil)
            return
        }

        let windowFrame = window?.frame ?? .zero
        let screenRect = CGRect(
            x: windowFrame.minX + selectionRect.minX,
            y: windowFrame.maxY - selectionRect.maxY,
            width: selectionRect.width,
            height: selectionRect.height
        )
        onComplete(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onComplete(nil)
            return
        }
        super.keyDown(with: event)
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private func drawInstruction() {
        let text = "Drag around the MFA QR code. Press Esc to cancel."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: (bounds.width - size.width) / 2,
            y: 36,
            width: size.width,
            height: size.height
        )
        text.draw(in: rect, withAttributes: attributes)
    }
}
