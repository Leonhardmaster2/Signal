import AVFoundation
import Accelerate

// MARK: - Segment Map for Timestamp Remapping

/// Maps trimmed audio positions back to original audio positions
struct SegmentMap: Codable {
    /// Each segment represents a kept portion of audio
    /// - trimmedStart: Start position in the trimmed audio (before speed change)
    /// - originalStart: Start position in the original audio
    /// - duration: Duration of this segment (before speed change)
    struct Segment: Codable {
        let trimmedStart: TimeInterval
        let originalStart: TimeInterval
        let duration: TimeInterval
        
        var trimmedEnd: TimeInterval { trimmedStart + duration }
        var originalEnd: TimeInterval { originalStart + duration }
    }
    
    let segments: [Segment]
    let originalDuration: TimeInterval
    let trimmedDuration: TimeInterval
    
    /// Speed multiplier applied to the trimmed audio (e.g., 1.5 means 1.5x faster)
    let speedMultiplier: Double
    
    /// Remap a timestamp from API response (sped-up audio) back to original audio timeline
    func remapToOriginal(_ apiTime: TimeInterval) -> TimeInterval {
        // First, convert from sped-up time to trimmed time (before speed change)
        let trimmedTime = apiTime * speedMultiplier
        
        // Find the segment that contains this trimmed time
        for segment in segments {
            if trimmedTime >= segment.trimmedStart && trimmedTime < segment.trimmedEnd {
                let offset = trimmedTime - segment.trimmedStart
                return segment.originalStart + offset
            }
        }
        
        // If past all segments, extrapolate from the last segment
        if let lastSegment = segments.last, trimmedTime >= lastSegment.trimmedEnd {
            let offset = trimmedTime - lastSegment.trimmedEnd
            return lastSegment.originalEnd + offset
        }
        
        // Fallback: return the original time (shouldn't happen with valid input)
        return trimmedTime
    }
    
    /// Check if any trimming was actually performed
    var hasTrimming: Bool {
        abs(originalDuration - trimmedDuration) > 0.1 // More than 100ms difference
    }
}

// MARK: - Silence Detection Configuration

struct SilenceDetectionConfig {
    /// Frame duration for RMS analysis (in seconds)
    let frameDuration: TimeInterval
    
    /// Number of standard deviations below mean to consider silence
    let silenceThresholdSD: Float
    
    /// Minimum silence duration to trim (in seconds)
    let minSilenceDuration: TimeInterval
    
    /// Edge buffer to add around kept segments (in seconds)
    let edgeBuffer: TimeInterval
    
    /// Default configuration optimized for speech with smooth transitions
    static let `default` = SilenceDetectionConfig(
        frameDuration: 0.03, // 30ms frames
        silenceThresholdSD: 1.25, // 1.25 SD below mean
        minSilenceDuration: 0.75, // Only trim silence longer than 750ms
        edgeBuffer: 0.15 // 150ms edge buffer for smooth transitions
    )
    
    /// Aggressive configuration for more trimming
    static let aggressive = SilenceDetectionConfig(
        frameDuration: 0.02, // 20ms frames
        silenceThresholdSD: 1.0, // 1.0 SD below mean
        minSilenceDuration: 0.5, // Trim silence longer than 500ms
        edgeBuffer: 0.1 // 100ms edge buffer
    )
}

// MARK: - Silence Trimming Service

enum SilenceTrimmingError: LocalizedError {
    case fileNotFound
    case invalidAudioFormat
    case readFailed
    case writeFailed
    case processingFailed(String)
    case noSpeechDetected
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .invalidAudioFormat:
            return "Invalid audio format for processing"
        case .readFailed:
            return "Failed to read audio file"
        case .writeFailed:
            return "Failed to write trimmed audio"
        case .processingFailed(let msg):
            return "Audio processing failed: \(msg)"
        case .noSpeechDetected:
            return "No speech detected in audio"
        }
    }
}

final class SilenceTrimmingService {
    static let shared = SilenceTrimmingService()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Process audio file and return trimmed version with segment map
    /// - Parameters:
    ///   - sourceURL: Original audio file URL
    ///   - config: Silence detection configuration
    /// - Returns: Tuple of trimmed audio URL and segment map for timestamp remapping
    func trimSilence(
        from sourceURL: URL,
        config: SilenceDetectionConfig = .default
    ) async throws -> (trimmedURL: URL, segmentMap: SegmentMap) {
        // Use standardizedFileURL for consistent path handling
        let standardURL = sourceURL.standardizedFileURL
        let filePath = standardURL.path(percentEncoded: false)
        
        print("✂️ [SilenceTrimming] Checking file at: \(filePath)")
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            print("✂️ [SilenceTrimming] ERROR: File not found at path: \(filePath)")
            throw SilenceTrimmingError.fileNotFound
        }
        
