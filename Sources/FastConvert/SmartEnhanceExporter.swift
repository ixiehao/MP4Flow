@preconcurrency import AVFoundation
import AudioToolbox
import CoreVideo
@preconcurrency import Dispatch
import VideoToolbox

/// Resolves an async bridge exactly once when a framework callback races a
/// watchdog. VideoToolbox callbacks can arrive after a cancelled export.
private final class ExportCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    @discardableResult func succeed() -> Bool { resolve(.success(())) }
    @discardableResult func fail(_ error: Error) -> Bool { resolve(.failure(error)) }

    private func resolve(_ result: Result<Void, Error>) -> Bool {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        guard let continuation else { return false }
        continuation.resume(with: result)
        return true
    }
}

/// Cancellation may arrive before a VideoToolbox or writer continuation is
/// installed. Keep that signal until the bridge is ready to receive it.
private final class ExportWaitCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var gate: ExportCompletionGate?
    private var cancelled = false
    private var submitted = false

    @discardableResult func install(_ gate: ExportCompletionGate) -> Bool {
        lock.lock()
        self.gate = gate
        let cancelled = self.cancelled
        lock.unlock()
        if cancelled { gate.fail(CancellationError()) }
        return !cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let gate = submitted ? self.gate : nil
        lock.unlock()
        gate?.fail(CancellationError())
    }

    /// Finish submitting the framework request before cancellation can resume
    /// the exporter and tear down the reader, writer or processing session.
    func submit(_ operation: () -> Void) {
        lock.lock()
        guard !cancelled else {
            let gate = self.gate
            lock.unlock()
            gate?.fail(CancellationError())
            return
        }
        submitted = true
        operation()
        lock.unlock()
    }
}

/// AVFoundation's writer completion callback is Sendable on modern SDKs while
/// AVAssetWriter itself is not annotated Sendable. The exporter owns it for the
/// entire callback lifetime and serializes all mutation through AVFoundation.
private final class ExportWriterReference: @unchecked Sendable {
    let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }
}

enum SmartEnhanceAvailability {
    static var isSupported: Bool {
        guard #available(macOS 27.0, *) else { return false }
        return SmartEnhanceExporter.isSupported
    }
}

/// A native, opt-in VideoToolbox export path. The enhancement stage only uses
/// exact system-advertised factors; a native pixel transfer then lands on the
/// user-selected output height without pretending arbitrary scaling is ML.
struct SmartEnhancePlan: Sendable {
    static let maximumScaleFactor: Float = 2

    let sourceWidth: Int
    let sourceHeight: Int
    let enhancedWidth: Int
    let enhancedHeight: Int
    let targetWidth: Int
    let targetHeight: Int
    let scaleFactor: Float

    var outputSummary: String { "\(targetWidth) × \(targetHeight)" }

    @available(macOS 27.0, *)
    static func availableTargets(sourceWidth: Int, sourceHeight: Int) -> [SmartEnhanceTarget] {
#if compiler(>=6.4)
        guard SmartEnhanceExporter.isSupported,
              sourceWidth > 0,
              sourceHeight > 0 else { return [] }

        let supported = VTLowLatencySuperResolutionScalerConfiguration
            .supportedScaleFactors(frameWidth: sourceWidth, frameHeight: sourceHeight)
        guard let maximumFactor = supported.filter({ $0 <= maximumScaleFactor }).max() else { return [] }
        let maximumHeight = Int((Float(sourceHeight) * maximumFactor).rounded(.down))
        return SmartEnhanceTarget.allCases.filter { target in
            target.rawValue > sourceHeight
                && target.rawValue <= maximumHeight
                && outputWidth(sourceWidth: sourceWidth, sourceHeight: sourceHeight, targetHeight: target.rawValue) >= 2
        }
#else
        // Xcode versions before 27 do not ship the VideoToolbox super-resolution
        // declarations. Keep the app buildable there; the feature is unavailable.
        []
#endif
    }

