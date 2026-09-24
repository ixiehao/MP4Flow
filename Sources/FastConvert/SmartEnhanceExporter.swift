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

    func succeed() { resolve(.success(())) }
    func fail(_ error: Error) { resolve(.failure(error)) }

    private func resolve(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        guard let continuation else { return }
        continuation.resume(with: result)
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
    }

    @available(macOS 27.0, *)
    static func make(info: VideoInfo, target: SmartEnhanceTarget) -> SmartEnhancePlan? {
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
    }

    private static func outputWidth(sourceWidth: Int, sourceHeight: Int, targetHeight: Int) -> Int {
        let rawWidth = Int((Double(sourceWidth) * Double(targetHeight) / Double(sourceHeight)).rounded())
        return max(2, rawWidth.isMultiple(of: 2) ? rawWidth : rawWidth - 1)
    }
}

@available(macOS 27.0, *)
final class SmartEnhanceExporter {
    static var isSupported: Bool {
        #if arch(arm64)
        VTLowLatencySuperResolutionScalerConfiguration.isSupported
        #else
        false
        #endif
    }

    private enum ExportError: LocalizedError {
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

        guard writer.startWriting() else { throw ExportError.writer(writer.error?.localizedDescription ?? "Unable to start the enhanced export.") }
        guard reader.startReading() else { throw ExportError.reader(reader.error?.localizedDescription ?? "Unable to read the source video.") }
        writer.startSession(atSourceTime: trim.map { CMTime(seconds: $0.start, preferredTimescale: 600) } ?? .zero)

        // Asset writers apply interleaving pressure while encoding. Feed audio
        // alongside enhanced video so a high-resolution video input cannot
        // wait forever for an audio packet that this exporter held until last.
        let audioWriteTask: Task<Void, Error>? = if let audioOutput, let audioInput {
            Task {
                while let sample = audioOutput.copyNextSampleBuffer() {
                    if shouldCancel() || Task.isCancelled {
                        reader.cancelReading()
                        writer.cancelWriting()
                        throw CancellationError()
                    }
                    try await waitUntilReady(audioInput, writer: writer, reader: reader, shouldCancel: shouldCancel)
                    guard audioInput.append(sample) else {
                        throw ExportError.writer(writer.error?.localizedDescription ?? "Unable to write source audio.")
                    }
                }
                audioInput.markAsFinished()
            }
        } else {
            nil
        }
        defer { audioWriteTask?.cancel() }

        let configuration = VTLowLatencySuperResolutionScalerConfiguration(
            frameWidth: plan.sourceWidth,
            frameHeight: plan.sourceHeight,
            scaleFactor: plan.scaleFactor
        )
        let processor = VTFrameProcessor()
        try processor.startSession(configuration: configuration)
        defer { processor.endSession() }

        let offset = trim?.start ?? 0
        while let sample = videoOutput.copyNextSampleBuffer() {
            if shouldCancel() {
                reader.cancelReading()
                writer.cancelWriting()
                throw CancellationError()
            }
            guard let buffer = CMSampleBufferGetImageBuffer(sample),
                  let sourceFrame = VTFrameProcessorFrame(buffer: buffer, presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample)),
                  let destinationBuffer = makeDestinationBuffer(configuration: configuration),
                  let destinationFrame = VTFrameProcessorFrame(buffer: destinationBuffer, presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample)) else {
                throw ExportError.pixelBuffer
            }
            let parameters = VTLowLatencySuperResolutionScalerParameters(sourceFrame: sourceFrame, destinationFrame: destinationFrame)
            try await process(processor: processor, parameters: parameters)
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
        guard reader.status != .failed else { throw ExportError.reader(reader.error?.localizedDescription ?? "Unable to read the source video.") }
        videoInput.markAsFinished()

        if let audioWriteTask { try await audioWriteTask.value }
        guard reader.status != .failed else { throw ExportError.reader(reader.error?.localizedDescription ?? "Unable to read source audio.") }
        try await finish(writer: writer)
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

    private func process(processor: VTFrameProcessor, parameters: VTLowLatencySuperResolutionScalerParameters) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ExportCompletionGate(continuation)
            let watchdog = DispatchWorkItem { gate.fail(ExportError.processingTimeout) }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 12, execute: watchdog)
            processor.process(parameters: parameters) { _, error in
                watchdog.cancel()
                if let error { gate.fail(error) }
                else { gate.succeed() }
            }
        }
    }

    private func waitUntilReady(_ input: AVAssetWriterInput, writer: AVAssetWriter, reader: AVAssetReader, shouldCancel: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !input.isReadyForMoreMediaData {
            if shouldCancel() || Task.isCancelled { throw CancellationError() }
            if writer.status == .failed { throw ExportError.writer(writer.error?.localizedDescription ?? "The enhanced export failed.") }
            if reader.status == .failed { throw ExportError.reader(reader.error?.localizedDescription ?? "The source video could not be read.") }
            if Date() >= deadline { throw ExportError.writer(L10n.text("编码器未响应。")) }
            try await Task.sleep(for: .milliseconds(4))
        }
    }

    private func finish(writer: AVAssetWriter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ExportCompletionGate(continuation)
            let writerReference = ExportWriterReference(writer)
            let watchdog = DispatchWorkItem {
                writer.cancelWriting()
                gate.fail(ExportError.finalizationTimeout)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 12, execute: watchdog)
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
}
