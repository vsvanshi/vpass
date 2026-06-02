import AppKit
import Foundation
import UniformTypeIdentifiers
import Vision

enum QRCodeScannerError: LocalizedError {
    case noImageSelected
    case unreadableImage
    case noQRCodeFound

    var errorDescription: String? {
        switch self {
        case .noImageSelected:
            return "No image was selected."
        case .unreadableImage:
            return "The selected image could not be read."
        case .noQRCodeFound:
            return "No QR code was found in the selected image."
        }
    }
}

struct QRCodeScanner {
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
}