        print("✂️ [SilenceTrimming] File exists, starting processing...")
        
        // Read audio file
        let audioFile = try AVAudioFile(forReading: standardURL)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let frameLength = AVAudioFrameCount(audioFile.length)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            throw SilenceTrimmingError.invalidAudioFormat
        }
        
        try audioFile.read(into: buffer)
        
        // Convert to mono float samples for analysis
        let samples = extractMonoSamples(from: buffer)
        
        // Analyze RMS energy
        let frameSize = Int(sampleRate * config.frameDuration)
        let rmsValues = computeRMSEnergy(samples: samples, frameSize: frameSize)
        
        // Detect speech segments
        let speechFrames = detectSpeechFrames(
            rmsValues: rmsValues,
            thresholdSD: config.silenceThresholdSD
        )
        
        // Convert frame indices to time ranges and merge nearby segments
        let speechRanges = framesToTimeRanges(
            frames: speechFrames,
            frameSize: frameSize,
            sampleRate: sampleRate,
            totalDuration: Double(samples.count) / sampleRate,
            minSilenceDuration: config.minSilenceDuration,
            edgeBuffer: config.edgeBuffer
        )
        
        guard !speechRanges.isEmpty else {
            throw SilenceTrimmingError.noSpeechDetected
        }
        
        // Create segment map
        let segmentMap = createSegmentMap(
            speechRanges: speechRanges,
            originalDuration: Double(samples.count) / sampleRate
        )
        
        // Log trimming statistics
        let silenceTrimmed = segmentMap.originalDuration - segmentMap.trimmedDuration
        let trimPercentage = (silenceTrimmed / segmentMap.originalDuration) * 100
        print("✂️ [SilenceTrimming] Original duration: \(String(format: "%.1f", segmentMap.originalDuration))s")
        print("✂️ [SilenceTrimming] After silence removal: \(String(format: "%.1f", segmentMap.trimmedDuration))s")
        print("✂️ [SilenceTrimming] Silence trimmed: \(String(format: "%.1f", silenceTrimmed))s (\(String(format: "%.1f", trimPercentage))%)")
        
        // Always create processed audio (even without silence trimming, we still speed up)
        let trimmedURL: URL
        if segmentMap.hasTrimming {
            // Create trimmed + sped up audio file
            trimmedURL = try await createTrimmedAudio(
                sourceURL: sourceURL,
                speechRanges: speechRanges,
                format: format
            )
        } else {
            // No silence to trim, but still speed up the audio
            print("✂️ [SilenceTrimming] No significant silence detected, applying speed-up only")
            trimmedURL = try await createSpedUpAudio(
                sourceURL: sourceURL
            )
        }
        
        // Log final API audio duration (after speed-up)
        let apiDuration = segmentMap.trimmedDuration / apiSpeedMultiplier
        let totalReduction = segmentMap.originalDuration - apiDuration
        let totalReductionPercentage = (totalReduction / segmentMap.originalDuration) * 100
        print("✂️ [SilenceTrimming] Speed multiplier: \(apiSpeedMultiplier)x")
        print("✂️ [SilenceTrimming] Final API audio duration: \(String(format: "%.1f", apiDuration))s")
        print("✂️ [SilenceTrimming] Total reduction (silence + speed): \(String(format: "%.1f", totalReduction))s (\(String(format: "%.1f", totalReductionPercentage))%)")
        
        return (trimmedURL, segmentMap)
    }
    
    // MARK: - Audio Analysis
    
    private func extractMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        if channelCount == 1 {
            // Mono: direct copy
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        } else {
            // Stereo+: average channels
            var monoSamples = [Float](repeating: 0, count: frameLength)
            for i in 0..<frameLength {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                monoSamples[i] = sum / Float(channelCount)
            }
            return monoSamples
        }
    }
    
    private func computeRMSEnergy(samples: [Float], frameSize: Int) -> [Float] {
        let frameCount = samples.count / frameSize
        var rmsValues = [Float](repeating: 0, count: frameCount)
        
        for i in 0..<frameCount {
            let startIdx = i * frameSize
            let endIdx = min(startIdx + frameSize, samples.count)
            let frameSlice = Array(samples[startIdx..<endIdx])
            
            // Compute RMS using Accelerate for performance
            var sumSquares: Float = 0
            vDSP_svesq(frameSlice, 1, &sumSquares, vDSP_Length(frameSlice.count))
            rmsValues[i] = sqrt(sumSquares / Float(frameSlice.count))
        }
        
        return rmsValues
    }
    
    private func detectSpeechFrames(rmsValues: [Float], thresholdSD: Float) -> [Bool] {
        // Filter out zero-amplitude frames for statistics
        let nonZeroRMS = rmsValues.filter { $0 > 0.0001 }
        
        guard !nonZeroRMS.isEmpty else {
            return [Bool](repeating: false, count: rmsValues.count)
        }
        
        // Compute mean and standard deviation
        var mean: Float = 0
        var stdDev: Float = 0
        vDSP_normalize(nonZeroRMS, 1, nil, 1, &mean, &stdDev, vDSP_Length(nonZeroRMS.count))
        
        // Threshold: mean - (thresholdSD * stdDev)
        let threshold = max(0, mean - thresholdSD * stdDev)
        
        // Mark frames as speech (above threshold) or silence (below threshold)
        return rmsValues.map { $0 >= threshold }
    }
    
    private func framesToTimeRanges(
        frames: [Bool],
        frameSize: Int,
        sampleRate: Double,
        totalDuration: TimeInterval,
        minSilenceDuration: TimeInterval,
        edgeBuffer: TimeInterval
    ) -> [(start: TimeInterval, end: TimeInterval)] {
        let frameDuration = Double(frameSize) / sampleRate
        var speechRanges: [(start: TimeInterval, end: TimeInterval)] = []
        
        var inSpeech = false
        var speechStart: TimeInterval = 0
        
        for (index, isSpeech) in frames.enumerated() {
            let time = Double(index) * frameDuration
            
            if isSpeech && !inSpeech {
                // Speech started
                speechStart = time
                inSpeech = true
            } else if !isSpeech && inSpeech {
                // Speech ended
                let speechEnd = time
                speechRanges.append((start: speechStart, end: speechEnd))
                inSpeech = false
            }
        }
        
        // Handle speech that extends to end of file
        if inSpeech {
            speechRanges.append((start: speechStart, end: totalDuration))
        }
        
        // Merge ranges that are separated by less than minSilenceDuration
        var mergedRanges: [(start: TimeInterval, end: TimeInterval)] = []
        
        for range in speechRanges {
            if let last = mergedRanges.last {
                let gap = range.start - last.end
                if gap < minSilenceDuration {
                    // Merge with previous range
                    mergedRanges[mergedRanges.count - 1] = (start: last.start, end: range.end)
                } else {
                    mergedRanges.append(range)
                }
            } else {
                mergedRanges.append(range)
            }
        }
        
        // Add edge buffers and clamp to valid range
        return mergedRanges.map { range in
            let bufferedStart = max(0, range.start - edgeBuffer)
            let bufferedEnd = min(totalDuration, range.end + edgeBuffer)
            return (start: bufferedStart, end: bufferedEnd)
        }
    }
    
    /// Speed multiplier for audio sent to API (1.5 = 1.5x faster)
    private let apiSpeedMultiplier: Double = 1.5
    
    private func createSegmentMap(
        speechRanges: [(start: TimeInterval, end: TimeInterval)],
        originalDuration: TimeInterval
    ) -> SegmentMap {
        var segments: [SegmentMap.Segment] = []
        var trimmedPosition: TimeInterval = 0
        
        for range in speechRanges {
            let duration = range.end - range.start
            segments.append(SegmentMap.Segment(
                trimmedStart: trimmedPosition,
                originalStart: range.start,
                duration: duration
            ))
            trimmedPosition += duration
        }
        
        return SegmentMap(
            segments: segments,
            originalDuration: originalDuration,
            trimmedDuration: trimmedPosition,
            speedMultiplier: apiSpeedMultiplier
        )
    }
    
    // MARK: - Trimmed Audio Creation
    
    private func createTrimmedAudio(
        sourceURL: URL,
        speechRanges: [(start: TimeInterval, end: TimeInterval)],
        format: AVAudioFormat
    ) async throws -> URL {
        // Create output file URL
        let outputFilename = "trimmed_\(UUID().uuidString).m4a"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFilename)
        
        // Use AVAssetExportSession for efficient audio extraction
        let asset = AVAsset(url: sourceURL)
        
        // Create composition with only speech segments
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw SilenceTrimmingError.processingFailed("Failed to create composition track")
        }
        
        let assetTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = assetTracks.first else {
            throw SilenceTrimmingError.invalidAudioFormat
        }
        
        var insertTime = CMTime.zero
        
        for range in speechRanges {
            let startTime = CMTime(seconds: range.start, preferredTimescale: 44100)
            let endTime = CMTime(seconds: range.end, preferredTimescale: 44100)
            let timeRange = CMTimeRange(start: startTime, end: endTime)
            
            do {
                try compositionTrack.insertTimeRange(timeRange, of: audioTrack, at: insertTime)
                insertTime = insertTime + timeRange.duration
            } catch {
                throw SilenceTrimmingError.processingFailed("Failed to insert time range: \(error.localizedDescription)")
            }
        }
        
        // Speed up audio to reduce API processing time
        let originalDuration = composition.duration
        let scaledDuration = CMTimeMultiplyByFloat64(originalDuration, multiplier: 1.0 / apiSpeedMultiplier)
        composition.scaleTimeRange(
            CMTimeRange(start: .zero, duration: originalDuration),
            toDuration: scaledDuration
        )
        
        // Export the composition
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw SilenceTrimmingError.processingFailed("Failed to create export session")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        await exportSession.export()
        
        switch exportSession.status {
        case .completed:
            return outputURL
        case .failed:
            throw SilenceTrimmingError.writeFailed
        case .cancelled:
            throw SilenceTrimmingError.processingFailed("Export cancelled")
        default:
            throw SilenceTrimmingError.processingFailed("Unknown export status")
        }
    }
    
    // MARK: - Speed Up Only (no trimming)
    
    private func createSpedUpAudio(sourceURL: URL) async throws -> URL {
        // Create output file URL
        let outputFilename = "spedup_\(UUID().uuidString).m4a"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFilename)
        
        let asset = AVAsset(url: sourceURL)
        
        // Create composition with the full audio
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw SilenceTrimmingError.processingFailed("Failed to create composition track")
        }
        
        let assetTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = assetTracks.first else {
            throw SilenceTrimmingError.invalidAudioFormat
        }
        
        let duration = try await asset.load(.duration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        
        do {
            try compositionTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        } catch {
            throw SilenceTrimmingError.processingFailed("Failed to insert audio: \(error.localizedDescription)")
        }
        
        // Speed up audio
        let originalDuration = composition.duration
        let scaledDuration = CMTimeMultiplyByFloat64(originalDuration, multiplier: 1.0 / apiSpeedMultiplier)
        composition.scaleTimeRange(
            CMTimeRange(start: .zero, duration: originalDuration),
            toDuration: scaledDuration
        )
        
        // Export the composition
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw SilenceTrimmingError.processingFailed("Failed to create export session")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        await exportSession.export()
        
        switch exportSession.status {
        case .completed:
            return outputURL
        case .failed:
            throw SilenceTrimmingError.writeFailed
        case .cancelled:
            throw SilenceTrimmingError.processingFailed("Export cancelled")
        default:
            throw SilenceTrimmingError.processingFailed("Unknown export status")
        }
    }
    
    // MARK: - Audio Compression for Upload

    /// Re-encode audio at a lower sample rate and bitrate for efficient API upload.
    /// Speech remains fully intelligible at 16kHz mono — most speech content is below 8kHz.
    /// This typically reduces file size by 4-6x compared to the 44.1kHz high-quality original.
    func compressForUpload(sourceURL: URL) async throws -> URL {
        let outputFilename = "compressed_\(UUID().uuidString).m4a"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFilename)

        let asset = AVAsset(url: sourceURL)
        let assetTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = assetTracks.first else {
            throw SilenceTrimmingError.invalidAudioFormat
        }

        // Configure AVAssetWriter with speech-optimized settings
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,         // 16kHz — plenty for speech recognition
            AVNumberOfChannelsKey: 1,          // Mono
            AVEncoderBitRateKey: 32000,        // 32kbps — clear speech at minimal size
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        // Configure reader
        let reader = try AVAssetReader(asset: asset)
        let readerSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        reader.add(readerOutput)

        // Start reading and writing
        guard reader.startReading() else {
            throw SilenceTrimmingError.processingFailed("Failed to start reading: \(reader.error?.localizedDescription ?? "unknown")")
        }
        guard writer.startWriting() else {
            throw SilenceTrimmingError.processingFailed("Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")")
        }
        writer.startSession(atSourceTime: .zero)

        // Process in a background task
        return try await withCheckedThrowingContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.trace.audioCompress")) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                // Log compression ratio
                                if let sourceSize = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64,
                                   let outputSize = try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64 {
                                    let ratio = Double(sourceSize) / Double(max(outputSize, 1))
                                    print("🗜️ [Compress] \(sourceSize / 1024)KB → \(outputSize / 1024)KB (\(String(format: "%.1f", ratio))x smaller)")
                                }
                                continuation.resume(returning: outputURL)
                            } else {
                                continuation.resume(throwing: SilenceTrimmingError.processingFailed(
                                    "Compression failed: \(writer.error?.localizedDescription ?? "unknown")"
                                ))
                            }
                        }
                        return
                    }
                }
            }
        }
    }

    // MARK: - Cleanup

    /// Remove temporary trimmed audio file
    func cleanupTrimmedFile(at url: URL) {
        // Only delete files in temporary directory
        if url.path.contains(FileManager.default.temporaryDirectory.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
