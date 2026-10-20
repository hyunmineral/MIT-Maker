import AVFoundation
import Observation
import UIKit
import Vision

/// Stage-1 measurement — **is a face visible.** Who it is isn't measured yet.
///
/// Air 5 front camera + Vision `VNDetectFaceRectanglesRequest` /
/// `VNDetectFaceCaptureQualityRequest`. Embedding and DB matching are stage 2.
/// Only Neural Engine detection runs per frame, and no photos are saved.
@Observable
final class FaceProbe: NSObject {

    struct Detection: Equatable {
        var count: Int
        var confidence: Float
        var quality: Float?
        /// Normalised box (Vision, origin bottom left). Converted when drawing over the preview.
        var boxes: [CGRect]
    }

    private(set) var isRunning = false
    private(set) var lastError: String?
    private(set) var latest = Detection(count: 0, confidence: 0, quality: nil, boxes: [])
    private(set) var frames = 0
    private(set) var hits = 0

    var hitRate: Double {
        guard frames > 0 else { return 0 }
        return Double(hits) / Double(frames)
    }

    let preview = PreviewView()

    @ObservationIgnored private let session = AVCaptureSession()
    @ObservationIgnored private let visionQueue = DispatchQueue(label: "FaceProbe.vision")
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var pendingCapture: ((CGImage?) -> Void)?

    /// Passes the next camera frame on as an upright CGImage. Used by the enrol and match buttons.
    func captureFrame(_ completion: @escaping (CGImage?) -> Void) {
        visionQueue.async {
            guard self.session.isRunning else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.pendingCapture = completion
        }
    }

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start() {
        guard !isRunning else { return }
        guard Consent.isGranted(.biometric) else {
            lastError = "No biometric (face) consent"
            return
        }
        lastError = nil
        visionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureIfNeeded()
                self.session.startRunning()
                DispatchQueue.main.async { self.isRunning = true }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.isRunning = false
                }
            }
        }
    }

    func stop() {
        visionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.isRunning = false
                self.latest = Detection(count: 0, confidence: 0, quality: nil, boxes: [])
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front)
        else { throw ProbeError.noCamera }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw ProbeError.noCamera }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: visionQueue)
        guard session.canAddOutput(output) else { throw ProbeError.noCamera }
        session.addOutput(output)
        output.connection(with: .video)?.videoRotationAngle = 90
        output.connection(with: .video)?.isVideoMirrored = true

        session.commitConfiguration()
        preview.setSession(session)
        configured = true
    }

    enum ProbeError: LocalizedError {
        case noCamera
        var errorDescription: String? { "Could not open the front camera" }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        func setSession(_ session: AVCaptureSession) {
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.connection?.videoRotationAngle = 90
            previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
            previewLayer.connection?.isVideoMirrored = true
        }
    }
}

extension FaceProbe: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if let pending = pendingCapture {
            pendingCapture = nil
            let ci = CIImage(cvPixelBuffer: pixel).oriented(.leftMirrored)
            let cg = CIContext().createCGImage(ci, from: ci.extent)
            DispatchQueue.main.async { pending(cg) }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixel,
                                            orientation: .leftMirrored,
                                            options: [:])
        let rects = VNDetectFaceRectanglesRequest()
        let quality = VNDetectFaceCaptureQualityRequest()
        do {
            try handler.perform([rects, quality])
        } catch { return }

        let faces = (rects.results ?? [])
        let qualities = (quality.results ?? []).compactMap(\.faceCaptureQuality)
        let conf = faces.map(\.confidence).max() ?? 0
        let q = qualities.max()
        let boxes = faces.map(\.boundingBox)
        let count = faces.count

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.frames += 1
            if count > 0 { self.hits += 1 }
            self.latest = Detection(count: count, confidence: conf,
                                    quality: q, boxes: boxes)
        }
    }
}
