import AVFoundation
import Atomics
import Foundation

public final class AudioPlaybackController: @unchecked Sendable {
    public static let supportedSampleRate: Double = 44_100
    public static let supportedChannelCount: AVAudioChannelCount = 2

    private static let bufferDurationSeconds: Double = 1
    private static let startupPrebufferDurationSeconds: Double = 0.2
    private static let bufferCapacityFrames = Int(
        supportedSampleRate * bufferDurationSeconds)
    private static let startupPrebufferFrames = Int(
        supportedSampleRate * startupPrebufferDurationSeconds)

    private let ringBuffer: AudioRingBuffer
    private let lifecycleLock = NSLock()
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private let packetCount = ManagedAtomic<UInt64>(0)
    private let sequenceGapPackets = ManagedAtomic<UInt64>(0)
    private let outOfOrderPackets = ManagedAtomic<UInt64>(0)
    private let totalPacketFrames = ManagedAtomic<UInt64>(0)
    private let sourceIntervalCount = ManagedAtomic<UInt64>(0)
    private let sourceIntervalTotalNanoseconds = ManagedAtomic<UInt64>(0)
    private let sourceIntervalMinimumNanoseconds = ManagedAtomic<UInt64>(UInt64.max)
    private let sourceIntervalMaximumNanoseconds = ManagedAtomic<UInt64>(0)
    private let arrivalIntervalCount = ManagedAtomic<UInt64>(0)
    private let arrivalIntervalTotalNanoseconds = ManagedAtomic<UInt64>(0)
    private let arrivalIntervalMinimumNanoseconds = ManagedAtomic<UInt64>(UInt64.max)
    private let arrivalIntervalMaximumNanoseconds = ManagedAtomic<UInt64>(0)
    private let renderCallbackCount = ManagedAtomic<UInt64>(0)
    private let hasLastPacket = ManagedAtomic<Bool>(false)
    private let lastPacketSequence = ManagedAtomic<UInt64>(0)
    private let lastPacketTimestampNanoseconds = ManagedAtomic<UInt64>(0)
    private let lastPacketFrameCount = ManagedAtomic<UInt32>(0)
    private let lastPacketArrivalNanoseconds = ManagedAtomic<UInt64>(0)

