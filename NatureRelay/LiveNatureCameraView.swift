import SwiftUI
import AVFoundation
import Vision
import CoreML
import CoreImage
import UIKit

struct LiveNatureCameraFixtureReport: Codable {
    let hasFrame: Bool
    let hasActualMask: Bool
    let title: String
    let message: String
    let frameWidth: Double
    let frameHeight: Double
    let normalizedBounds: [Double]
    let errorStage: String?
    let errorDetail: String?
    let maskComputeMode: String
    let supportedMaskDevices: [String: [String]]
    let primaryMaskError: String?
    let maskObservationCount: Int
    let instanceCount: Int
    let instanceMaskPixelFormat: String?
    let generatedMaskPixelFormats: [String]
    let candidateCount: Int
    let selectionStatus: String
    let instanceReadErrors: [String]
}

/// Exercises the same Vision pipeline without requesting the camera or inventing a successful mask.
enum LiveNatureCameraFixtureVerifier {
    static func inspect(image: UIImage, maskDestination: URL? = nil) async -> LiveNatureCameraFixtureReport {
        let controller = LiveNatureCameraController(fixture: image, onTargetFrame: nil)
        return await controller.inspectFixture(image: image, maskDestination: maskDestination)
    }
}

/// The live highlight is a real foreground-instance mask. It is never replaced by a drawn plant shape.
struct LiveNatureCameraView: View {
    @Environment(\.scenePhase) private var scenePhase
    let fixtureImage: UIImage?
    let speciesName: String?
    let characterImage: UIImage?
    let fixtureCredit: String?
    let fixtureSourceURL: URL?
    let onCapture: (UIImage) -> Void
    let onClose: () -> Void
    @StateObject private var camera: LiveNatureCameraController

