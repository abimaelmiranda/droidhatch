import Atomics
import AVFoundation
import Foundation

public final class AudioRingBuffer: @unchecked Sendable {
    private let channelCount: Int
    private let capacityFrames: Int
    private let minimumPlaybackFrames: Int
    private var storage: [Float]
    private let readFrame = ManagedAtomic<Int>(0)
    private let writeFrame = ManagedAtomic<Int>(0)
    private let totalWrittenFrames = ManagedAtomic<UInt64>(0)
    private let totalReadFrames = ManagedAtomic<UInt64>(0)
    private let underrunFrames = ManagedAtomic<UInt64>(0)
    private let underrunEvents = ManagedAtomic<UInt64>(0)
    private let overflowFrames = ManagedAtomic<UInt64>(0)
    private let playbackStarted = ManagedAtomic<Bool>(false)
    private let minimumOccupiedFrames: ManagedAtomic<Int>
    private let maximumOccupiedFrames = ManagedAtomic<Int>(0)

    public init(
        capacityFrames: Int,
        channelCount: Int,
        minimumPlaybackFrames: Int) {
        precondition(capacityFrames > 0)
        precondition(channelCount > 0)
        precondition(minimumPlaybackFrames >= 0)
        precondition(minimumPlaybackFrames <= capacityFrames)
        self.capacityFrames = capacityFrames
        self.channelCount = channelCount
        self.minimumPlaybackFrames = minimumPlaybackFrames
        storage = Array(repeating: 0, count: capacityFrames * channelCount)
        minimumOccupiedFrames = ManagedAtomic(capacityFrames)
    }

    @discardableResult
    public func write(_ samples: UnsafeBufferPointer<Float>, frameCount: Int) -> Int {
        guard frameCount > 0 else {
            return 0
        }

        let read = readFrame.load(ordering: .acquiring)
        let write = writeFrame.load(ordering: .relaxed)
        let occupied = write - read
        let writableFrames = capacityFrames - occupied
        let framesToWrite = min(frameCount, max(writableFrames, 0))
        if framesToWrite < frameCount {
            increment(overflowFrames, by: UInt64(frameCount - framesToWrite))
        }
        guard framesToWrite > 0 else {
            return 0
        }

        for frame in 0..<framesToWrite {
            let storageFrame = (write + frame) % capacityFrames
            let sourceOffset = frame * channelCount
            let storageOffset = storageFrame * channelCount
            for channel in 0..<channelCount {
                storage[storageOffset + channel] = samples[sourceOffset + channel]
            }
        }

        writeFrame.store(write + framesToWrite, ordering: .releasing)
        increment(totalWrittenFrames, by: UInt64(framesToWrite))
        updateMaximum(
            maximumOccupiedFrames,
            value: min(capacityFrames, occupied + framesToWrite))
        return framesToWrite
    }

    @discardableResult
    public func read(
        into destination: UnsafeMutableBufferPointer<Float>,
        frameCount: Int) -> Int {
        guard frameCount > 0 else {
            return 0
        }

        let read = readFrame.load(ordering: .relaxed)
        let write = writeFrame.load(ordering: .acquiring)
        let availableFrames = write - read

        let framesToRead = min(frameCount, max(availableFrames, 0))
        if framesToRead < frameCount {
            if playbackStarted.load(ordering: .acquiring) {
                let missingFrames = UInt64(frameCount - framesToRead)
                increment(underrunFrames, by: missingFrames)
                underrunEvents.wrappingIncrement(ordering: .relaxed)
            }
        }
        guard framesToRead > 0 else {
            return 0
        }

        for frame in 0..<framesToRead {
            let storageFrame = (read + frame) % capacityFrames
            let destinationOffset = frame * channelCount
            let storageOffset = storageFrame * channelCount
            for channel in 0..<channelCount {
                destination[destinationOffset + channel] = storage[storageOffset + channel]
            }
        }

        readFrame.store(read + framesToRead, ordering: .releasing)
        increment(totalReadFrames, by: UInt64(framesToRead))
        updateMinimum(
            minimumOccupiedFrames,
            value: max(0, availableFrames - framesToRead))
        return framesToRead
    }