    public init() {
        ringBuffer = AudioRingBuffer(
            capacityFrames: Self.bufferCapacityFrames,
            channelCount: Int(Self.supportedChannelCount),
            minimumPlaybackFrames: Self.startupPrebufferFrames)

        configurationObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("AVAudioEngineConfigurationChangeNotification"),
            object: nil,
            queue: nil) { [weak self] notification in
                self?.handleConfigurationChange(notification)
            }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    public func start() throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        try startLocked()
    }

    private func startLocked() throws {
        if let engine, engine.isRunning {
            return
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.supportedSampleRate,
            channels: Self.supportedChannelCount,
            interleaved: false) else {
            throw AudioPlaybackError.unsupportedFormat
        }

        let audioEngine = AVAudioEngine()
        let ringBuffer = ringBuffer
        let sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            self.renderCallbackCount.wrappingIncrement(ordering: .relaxed)
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            ringBuffer.read(into: buffers, frameCount: Int(frameCount))
            return noErr
        }

        audioEngine.attach(sourceNode)
        audioEngine.connect(sourceNode, to: audioEngine.mainMixerNode, format: nil)
        audioEngine.connect(audioEngine.mainMixerNode, to: audioEngine.outputNode, format: nil)
        audioEngine.mainMixerNode.outputVolume = 1
        audioEngine.prepare()
        try audioEngine.start()
        engine = audioEngine
    }

    public func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        engine?.stop()
        engine = nil
        ringBuffer.clear()
    }

    private func handleConfigurationChange(_ notification: Notification) {
        guard let changedEngine = notification.object as? AVAudioEngine else {
            return
        }

        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        guard engine === changedEngine else {
            return
        }

        changedEngine.stop()
        engine = nil
        ringBuffer.clear()

        do {
            try startLocked()
        } catch {
            // The next configuration notification or an explicit start can retry.
        }
    }

    public func accept(_ packet: AudioPacket) {
        guard packet.descriptor.sampleRate == UInt32(Self.supportedSampleRate),
              packet.descriptor.channelCount == Self.supportedChannelCount,
              packet.descriptor.sampleFormat == .pcmSigned16LittleEndian else {
            return
        }

        record(packet: packet)

        let sampleCount = Int(packet.frameCount) * Int(packet.descriptor.channelCount)
        var samples = Array(repeating: Float.zero, count: sampleCount)
        packet.payload.withUnsafeBytes { rawBuffer in
            let source = rawBuffer.bindMemory(to: UInt8.self)
            for sampleIndex in 0..<sampleCount {
                let offset = sampleIndex * MemoryLayout<Int16>.size
                let bits = UInt16(source[offset]) | UInt16(source[offset + 1]) << 8
                let value = Int16(bitPattern: bits)
                samples[sampleIndex] = Float(value) / Float(Int16.max)
            }
        }

        samples.withUnsafeBufferPointer { buffer in
            _ = ringBuffer.write(buffer, frameCount: Int(packet.frameCount))
        }
    }

    public func metrics() -> AudioPlaybackMetrics {
        let hasLastPacket = hasLastPacket.load(ordering: .acquiring)
        return AudioPlaybackMetrics(
            packetCount: packetCount.load(ordering: .acquiring),
            sequenceGapPackets: sequenceGapPackets.load(ordering: .acquiring),
            outOfOrderPackets: outOfOrderPackets.load(ordering: .acquiring),
            totalPacketFrames: totalPacketFrames.load(ordering: .acquiring),
            sourcePacketIntervalNanoseconds: intervalMetrics(
                count: sourceIntervalCount,
                total: sourceIntervalTotalNanoseconds,
                minimum: sourceIntervalMinimumNanoseconds,
                maximum: sourceIntervalMaximumNanoseconds),
            arrivalPacketIntervalNanoseconds: intervalMetrics(
                count: arrivalIntervalCount,
                total: arrivalIntervalTotalNanoseconds,
                minimum: arrivalIntervalMinimumNanoseconds,
                maximum: arrivalIntervalMaximumNanoseconds),
            renderCallbackCount: renderCallbackCount.load(ordering: .acquiring),
            lastPacketSequence: hasLastPacket
                ? lastPacketSequence.load(ordering: .acquiring)
                : nil,
            lastPacketTimestampNanoseconds: hasLastPacket
                ? lastPacketTimestampNanoseconds.load(ordering: .acquiring)
                : nil,
            lastPacketFrameCount: hasLastPacket
                ? lastPacketFrameCount.load(ordering: .acquiring)
                : nil,
            ringBuffer: ringBuffer.metrics())
    }

    private func record(packet: AudioPacket) {
        let arrivalNanoseconds = DispatchTime.now().uptimeNanoseconds
        if hasLastPacket.load(ordering: .acquiring) {
            let previousSequence = lastPacketSequence.load(ordering: .relaxed)
            if packet.sequence > previousSequence,
               packet.sequence - previousSequence > 1 {
                increment(
                    sequenceGapPackets,
                    by: packet.sequence - previousSequence - 1)
            } else if packet.sequence <= previousSequence {
                increment(outOfOrderPackets, by: 1)
            }

            let previousSourceTimestamp = lastPacketTimestampNanoseconds.load(ordering: .relaxed)
            if packet.timestampNanoseconds > previousSourceTimestamp {
                recordInterval(
                    packet.timestampNanoseconds - previousSourceTimestamp,
                    count: sourceIntervalCount,
                    total: sourceIntervalTotalNanoseconds,
                    minimum: sourceIntervalMinimumNanoseconds,
                    maximum: sourceIntervalMaximumNanoseconds)
            }

            let previousArrival = lastPacketArrivalNanoseconds.load(ordering: .relaxed)
            if arrivalNanoseconds > previousArrival {
                recordInterval(
                    arrivalNanoseconds - previousArrival,
                    count: arrivalIntervalCount,
                    total: arrivalIntervalTotalNanoseconds,
                    minimum: arrivalIntervalMinimumNanoseconds,
                    maximum: arrivalIntervalMaximumNanoseconds)
            }
        }

        increment(packetCount, by: 1)
        increment(totalPacketFrames, by: UInt64(packet.frameCount))
        lastPacketSequence.store(packet.sequence, ordering: .relaxed)
        lastPacketTimestampNanoseconds.store(
            packet.timestampNanoseconds,
            ordering: .relaxed)
        lastPacketFrameCount.store(packet.frameCount, ordering: .relaxed)
        lastPacketArrivalNanoseconds.store(arrivalNanoseconds, ordering: .relaxed)
        hasLastPacket.store(true, ordering: .releasing)
    }

    private func recordInterval(
        _ intervalNanoseconds: UInt64,
        count: ManagedAtomic<UInt64>,
        total: ManagedAtomic<UInt64>,
        minimum: ManagedAtomic<UInt64>,
        maximum: ManagedAtomic<UInt64>) {
        count.wrappingIncrement(ordering: .relaxed)
        total.wrappingIncrement(by: intervalNanoseconds, ordering: .relaxed)
        updateMinimum(minimum, value: intervalNanoseconds)
        updateMaximum(maximum, value: intervalNanoseconds)
    }

    private func intervalMetrics(
        count: ManagedAtomic<UInt64>,
        total: ManagedAtomic<UInt64>,
        minimum: ManagedAtomic<UInt64>,
        maximum: ManagedAtomic<UInt64>) -> AudioPacketIntervalMetrics {
        let intervalCount = count.load(ordering: .acquiring)
        return AudioPacketIntervalMetrics(
            count: intervalCount,
            minimumNanoseconds: intervalCount == 0
                ? nil
                : minimum.load(ordering: .acquiring),
            averageNanoseconds: intervalCount == 0
                ? nil
                : total.load(ordering: .acquiring) / intervalCount,
            maximumNanoseconds: intervalCount == 0
                ? nil
                : maximum.load(ordering: .acquiring))
    }

    private func increment(
        _ counter: ManagedAtomic<UInt64>,
        by value: UInt64) {
        counter.wrappingIncrement(by: value, ordering: .relaxed)
    }

    private func updateMinimum(
        _ metric: ManagedAtomic<UInt64>,
        value: UInt64) {
        while true {
            let current = metric.load(ordering: .relaxed)
            guard value < current else {
                return
            }
            let result = metric.compareExchange(
                expected: current,
                desired: value,
                ordering: .relaxed)
            if result.exchanged {
                return
            }
        }
    }

    private func updateMaximum(
        _ metric: ManagedAtomic<UInt64>,
        value: UInt64) {
        while true {
            let current = metric.load(ordering: .relaxed)
            guard value > current else {
                return
            }
            let result = metric.compareExchange(
                expected: current,
                desired: value,
                ordering: .relaxed)
            if result.exchanged {
                return
            }
        }
    }
}