    init(fixtureImage: UIImage? = nil, speciesName: String? = nil, characterImage: UIImage? = nil,
         fixtureCredit: String? = nil, fixtureSourceURL: URL? = nil,
         onTargetFrame: ((UIImage) -> Void)? = nil,
         onCapture: @escaping (UIImage) -> Void, onClose: @escaping () -> Void) {
        self.fixtureImage = fixtureImage
        self.speciesName = speciesName
        self.characterImage = characterImage
        self.fixtureCredit = fixtureCredit
        self.fixtureSourceURL = fixtureSourceURL
        self.onCapture = onCapture
        self.onClose = onClose
        _camera = StateObject(wrappedValue: LiveNatureCameraController(fixture: fixtureImage, onTargetFrame: onTargetFrame))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let fixtureImage {
                    Image(uiImage: fixtureImage).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    LiveNaturePreview(session: camera.session)
                }
                if let mask = camera.maskImage {
                    let imageRect = aspectFillRect(source: camera.frameSize, destination: geometry.size)
                    let source = camera.maskBounds
                    let target = camera.targetBounds
                    let sx = source.width > 0 ? target.width / source.width : 1
                    let sy = source.height > 0 ? target.height / source.height : 1
                    let dx = target.minX - source.minX * sx
                    let dy = (1 - target.maxY) - (1 - source.maxY) * sy
                    Image(uiImage: mask).resizable()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .scaleEffect(x: sx, y: sy, anchor: .topLeading)
                        .offset(x: imageRect.minX + dx * imageRect.width,
                                y: imageRect.minY + dy * imageRect.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                        .accessibilityLabel("White translucent highlight of the detected foreground subject")
                }
                if let characterImage, !camera.targetBounds.isEmpty {
                    let rect = aspectFillRect(source: camera.frameSize, destination: geometry.size)
                    let x = rect.minX + camera.targetBounds.midX * rect.width
                    let y = rect.minY + (1 - camera.targetBounds.midY) * rect.height
                    Image(uiImage: characterImage).resizable().scaledToFit()
                        .frame(width: 148, height: 174)
                        .position(x: min(max(x, 80), geometry.size.width - 80),
                                  y: min(max(y, 160), geometry.size.height - 200))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                        .allowsHitTesting(false)
                }
                LinearGradient(colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        Button(action: onClose) {
                            Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                                .frame(width: 46, height: 46).background(.black.opacity(0.35), in: Circle())
                        }.accessibilityLabel("Close live camera")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Text("FIELD CAMERA").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                            Text(fixtureImage == nil ? "Meet what you found." : "Demo · public sample photo")
                                .font(.system(size: 14, weight: .semibold))
                        }.padding(.top, 7)
                    }.padding(.horizontal, 24).padding(.top, 18)
                    Spacer()
                    if camera.maskImage == nil && !camera.permissionDenied {
                        Image(systemName: "viewfinder").font(.system(size: 104, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.6)).accessibilityHidden(true)
                    }
                    Spacer()
                    VStack(spacing: 13) {
                        HStack(spacing: 8) {
                            Circle().fill(camera.maskImage == nil ? .white.opacity(0.65) : NRTheme.lime)
                                .frame(width: 7, height: 7)
                            Text(speciesName ?? camera.title).font(.system(size: 18, weight: .semibold, design: .rounded))
                        }
                        Text(camera.message).font(.system(size: 12)).multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.8)).lineSpacing(3).frame(maxWidth: 310)
                        if camera.permissionDenied {
                            Button("Open camera settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }.font(.system(size: 14, weight: .semibold)).padding(15)
                        } else {
                            Button {
                                camera.capture { image in if let image { onCapture(image) } }
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "camera.macro")
                                    Text("Use this photo")
                                }.font(.system(size: 16, weight: .bold)).foregroundStyle(NRTheme.ink)
                                    .frame(maxWidth: .infinity).padding(.vertical, 19)
                                    .background(camera.hasFrame ? NRTheme.lime : Color.white.opacity(0.45), in: Capsule())
                            }.disabled(!camera.hasFrame).accessibilityIdentifier("livecamera.capture")
                        }
                        Text("The live highlight stays on this iPhone. After capture, review its broad image label and choose a species name yourself.")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                        if let fixtureCredit {
                            HStack(spacing: 8) {
                                Text(fixtureCredit)
                                if let fixtureSourceURL { Link("Source", destination: fixtureSourceURL) }
                            }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.75))
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 28)
                }.foregroundStyle(.white)
            }.clipped()
        }
        .background(.black).preferredColorScheme(.dark)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start() } else { camera.stop() }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: characterImage != nil)
    }

    private func aspectFillRect(source: CGSize, destination: CGSize) -> CGRect {
        guard source.width > 0, source.height > 0 else { return CGRect(origin: .zero, size: destination) }
        let scale = max(destination.width / source.width, destination.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: (destination.width - size.width) / 2, y: (destination.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

private struct LiveNaturePreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}

// Session work belongs to sessionQueue; image/Vision state belongs to frameQueue;
// published presentation state is delivered on the main queue, guarded by a run generation.
private final class LiveNatureCameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published var maskImage: UIImage?
    @Published var frameSize = CGSize.zero
    @Published var targetBounds = CGRect.zero
    @Published var maskBounds = CGRect.zero
    @Published var title = "Point at one subject"
    @Published var message = "Keep the subject near the center and hold still for a moment."
    @Published var permissionDenied = false
    @Published var hasFrame = false
    private let sessionQueue = DispatchQueue(label: "nature.relay.camera.session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "nature.relay.camera.frames", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let fixture: UIImage?
    private let onTargetFrame: ((UIImage) -> Void)?
    private var latestFrame: UIImage?
    private var latestFrameGeneration: UInt64?
    private var configured = false
    private let activityLock = NSLock()
    private var isActive = false
    private var runGeneration: UInt64 = 0
    private var activeRun: UInt64? { activityLock.withLock { isActive ? runGeneration : nil } }
    private var lastFrameTime: CFTimeInterval = 0
    private var lastMaskTime: CFTimeInterval = 0
    private var lastClassificationTime: CFTimeInterval = 0
    private var tracker: VNTrackObjectRequest?
    private var sequence = VNSequenceRequestHandler()
    private var trackedBounds = CGRect.zero
    private var plantSuggested = false
    private var classification: VNImageBasedRequest?
    private var foregroundRequest: VNGenerateForegroundInstanceMaskRequest?
    private var triedMaskCPUFallback = false
    private var maskComputeMode = "system-default"
    private var supportedMaskDevices: [String: [String]] = [:]
    private var primaryMaskError: String?
    private var maskObservationCount = 0
    private var instanceCount = 0
    private var instanceMaskPixelFormat: String?
    private var generatedMaskPixelFormats: [String] = []
    private var candidateCount = 0
    private var selectionStatus = "not-run"
    private var instanceReadErrors: [String] = []
    private var maskFailureCount = 0
    private var stableFrames = 0
    private var sentStableFrame = false
    private var lastErrorStage: String?
    private var lastErrorDetail: String?

    init(fixture: UIImage?, onTargetFrame: ((UIImage) -> Void)?) {
        self.fixture = fixture
        self.onTargetFrame = onTargetFrame
        super.init()
    }

    func start() {
        let shouldStart = activityLock.withLock {
            guard !isActive else { return false }
            isActive = true; runGeneration &+= 1
            return true
        }
        guard shouldStart, let run = activeRun else { return }
        publish(generation: run) {
            $0.hasFrame = false; $0.permissionDenied = false; $0.frameSize = .zero
            $0.title = "Point at one subject"
            $0.message = "Keep the subject near the center and hold still for a moment."
        }
        frameQueue.async { [weak self] in
            guard let self, self.activeRun == run else { return }
            self.latestFrame = nil; self.latestFrameGeneration = nil
            self.tracker = nil; self.sequence = VNSequenceRequestHandler(); self.trackedBounds = .zero
            self.lastFrameTime = 0; self.lastMaskTime = 0; self.lastClassificationTime = 0
            self.stableFrames = 0; self.sentStableFrame = false
        }
        if let fixture {
            frameQueue.async { [weak self] in
                guard let self else { return }
                let scale = min(1, 1280 / max(fixture.size.width, fixture.size.height))
                let size = CGSize(width: fixture.size.width * scale, height: fixture.size.height * scale)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let renderer = UIGraphicsImageRenderer(size: size, format: format)
                let image = renderer.image { _ in fixture.draw(in: CGRect(origin: .zero, size: size)) }
                guard let cgImage = image.cgImage else { return }
                guard self.activeRun == run else { return }
                self.latestFrame = image; self.latestFrameGeneration = run
                self.publish(generation: run) { $0.hasFrame = true; $0.frameSize = image.size }
                self.analyze(handler: VNImageRequestHandler(cgImage: cgImage, orientation: .up), image: image, time: CACurrentMediaTime(), force: true, generation: run)
            }
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart(generation: run)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self, self.activeRun == run else { return }
                if granted { self.configureAndStart(generation: run) } else { self.cameraDenied(generation: run) }
            }
        default: cameraDenied(generation: run)
        }
    }

    func stop() {
        activityLock.withLock { isActive = false; runGeneration &+= 1 }
        maskImage = nil; targetBounds = .zero; maskBounds = .zero; hasFrame = false; frameSize = .zero
        sessionQueue.async { [weak self] in if self?.session.isRunning == true { self?.session.stopRunning() } }
        frameQueue.async { [weak self] in
            self?.latestFrame = nil; self?.latestFrameGeneration = nil
            self?.tracker = nil; self?.sequence = VNSequenceRequestHandler()
        }
    }

    func capture(completion: @escaping @MainActor @Sendable (UIImage?) -> Void) {
        frameQueue.async { [weak self] in
            guard let self, let run = self.activeRun, self.latestFrameGeneration == run else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let image = self.latestFrame
            DispatchQueue.main.async { completion(self.activeRun == run ? image : nil) }
        }
    }

    private func cameraDenied(generation: UInt64) {
        publish(generation: generation) { $0.permissionDenied = true; $0.title = "Camera access is off"; $0.message = "Allow camera access in Settings to photograph nature around you." }
    }

    private func configureAndStart(generation: UInt64) {
        sessionQueue.async { [weak self] in
            guard let self, self.activeRun == generation else { return }
            do {
                if !self.configured {
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                        self.publish(generation: generation) { $0.title = "No camera available"; $0.message = "Close the camera and choose a photo from your library." }
                        return
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }
                    self.session.sessionPreset = .hd1280x720
                    guard self.session.canAddInput(input) else { throw CameraError.configuration }
                    self.session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.frameQueue)
                    guard self.session.canAddOutput(output) else { throw CameraError.configuration }
                    self.session.addOutput(output)
                    if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                    if device.isFocusModeSupported(.continuousAutoFocus), (try? device.lockForConfiguration()) != nil {
                        device.focusMode = .continuousAutoFocus
                        device.unlockForConfiguration()
                    }
                    self.configured = true
                }
                if self.activeRun == generation && !self.session.isRunning { self.session.startRunning() }
            } catch {
                self.publish(generation: generation) { $0.title = "Camera couldn't start"; $0.message = error.localizedDescription }
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CACurrentMediaTime()
        guard let run = activeRun, time - lastFrameTime >= 0.18,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameTime = time
        autoreleasepool {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            let image = UIImage(cgImage: cgImage)
            guard activeRun == run else { return }
            latestFrame = image; latestFrameGeneration = run
            publish(generation: run) { $0.hasFrame = true; $0.frameSize = image.size }
            if let tracker {
                do {
                    try sequence.perform([tracker], on: pixelBuffer, orientation: .up)
                    if let observation = tracker.results?.first as? VNDetectedObjectObservation, observation.confidence >= 0.35 {
                        self.tracker?.inputObservation = observation
                        trackedBounds = smooth(observation.boundingBox, previous: trackedBounds)
                        let bounds = trackedBounds
                        publish(generation: run) { $0.targetBounds = bounds }
                    } else { clearTarget(message: "The subject moved. Hold one subject near the center again.", generation: run) }
                } catch { clearTarget(message: "The subject moved. Hold one subject near the center again.", generation: run) }
            }
            analyze(handler: VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up), image: image, time: time, force: false, generation: run)
        }
    }

    private func analyze(handler: VNImageRequestHandler, image: UIImage, time: CFTimeInterval, force: Bool, generation: UInt64) {
        guard activeRun == generation else { return }
        if force || time - lastClassificationTime > 2.2 {
            lastClassificationTime = time
            do {
                let request = try classificationRequest()
                try handler.perform([request])
                let results = (request.results as? [VNClassificationObservation] ?? []).sorted { $0.confidence > $1.confidence }
                let top = Array(results.prefix(3))
                let kind = PhotoRecognitionService.kind(for: top.map(\.identifier))
                plantSuggested = [.plant, .flower, .tree].contains(kind) && (top.first?.confidence ?? 0) >= 0.08
                let suggested = plantSuggested
                publish(generation: generation) { if $0.maskImage == nil { $0.title = suggested ? "A plant might be here" : "Point at one subject" } }
            } catch {
                lastErrorStage = "classification"; lastErrorDetail = error.localizedDescription
                plantSuggested = false
                publish(generation: generation) { $0.message = "Live category detection is unavailable. You can still take a photo." }
            }
        }
        guard force || time - lastMaskTime > 0.95 else { return }
        lastMaskTime = time
        do {
            guard let observation = try foregroundMask(from: handler) else {
                selectionStatus = "no-mask-observations"
                clearTarget(message: "Move closer to one subject, with some space around it.", generation: generation)
                return
            }
            guard let selected = selectInstance(observation) else {
                clearTarget(message: "Move closer to one subject, with some space around it.", generation: generation)
                return
            }
            guard selected.area > 0.003 else {
                selectionStatus = "candidate-too-small"
                clearTarget(message: "Move closer to one subject, with some space around it.", generation: generation)
                return
            }
            let pixels = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: selected.index), from: handler)
            let mask = CIImage(cvPixelBuffer: pixels)
            // RGB is white; only the actual segmentation values drive the translucent alpha.
            let white = mask.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0.34, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
            ])
            guard let cgMask = context.createCGImage(white, from: white.extent) else { throw CameraError.mask }
            guard activeRun == generation else { return }
            let renderedMask = UIImage(cgImage: cgMask)
            selectionStatus = "rendered-actual-mask"
            let oldBounds = trackedBounds
            trackedBounds = selected.bounds
            tracker = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: selected.bounds))
            tracker?.trackingLevel = .fast
            maskFailureCount = 0
            let title = plantSuggested ? "Plant candidate found" : "Subject highlighted"
            lastErrorStage = nil; lastErrorDetail = nil
            publish(generation: generation) {
                $0.maskImage = renderedMask; $0.maskBounds = selected.bounds; $0.targetBounds = selected.bounds
                $0.title = title
                $0.message = "The white area is the detected subject. Capture it, then choose its name and companion."
            }
            if plantSuggested && !oldBounds.isEmpty && abs(oldBounds.midX - selected.bounds.midX) < 0.07 && abs(oldBounds.midY - selected.bounds.midY) < 0.07 {
                stableFrames += 1
            } else { stableFrames = 0 }
            if stableFrames >= 2 && !sentStableFrame {
                sentStableFrame = true
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.activeRun == generation else { return }
                    self.onTargetFrame?(image)
                }
            }
        } catch {
            lastErrorStage = "foreground-mask-\(maskComputeMode)"
            let detail = error as NSError
            lastErrorDetail = "\(detail.localizedDescription) [\(detail.domain) \(detail.code)]"
            maskFailureCount += 1
            if maskFailureCount >= 2 || force {
                clearTarget(message: "A live silhouette isn't available here. You can still capture a photo and choose its name.", generation: generation)
            }
        }
    }

    private struct Instance { let index: Int; let bounds: CGRect; let area: Double }
    private func selectInstance(_ observation: VNInstanceMaskObservation) -> Instance? {
        var candidates = [Instance]()
        selectionStatus = observation.allInstances.isEmpty ? "no-foreground-instances" : "reading-instance-masks"
        for index in observation.allInstances.prefix(12) {
            let buffer: CVPixelBuffer
            do { buffer = try observation.generateMask(forInstances: IndexSet(integer: index)) }
            catch {
                instanceReadErrors.append("Instance \(index): \(error.localizedDescription)")
                selectionStatus = "instance-mask-generation-failed"
                continue
            }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let format = CVPixelBufferGetPixelFormatType(buffer)
            generatedMaskPixelFormats.append(pixelFormatDescription(format))
            guard format == kCVPixelFormatType_OneComponent32Float || format == kCVPixelFormatType_OneComponent8 else {
                selectionStatus = "generated-mask-pixel-format-unsupported"
                continue
            }
            guard let data = CVPixelBufferGetBaseAddress(buffer) else {
                selectionStatus = "generated-mask-base-address-unavailable"
                continue
            }
            let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            let floatValues = data.assumingMemoryBound(to: Float.self)
            let byteValues = data.assumingMemoryBound(to: UInt8.self)
            var minX = width, minY = height, maxX = -1, maxY = -1, count = 0
            for y in Swift.stride(from: 0, to: height, by: 2) {
                for x in Swift.stride(from: 0, to: width, by: 2) {
                    let included = format == kCVPixelFormatType_OneComponent32Float
                        ? floatValues[y * (rowBytes / MemoryLayout<Float>.stride) + x] > 0.5
                        : byteValues[y * rowBytes + x] > 127
                    guard included else { continue }
                    minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y); count += 4
                }
            }
            guard maxX >= minX, maxY >= minY else {
                selectionStatus = "generated-mask-empty-at-half-threshold"
                continue
            }
            let rect = CGRect(x: Double(minX) / Double(width), y: 1 - Double(maxY + 1) / Double(height),
                              width: Double(maxX - minX + 1) / Double(width), height: Double(maxY - minY + 1) / Double(height))
            candidates.append(Instance(index: index, bounds: rect, area: Double(count) / Double(width * height)))
        }
        candidateCount = candidates.count
        if !candidates.isEmpty { selectionStatus = "selected-instance" }
        let center = trackedBounds.isEmpty ? CGPoint(x: 0.5, y: 0.5) : CGPoint(x: trackedBounds.midX, y: trackedBounds.midY)
        return candidates.min { score($0, center: center) < score($1, center: center) }
    }

    private func score(_ instance: Instance, center: CGPoint) -> Double {
        let dx = instance.bounds.midX - center.x, dy = instance.bounds.midY - center.y
        let containsCenter = instance.bounds.contains(center)
        return dx * dx + dy * dy + (containsCenter ? 0 : 0.18) + (instance.area > 0.88 ? 0.25 : 0) - min(instance.area, 0.3) * 0.1
    }

    private func classificationRequest() throws -> VNImageBasedRequest {
        if let classification { return classification }
        let request: VNImageBasedRequest
        if let url = Bundle.main.url(forResource: "MobileNetV2FP16", withExtension: "mlmodelc") {
            let config = MLModelConfiguration(); config.computeUnits = .cpuOnly
            let model = try VNCoreMLModel(for: MLModel(contentsOf: url, configuration: config))
            let core = VNCoreMLRequest(model: model); core.imageCropAndScaleOption = .centerCrop
            request = core
        } else { request = VNClassifyImageRequest() }
        configureSimulator(request)
        classification = request
        return request
    }

    private func configureSimulator(_ request: VNRequest) {
        #if targetEnvironment(simulator)
        _ = configureCPU(request)
        #endif
    }

    @discardableResult private func configureCPU(_ request: VNRequest) -> Bool {
        var configured = false
        if let stages = try? request.supportedComputeStageDevices {
            for (stage, devices) in stages {
                if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                    request.setComputeDevice(cpu, for: stage)
                    configured = true
                }
            }
        }
        return configured
    }

    private func foregroundMask(from handler: VNImageRequestHandler) throws -> VNInstanceMaskObservation? {
        maskObservationCount = 0; instanceCount = 0; instanceMaskPixelFormat = nil
        generatedMaskPixelFormats = []; candidateCount = 0; selectionStatus = "request-started"; instanceReadErrors = []
        let request: VNGenerateForegroundInstanceMaskRequest
        if let foregroundRequest { request = foregroundRequest }
        else {
            request = VNGenerateForegroundInstanceMaskRequest()
            if let stages = try? request.supportedComputeStageDevices {
                supportedMaskDevices = Dictionary(uniqueKeysWithValues: stages.map { stage, devices in
                    let names = devices.map { device -> String in
                        if case .cpu = device { return "CPU" }
                        if case .gpu = device { return "GPU" }
                        if case .neuralEngine = device { return "Neural Engine" }
                        return "Other accelerator"
                    }
                    return (String(describing: stage), names)
                })
            }
            foregroundRequest = request
            #if targetEnvironment(simulator)
            maskComputeMode = configureCPU(request) ? "cpu-simulator" : "system-default-no-supported-cpu"
            triedMaskCPUFallback = true
            #endif
        }
        do { try handler.perform([request]) }
        catch {
            // Some devices cannot initialize the advertised accelerator; try supported CPU stages once.
            guard !triedMaskCPUFallback else { throw error }
            triedMaskCPUFallback = true
            primaryMaskError = error.localizedDescription
            guard configureCPU(request) else {
                maskComputeMode = "cpu-fallback-unsupported"
                throw error
            }
            maskComputeMode = "cpu-fallback"
            try handler.perform([request])
        }
        let results = request.results ?? []
        maskObservationCount = results.count
        if let observation = results.first {
            instanceCount = observation.allInstances.count
            instanceMaskPixelFormat = pixelFormatDescription(CVPixelBufferGetPixelFormatType(observation.instanceMask))
        }
        return results.first
    }

    private func pixelFormatDescription(_ format: OSType) -> String {
        let bytes = [UInt8((format >> 24) & 255), UInt8((format >> 16) & 255), UInt8((format >> 8) & 255), UInt8(format & 255)]
        let fourCC = String(bytes: bytes, encoding: .ascii) ?? "non-ASCII"
        return "\(format) (\(fourCC))"
    }

    private func clearTarget(message: String, generation: UInt64) {
        tracker = nil; trackedBounds = .zero; stableFrames = 0; sentStableFrame = false
        let title = plantSuggested ? "A plant might be here" : "Point at one subject"
        publish(generation: generation) { $0.maskImage = nil; $0.targetBounds = .zero; $0.maskBounds = .zero; $0.title = title; $0.message = message }
    }

    private func smooth(_ next: CGRect, previous: CGRect) -> CGRect {
        guard !previous.isEmpty else { return next }
        let alpha = 0.68
        return CGRect(x: previous.minX + (next.minX - previous.minX) * alpha,
                      y: previous.minY + (next.minY - previous.minY) * alpha,
                      width: previous.width + (next.width - previous.width) * alpha,
                      height: previous.height + (next.height - previous.height) * alpha)
    }

    private func publish(generation: UInt64? = nil, _ update: @escaping (LiveNatureCameraController) -> Void) {
        guard let generation = generation ?? activeRun else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.activeRun == generation else { return }
            update(self)
        }
    }

    func inspectFixture(image: UIImage, maskDestination: URL?) async -> LiveNatureCameraFixtureReport {
        activityLock.withLock { isActive = true; runGeneration &+= 1 }
        let run = activeRun!
        return await withCheckedContinuation { continuation in
            frameQueue.async {
                if let cgImage = image.cgImage {
                    self.latestFrame = image; self.latestFrameGeneration = run
                    self.publish(generation: run) { $0.hasFrame = true; $0.frameSize = image.size }
                    self.analyze(handler: VNImageRequestHandler(cgImage: cgImage, orientation: .up), image: image,
                                 time: CACurrentMediaTime(), force: true, generation: run)
                } else {
                    self.lastErrorStage = "image-decode"; self.lastErrorDetail = "The fixture has no decoded CGImage."
                }
                let errorStage = self.lastErrorStage, errorDetail = self.lastErrorDetail
                let computeMode = self.maskComputeMode, supported = self.supportedMaskDevices, primaryError = self.primaryMaskError
                let observationCount = self.maskObservationCount, instanceCount = self.instanceCount
                let rawFormat = self.instanceMaskPixelFormat, generatedFormats = self.generatedMaskPixelFormats
                let candidateCount = self.candidateCount, selectionStatus = self.selectionStatus, readErrors = self.instanceReadErrors
                DispatchQueue.main.async {
                    if let maskDestination, let data = self.maskImage?.pngData() { try? data.write(to: maskDestination, options: .atomic) }
                    continuation.resume(returning: LiveNatureCameraFixtureReport(
                        hasFrame: self.hasFrame, hasActualMask: self.maskImage != nil, title: self.title, message: self.message,
                        frameWidth: self.frameSize.width, frameHeight: self.frameSize.height,
                        normalizedBounds: [self.targetBounds.minX, self.targetBounds.minY, self.targetBounds.width, self.targetBounds.height],
                        errorStage: errorStage, errorDetail: errorDetail,
                        maskComputeMode: computeMode, supportedMaskDevices: supported, primaryMaskError: primaryError,
                        maskObservationCount: observationCount, instanceCount: instanceCount,
                        instanceMaskPixelFormat: rawFormat, generatedMaskPixelFormats: generatedFormats,
                        candidateCount: candidateCount, selectionStatus: selectionStatus, instanceReadErrors: readErrors))
                }
            }
        }
    }

    private enum CameraError: LocalizedError {
        case configuration, mask
        var errorDescription: String? {
            switch self {
            case .configuration: return "This camera configuration isn't available. Try choosing a photo instead."
            case .mask: return "The detected silhouette couldn't be rendered."
            }
        }
    }
}
