import AppKit
import CoreGraphics
import Foundation
import OSLog
import ScreenCaptureKit
import Vision

@MainActor
final class CaptureMonitor {
    enum State: Equatable {
        case stopped
        case waitingForPermission
        case monitoring
        case processing
        case error(String)

        var label: String {
            switch self {
            case .stopped: return "Stopped"
            case .waitingForPermission: return "Screen recording permission needed"
            case .monitoring: return "Watching for notifications"
            case .processing: return "Codex is researching a notification"
            case .error(let message): return "Error: \(message)"
            }
        }
    }

    var onStateChange: ((State) -> Void)?
    var onCodexResult: ((CodexRunner.Result) -> Void)?
    var onDiagnosticChange: ((String) -> Void)?

    private let runner = CodexRunner()
    private let logger = Logger(subsystem: "com.chidiwilliams.notificationclaude", category: "capture")
    private var timer: Timer?
    private var previousImages: [CGDirectDisplayID: CGImage] = [:]
    private var recentText: [String: Date] = [:]
    private var captureInProgress = false
    private var forceProcessNextFrame = false
    private var suppressDetectionUntil = Date.distantPast
    private(set) var state: State = .stopped {
        didSet { onStateChange?(state) }
    }

    func start() {
        guard timer == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            SnoopyLog.shared.warning("Screen recording permission is not granted")
            state = .waitingForPermission
            return
        }

        state = .monitoring
        SnoopyLog.shared.info("Monitoring started with a 2-second interval")
        captureAllDisplays()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureAllDisplays() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousImages.removeAll()
        captureInProgress = false
        state = .stopped
        SnoopyLog.shared.info("Monitoring stopped")
    }

    func requestPermission() {
        if CGRequestScreenCaptureAccess() {
            start()
        } else {
            state = .waitingForPermission
        }
    }

    func processNextFrame() {
        forceProcessNextFrame = true
        captureAllDisplays()
    }

    private func captureAllDisplays() {
        guard !captureInProgress, !runner.isRunning else { return }
        captureInProgress = true

        Task {
            defer { captureInProgress = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard !content.displays.isEmpty else {
                    onDiagnosticChange?("No capturable displays found")
                    return
                }
                for display in content.displays {
                    guard let screen = screen(for: display.displayID) else { continue }
                    let image = try await captureBannerArea(display: display, screen: screen)
                    await examine(image, displayID: display.displayID)
                }
            } catch {
                logger.error("Capture failed: \(error.localizedDescription, privacy: .public)")
                SnoopyLog.shared.error("Capture failed: \(error.localizedDescription)")
                onDiagnosticChange?("Capture failed: \(error.localizedDescription)")
                state = .error(error.localizedDescription)
            }
        }
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }

    private func captureBannerArea(display: SCDisplay, screen: NSScreen) async throws -> CGImage {
        let widthPoints = min(480.0, screen.frame.width)
        // Notification banners live in a shallow strip below the menu bar. Keeping this
        // tight prevents ordinary content in the underlying app from becoming prompt text.
        let heightPoints = min(220.0, screen.frame.height - 28.0)
        let scale = screen.backingScaleFactor

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(
            x: screen.frame.width - widthPoints,
            y: 28,
            width: widthPoints,
            height: heightPoints
        )
        configuration.width = Int(widthPoints * scale)
        configuration.height = Int(heightPoints * scale)
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private func examine(_ image: CGImage, displayID: CGDirectDisplayID) async {
        defer { previousImages[displayID] = image }
        guard let previous = previousImages[displayID] else {
            SnoopyLog.shared.info("Captured baseline for display \(displayID)")
            onDiagnosticChange?("Baseline captured; watching every 2 seconds")
            return
        }

        if Date() < suppressDetectionUntil {
            onDiagnosticChange?("Cooling down after Codex; baseline refreshed")
            return
        }

        let difference = sampledDifference(previous, image)
        let forced = forceProcessNextFrame
        if forced { forceProcessNextFrame = false }
        let percent = Int((difference * 100).rounded())
        onDiagnosticChange?(forced ? "Test capture: analyzing image…" : "Last visual change: \(percent)%")
        guard forced || difference > 0.07 else { return }

        let text = await recognizeText(in: image)
        let lineCount = text.split(separator: "\n").count
        guard text.count >= 8, lineCount >= 2 else {
            logger.info("Candidate rejected: OCR found \(lineCount) line(s)")
            onDiagnosticChange?("Image changed, but OCR found \(lineCount) text line(s)")
            SnoopyLog.shared.info("Candidate rejected: OCR found \(lineCount) line(s), visual change \(percent)%")
            return
        }

        let lowercaseText = text.lowercased()
        guard !lowercaseText.contains("codex finished"),
              !lowercaseText.contains("codex failed") else { return }

        let signature = normalizedSignature(text)
        let now = Date()
        recentText = recentText.filter { now.timeIntervalSince($0.value) < 120 }
        guard recentText[signature] == nil else { return }
        recentText[signature] = now

        logger.info("Notification candidate accepted with \(lineCount) OCR lines")
        SnoopyLog.shared.info("Notification candidate accepted: \(lineCount) OCR lines, visual change \(percent)%")
        onDiagnosticChange?("Detected \(lineCount) text lines; launching Codex…")
        state = .processing
        runner.run(image: image, recognizedText: text) { [weak self] result in
            guard let self else { return }
            self.suppressDetectionUntil = Date().addingTimeInterval(12)
            self.state = self.timer == nil ? .stopped : .monitoring
            self.onDiagnosticChange?(result.succeeded ? "Codex completed successfully" : "Codex failed; open last result")
            self.onCodexResult?(result)
        }
    }

    private func recognizeText(in image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first }
                    .filter { $0.confidence >= 0.35 }
                    .map(\.string) ?? []
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
        }
    }

    private func normalizedSignature(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(40)
            .joined(separator: " ")
    }

    private func sampledDifference(_ lhs: CGImage, _ rhs: CGImage) -> Double {
        guard lhs.width == rhs.width, lhs.height == rhs.height,
              let left = rgbaBytes(lhs), let right = rgbaBytes(rhs) else { return 1 }

        let pixelCount = lhs.width * lhs.height
        let stride = max(1, pixelCount / 18_000)
        var changed = 0
        var samples = 0
        for pixel in Swift.stride(from: 0, to: pixelCount, by: stride) {
            let offset = pixel * 4
            let delta = abs(Int(left[offset]) - Int(right[offset]))
                + abs(Int(left[offset + 1]) - Int(right[offset + 1]))
                + abs(Int(left[offset + 2]) - Int(right[offset + 2]))
            if delta > 75 { changed += 1 }
            samples += 1
        }
        return samples == 0 ? 0 : Double(changed) / Double(samples)
    }

    private func rgbaBytes(_ image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }
}