    @discardableResult
    public func read(
        into audioBufferList: UnsafeMutableAudioBufferListPointer,
        frameCount: Int) -> Int {
        guard frameCount > 0 else {
            return 0
        }

        let read = readFrame.load(ordering: .relaxed)
        let write = writeFrame.load(ordering: .acquiring)
        let availableFrames = write - read

        if !playbackStarted.load(ordering: .acquiring) {
            guard availableFrames >= minimumPlaybackFrames else {
                renderSilence(
                    into: audioBufferList,
                    frameCount: frameCount)
                return 0
            }
            playbackStarted.store(true, ordering: .releasing)
        }

        let framesToRead = min(frameCount, max(availableFrames, 0))
        if framesToRead < frameCount {
            let missingFrames = UInt64(frameCount - framesToRead)
            increment(underrunFrames, by: missingFrames)
            underrunEvents.wrappingIncrement(ordering: .relaxed)
        }
        let bufferCount = audioBufferList.count

        for channel in 0..<channelCount {
            let bufferIndex = bufferCount == 1 ? 0 : channel
            guard let data = audioBufferList[bufferIndex].mData else {
                return 0
            }

            let output = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                let storageFrame = (read + frame) % capacityFrames
                let storageOffset = storageFrame * channelCount + channel
                let outputOffset = bufferCount == 1
                    ? frame * channelCount + channel
                    : frame

                output[outputOffset] = frame < framesToRead
                    ? storage[storageOffset]
                    : 0
            }
        }

        readFrame.store(read + framesToRead, ordering: .releasing)
        increment(totalReadFrames, by: UInt64(framesToRead))
        updateMinimum(
            minimumOccupiedFrames,
            value: max(0, availableFrames - framesToRead))
        return framesToRead
    }

    public func metrics() -> AudioRingBufferMetrics {
        let read = readFrame.load(ordering: .acquiring)
        let write = writeFrame.load(ordering: .acquiring)
        let occupied = min(capacityFrames, max(0, write - read))
        return AudioRingBufferMetrics(
            capacityFrames: capacityFrames,
            occupiedFrames: occupied,
            minimumOccupiedFrames: minimumOccupiedFrames.load(ordering: .acquiring),
            maximumOccupiedFrames: maximumOccupiedFrames.load(ordering: .acquiring),
            totalWrittenFrames: totalWrittenFrames.load(ordering: .acquiring),
            totalReadFrames: totalReadFrames.load(ordering: .acquiring),
            underrunFrames: underrunFrames.load(ordering: .acquiring),
            underrunEvents: underrunEvents.load(ordering: .acquiring),
            overflowFrames: overflowFrames.load(ordering: .acquiring),
            playbackStarted: playbackStarted.load(ordering: .acquiring))
    }

    public func clear() {
        let write = writeFrame.load(ordering: .acquiring)
        readFrame.store(write, ordering: .releasing)
        resetPlaybackGate()
        updateMinimum(minimumOccupiedFrames, value: 0)
    }

    public func resetPlaybackGate() {
        playbackStarted.store(false, ordering: .releasing)
    }

    private func renderSilence(
        into audioBufferList: UnsafeMutableAudioBufferListPointer,
        frameCount: Int) {
        let bufferCount = audioBufferList.count
        for channel in 0..<channelCount {
            let bufferIndex = bufferCount == 1 ? 0 : channel
            guard let data = audioBufferList[bufferIndex].mData else {
                continue
            }

            let output = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                let outputOffset = bufferCount == 1
                    ? frame * channelCount + channel
                    : frame
                output[outputOffset] = 0
            }
        }
    }

    private func increment(
        _ counter: ManagedAtomic<UInt64>,
        by value: UInt64) {
        counter.wrappingIncrement(by: value, ordering: .relaxed)
    }

    private func updateMinimum(
        _ metric: ManagedAtomic<Int>,
        value: Int) {
        let current = metric.load(ordering: .relaxed)
        if value < current {
            metric.store(value, ordering: .relaxed)
        }
    }

    private func updateMaximum(
        _ metric: ManagedAtomic<Int>,
        value: Int) {
        let current = metric.load(ordering: .relaxed)
        if value > current {
            metric.store(value, ordering: .relaxed)
        }
    }
}