    @available(macOS 27.0, *)
    static func make(info: VideoInfo, target: SmartEnhanceTarget) -> SmartEnhancePlan? {
#if compiler(>=6.4)
        guard SmartEnhanceExporter.isSupported,
              let sourceWidth = info.width,
              let sourceHeight = info.height,
              sourceWidth > 0,
              sourceHeight > 0 else { return nil }

        let supported = VTLowLatencySuperResolutionScalerConfiguration
            .supportedScaleFactors(frameWidth: sourceWidth, frameHeight: sourceHeight)
        let targetWidth = outputWidth(sourceWidth: sourceWidth, sourceHeight: sourceHeight, targetHeight: target.rawValue)
        let requestedFactor = Float(target.rawValue) / Float(sourceHeight)
        guard target.rawValue > sourceHeight,
              target.rawValue <= Int((Float(sourceHeight) * maximumScaleFactor).rounded(.down)),
              let scaleFactor = supported.sorted().first(where: {
                  $0 <= maximumScaleFactor && $0 >= requestedFactor
              }) else { return nil }
        let enhancedWidth = Int((Float(sourceWidth) * scaleFactor).rounded())
        let enhancedHeight = Int((Float(sourceHeight) * scaleFactor).rounded())
        return SmartEnhancePlan(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            enhancedWidth: enhancedWidth,
            enhancedHeight: enhancedHeight,
            targetWidth: targetWidth,
            targetHeight: target.rawValue,
            scaleFactor: scaleFactor
        )
#else
        nil
#endif
    }

    private static func outputWidth(sourceWidth: Int, sourceHeight: Int, targetHeight: Int) -> Int {
        let rawWidth = Int((Double(sourceWidth) * Double(targetHeight) / Double(sourceHeight)).rounded())
        return max(2, rawWidth.isMultiple(of: 2) ? rawWidth : rawWidth - 1)
    }
}

#if compiler(>=6.4)
@available(macOS 27.0, *)
final class SmartEnhanceExporter {
    /// A timeout can resume export before VideoToolbox calls back. End the
    /// processing session only after its last submitted request completes.
    private final class FrameProcessorSession: @unchecked Sendable {
        let processor: VTFrameProcessor
        private let lock = NSLock()
        private var requestsInFlight = 0
        private var closing = false
        private var ended = false

        init(_ processor: VTFrameProcessor) { self.processor = processor }

        func beginRequest() {
            lock.lock()
            requestsInFlight += 1
            lock.unlock()
        }

        func completeRequest() {
            lock.lock()
            requestsInFlight -= 1
            let shouldEnd = closing && requestsInFlight == 0 && !ended
            if shouldEnd { ended = true }
            lock.unlock()
            if shouldEnd { processor.endSession() }
        }

        func close() {
            lock.lock()
            closing = true
            let shouldEnd = requestsInFlight == 0 && !ended
            if shouldEnd { ended = true }
            lock.unlock()
            if shouldEnd { processor.endSession() }
        }
    }

    /// The callback is Sendable but VideoToolbox's Objective-C parameter type
    /// is not annotated. This reference owns the per-frame buffers until the
    /// framework finishes its asynchronous request.
    private final class FrameParametersReference: @unchecked Sendable {
        let parameters: VTLowLatencySuperResolutionScalerParameters

        init(_ parameters: VTLowLatencySuperResolutionScalerParameters) {
            self.parameters = parameters
        }
    }

    static var isSupported: Bool {
        #if arch(arm64)
        VTLowLatencySuperResolutionScalerConfiguration.isSupported
        #else
        false
        #endif
    }

    enum ExportError: LocalizedError {
        case unavailable
        case invalidSource
        case reader(String)
        case writer(String)
        case pixelBuffer
        case pixelTransfer
        case processingTimeout
        case finalizationTimeout

        var errorDescription: String? {
            switch self {
            case .unavailable: L10n.text("此 Mac 不支持智能增强放大。")
            case .invalidSource, .reader: L10n.text("无法读取用于智能增强的视频。")
            case .writer: L10n.text("无法写入智能增强输出文件。")
            case .pixelBuffer: L10n.text("无法准备智能增强的视频帧。")
            case .pixelTransfer: L10n.text("无法调整智能增强输出尺寸。")
            case .processingTimeout: L10n.text("智能增强处理超时。")
            case .finalizationTimeout: L10n.text("整理输出文件超时。")
            }
        }
    }

    /// Exports video and re-encodes audio to AAC so the native MP4 output stays
    /// broadly playable even when the source uses a different audio codec.
    func export(
        source: URL,
        output: URL,
        plan: SmartEnhancePlan,
        trim: ClipRange?,
        videoBitRate: Int,
        shouldCancel: @escaping () -> Bool,
        onProgress: (Double) -> Void
    ) async throws {
        guard Self.isSupported else { throw ExportError.unavailable }

        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.invalidSource
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let reader = try AVAssetReader(asset: asset)
        if let trim {
            reader.timeRange = CMTimeRange(start: CMTime(seconds: trim.start, preferredTimescale: 600), duration: CMTime(seconds: trim.end - trim.start, preferredTimescale: 600))
        }
        let sourceSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: sourceSettings)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw ExportError.invalidSource }
        reader.add(videoOutput)

        let audioOutput = audioTrack.map { AVAssetReaderTrackOutput(track: $0, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]) }
        if let audioOutput {
            guard reader.canAdd(audioOutput) else { throw ExportError.invalidSource }
            reader.add(audioOutput)
        }

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: plan.targetWidth,
            AVVideoHeightKey: plan.targetHeight,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: videoBitRate]
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw ExportError.writer("The enhanced video output could not be created.") }
        writer.add(videoInput)
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
                kCVPixelBufferWidthKey as String: plan.targetWidth,
                kCVPixelBufferHeightKey as String: plan.targetHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        let pixelTransferSession = try makePixelTransferSession(plan: plan)
        defer {
            if let pixelTransferSession {
                VTPixelTransferSessionInvalidate(pixelTransferSession)
            }
        }

        let audioInput = audioOutput.map { _ in AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]) }
        if let audioInput {
            audioInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(audioInput) else { throw ExportError.writer("The source audio cannot be written to MP4.") }
            writer.add(audioInput)
        }

        let configuration = VTLowLatencySuperResolutionScalerConfiguration(
            frameWidth: plan.sourceWidth,
            frameHeight: plan.sourceHeight,
            scaleFactor: plan.scaleFactor
        )
        let processor = VTFrameProcessor()
        try processor.startSession(configuration: configuration)
        let processorSession = FrameProcessorSession(processor)
        defer { processorSession.close() }

        var audioWriteTask: Task<Void, Error>?
        do {
            if shouldCancel() || Task.isCancelled { throw CancellationError() }
            guard writer.startWriting() else { throw ExportError.writer(writer.error?.localizedDescription ?? "Unable to start the enhanced export.") }
            guard reader.startReading() else { throw ExportError.reader(reader.error?.localizedDescription ?? "Unable to read the source video.") }
            writer.startSession(atSourceTime: trim.map { CMTime(seconds: $0.start, preferredTimescale: 600) } ?? .zero)

            // Feed audio alongside video; the writer may wait for the next
            // audio packet before accepting a high-resolution video frame.
            if let audioOutput, let audioInput {
                audioWriteTask = Task {
                    do {
                        while let sample = audioOutput.copyNextSampleBuffer() {
                            try await waitUntilReady(audioInput, writer: writer, reader: reader, shouldCancel: shouldCancel)
                            guard audioInput.append(sample) else {
                                throw ExportError.writer(writer.error?.localizedDescription ?? "Unable to write source audio.")
                            }
                        }
                        if shouldCancel() || Task.isCancelled { throw CancellationError() }
                        guard reader.status != .failed else {
                            throw ExportError.reader(reader.error?.localizedDescription ?? "Unable to read source audio.")
                        }
                        audioInput.markAsFinished()
                    } catch {
                        // Wake the video producer if audio fails while the
                        // writer is waiting for interleaved media.
                        reader.cancelReading()
                        writer.cancelWriting()
                        throw error
                    }
                }
            }

            let offset = trim?.start ?? 0
            while let sample = videoOutput.copyNextSampleBuffer() {
                if shouldCancel() || Task.isCancelled { throw CancellationError() }
                guard let buffer = CMSampleBufferGetImageBuffer(sample),
                      let sourceFrame = VTFrameProcessorFrame(buffer: buffer, presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample)),
                      let destinationBuffer = makeDestinationBuffer(configuration: configuration),
                      let destinationFrame = VTFrameProcessorFrame(buffer: destinationBuffer, presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample)) else {
                    throw ExportError.pixelBuffer
                }
                let parameters = VTLowLatencySuperResolutionScalerParameters(sourceFrame: sourceFrame, destinationFrame: destinationFrame)
                try await process(session: processorSession, parameters: parameters, shouldCancel: shouldCancel)
                if shouldCancel() || Task.isCancelled { throw CancellationError() }
                let outputBuffer: CVPixelBuffer
                if let pixelTransferSession {
                    guard let resizedBuffer = makeWriterDestinationBuffer(adaptor: pixelBufferAdaptor),
                          VTPixelTransferSessionTransferImage(pixelTransferSession, from: destinationBuffer, to: resizedBuffer) == noErr else {
                        throw ExportError.pixelTransfer
                    }
                    outputBuffer = resizedBuffer
                } else {
                    outputBuffer = destinationBuffer
                }
                try await waitUntilReady(videoInput, writer: writer, reader: reader, shouldCancel: shouldCancel)
                guard pixelBufferAdaptor.append(outputBuffer, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sample)) else {
                    throw ExportError.writer(writer.error?.localizedDescription ?? "Unable to write an enhanced frame.")
                }
                onProgress(max(0, CMSampleBufferGetPresentationTimeStamp(sample).seconds - offset))
            }
            if shouldCancel() || Task.isCancelled { throw CancellationError() }
            guard reader.status != .failed else { throw ExportError.reader(reader.error?.localizedDescription ?? "Unable to read the source video.") }
            videoInput.markAsFinished()

            if let audioWriteTask { try await waitForAudioCompletion(audioWriteTask, shouldCancel: shouldCancel) }
            guard reader.status == .completed else {
                throw ExportError.reader(reader.error?.localizedDescription ?? "The source could not be read completely.")
            }
            if shouldCancel() || Task.isCancelled { throw CancellationError() }
            try await finish(writer: writer, shouldCancel: shouldCancel)
        } catch {
            audioWriteTask?.cancel()
            reader.cancelReading()
            writer.cancelWriting()
            if let audioWriteTask { await waitForAudioShutdown(audioWriteTask) }
            throw error
        }
    }

    private func makeDestinationBuffer(configuration: VTLowLatencySuperResolutionScalerConfiguration) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int((Float(configuration.frameWidth) * configuration.scaleFactor).rounded()),
            Int((Float(configuration.frameHeight) * configuration.scaleFactor).rounded()),
            configuration.supportedPixelFormats.first ?? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            configuration.destinationPixelBufferAttributes as CFDictionary,
            &pixelBuffer
        )
        return status == kCVReturnSuccess ? pixelBuffer : nil
    }

    private func makeWriterDestinationBuffer(adaptor: AVAssetWriterInputPixelBufferAdaptor) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        return status == kCVReturnSuccess ? pixelBuffer : nil
    }

    private func makePixelTransferSession(plan: SmartEnhancePlan) throws -> VTPixelTransferSession? {
        guard plan.enhancedWidth != plan.targetWidth || plan.enhancedHeight != plan.targetHeight else { return nil }
        var pixelTransferSession: VTPixelTransferSession?
        let status = VTPixelTransferSessionCreate(
            allocator: kCFAllocatorDefault,
            pixelTransferSessionOut: &pixelTransferSession
        )
        guard status == noErr, let pixelTransferSession else { throw ExportError.pixelTransfer }
        return pixelTransferSession
    }

    private func process(session: FrameProcessorSession, parameters: VTLowLatencySuperResolutionScalerParameters, shouldCancel: @escaping () -> Bool) async throws {
        let cancellation = ExportWaitCancellation()
        let cancellationMonitor = monitorCancellation(cancellation, shouldCancel: shouldCancel)
        let parametersReference = FrameParametersReference(parameters)
        defer { cancellationMonitor.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = ExportCompletionGate(continuation)
                guard cancellation.install(gate) else { return }
                let watchdog = DispatchWorkItem { gate.fail(ExportError.processingTimeout) }
                cancellation.submit {
                    session.beginRequest()
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 60, execute: watchdog)
                    session.processor.process(parameters: parametersReference.parameters) { _, error in
                        // Retain the buffers and session until VideoToolbox has
                        // really completed this request, even after a timeout.
                        withExtendedLifetime(parametersReference) {}
                        session.completeRequest()
                        watchdog.cancel()
                        if let error { gate.fail(error) }
                        else { gate.succeed() }
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func waitUntilReady(_ input: AVAssetWriterInput, writer: AVAssetWriter, reader: AVAssetReader, shouldCancel: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(30)
        while !input.isReadyForMoreMediaData {
            if shouldCancel() || Task.isCancelled { throw CancellationError() }
            if writer.status == .failed { throw ExportError.writer(writer.error?.localizedDescription ?? "The enhanced export failed.") }
            if writer.status == .cancelled { throw ExportError.writer("The enhanced export was cancelled by the encoder.") }
            if reader.status == .failed { throw ExportError.reader(reader.error?.localizedDescription ?? "The source video could not be read.") }
            if reader.status == .cancelled { throw ExportError.reader("The source reader was cancelled.") }
            if Date() >= deadline { throw ExportError.writer(L10n.text("编码器未响应。")) }
            try await Task.sleep(for: .milliseconds(4))
        }
        if shouldCancel() || Task.isCancelled { throw CancellationError() }
    }

    private func finish(writer: AVAssetWriter, shouldCancel: @escaping () -> Bool) async throws {
        let cancellation = ExportWaitCancellation()
        let cancellationMonitor = monitorCancellation(cancellation, shouldCancel: shouldCancel)
        defer { cancellationMonitor.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = ExportCompletionGate(continuation)
                guard cancellation.install(gate) else { return }
                let writerReference = ExportWriterReference(writer)
                let watchdog = DispatchWorkItem {
                    if gate.fail(ExportError.finalizationTimeout) {
                        writerReference.writer.cancelWriting()
                    }
                }
                cancellation.submit {
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 90, execute: watchdog)
                    writer.finishWriting {
                        watchdog.cancel()
                        let writer = writerReference.writer
                        guard writer.status == .completed else {
                            gate.fail(ExportError.writer(writer.error?.localizedDescription ?? "The enhanced export did not complete."))
                            return
                        }
                        gate.succeed()
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func monitorCancellation(_ cancellation: ExportWaitCancellation, shouldCancel: @escaping () -> Bool) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                if await MainActor.run(body: { shouldCancel() }) {
                    cancellation.cancel()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// The audio producer normally finishes before video. A damaged source can
    /// leave its final read pending, so bound this last join as well.
    private func waitForAudioCompletion(_ task: Task<Void, Error>, shouldCancel: @escaping () -> Bool) async throws {
        let cancellation = ExportWaitCancellation()
        let cancellationMonitor = monitorCancellation(cancellation, shouldCancel: shouldCancel)
        defer { cancellationMonitor.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = ExportCompletionGate(continuation)
                guard cancellation.install(gate) else { return }
                let watchdog = DispatchWorkItem { gate.fail(ExportError.reader("Audio decoding did not complete.")) }
                cancellation.submit {
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 90, execute: watchdog)
                    Task {
                        do {
                            try await task.value
                            watchdog.cancel()
                            gate.succeed()
                        } catch {
                            watchdog.cancel()
                            gate.fail(error)
                        }
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    /// AVAssetReader cancellation normally releases a blocked audio read.
    /// Bound the join so a broken demuxer cannot trap the user's cancel action.
    private func waitForAudioShutdown(_ task: Task<Void, Error>) async {
        _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ExportCompletionGate(continuation)
            let watchdog = DispatchWorkItem { gate.fail(ExportError.reader("Audio reader did not stop.")) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: watchdog)
            Task {
                _ = await task.result
                watchdog.cancel()
                gate.succeed()
            }
        }
    }
}
#else
/// Older Xcode SDKs do not declare the macOS 27 VideoToolbox super-resolution
/// API. This compatibility shell keeps CI and source builds valid while the
/// UI correctly reports that Smart Enhance is unavailable on those SDKs.
@available(macOS 27.0, *)
final class SmartEnhanceExporter {
    static var isSupported: Bool { false }

    func export(
        source: URL,
        output: URL,
        plan: SmartEnhancePlan,
        trim: ClipRange?,
        videoBitRate: Int,
        shouldCancel: @escaping () -> Bool,
        onProgress: (Double) -> Void
    ) async throws {
        throw SmartEnhanceUnsupportedError()
    }
}

private struct SmartEnhanceUnsupportedError: LocalizedError {
    var errorDescription: String? { L10n.text("此 Mac 不支持智能增强放大。") }
}
#endif
