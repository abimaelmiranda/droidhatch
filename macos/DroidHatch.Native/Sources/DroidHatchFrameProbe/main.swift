import DroidHatchFrameTransport
import Foundation

func isBlack(_ pixels: Data) -> Bool {
    var offset = 0
    while offset + 3 < pixels.count {
        if pixels[offset] != 0 || pixels[offset + 1] != 0 || pixels[offset + 2] != 0 {
            return false
        }
        offset += 4
    }
    return true
}

func parseOptions() -> ProbeOptions? {
    var host = "127.0.0.1"
    var port: UInt16 = 5732
    var frameCount: Int? = 30
    var durationSeconds: Double?
    var snapshotIntervalSeconds: Double?
    var readTimeoutSeconds = 30.0
    var continueOnTimeout = false
    var outputDirectory = URL(fileURLWithPath: "/private/tmp/droidhatch-frame-probe")
    var index = 1

    while index < CommandLine.arguments.count {
        let argument = CommandLine.arguments[index]
        if argument == "--continue-on-timeout" {
            continueOnTimeout = true
            index += 1
            continue
        }

        guard index + 1 < CommandLine.arguments.count else {
            return nil
        }
        let value = CommandLine.arguments[index + 1]
        switch argument {
        case "--host":
            host = value
        case "--port":
            guard let parsed = UInt16(value) else { return nil }
            port = parsed
        case "--frames":
            guard let parsed = Int(value), parsed > 0 else { return nil }
            frameCount = parsed
            durationSeconds = nil
        case "--duration":
            guard let parsed = Double(value), parsed > 0 else { return nil }
            durationSeconds = parsed
            frameCount = nil
        case "--snapshot-interval":
            guard let parsed = Double(value), parsed > 0 else { return nil }
            snapshotIntervalSeconds = parsed
        case "--read-timeout":
            guard let parsed = Double(value), parsed > 0 else { return nil }
            readTimeoutSeconds = parsed
        case "--output":
            outputDirectory = URL(fileURLWithPath: value, isDirectory: true)
        default:
            return nil
        }
        index += 2
    }

    return ProbeOptions(
        host: host,
        port: port,
        frameCount: frameCount,
        durationSeconds: durationSeconds,
        snapshotIntervalSeconds: snapshotIntervalSeconds,
        readTimeoutSeconds: readTimeoutSeconds,
        continueOnTimeout: continueOnTimeout,
        outputDirectory: outputDirectory)
}

guard let options = parseOptions() else {
    fputs(
        "Uso: droidhatch-frame-probe [--host HOST] [--port PORT] "
        + "[--frames N | --duration SECONDS] [--snapshot-interval SECONDS] "
        + "[--read-timeout SECONDS] [--continue-on-timeout] [--output DIR]\n",
        stderr)
    exit(2)
}

do {
    try FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)
    let connection = try FrameConnection(
        host: options.host,
        port: options.port,
        readTimeoutSeconds: options.readTimeoutSeconds)
    let timelineURL = options.outputDirectory.appendingPathComponent("timeline.csv")
    try Data("elapsedSeconds,event,sequence,stale\n".utf8).write(to: timelineURL)
    let timelineFile = try FileHandle(forWritingTo: timelineURL)
    defer {
        try? timelineFile.close()
    }

    var receivedFrames = 0
    var droppedFrames: UInt64 = 0
    var snapshotCount = 0
    var blackSnapshots = 0
    var staleSnapshots = 0
    var timeoutEvents = 0
    var nextSnapshotAt: UInt64?
    let startedAt = DispatchTime.now().uptimeNanoseconds
    var lastSequence: UInt64?
    var firstSequence: UInt64?
    var lastFrameHeader: FrameHeader?
    var lastFramePixels: Data?

    func appendTimeline(event: String, sequence: UInt64?, stale: Bool) throws {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000_000
        let sequenceText: String
        if let sequence {
            sequenceText = String(sequence)
        } else {
            sequenceText = ""
        }
        let staleText = stale ? "true" : "false"
        let line = String(format: "%.3f,%@,%@,%@\n", elapsed, event, sequenceText, staleText)
        try timelineFile.write(contentsOf: Data(line.utf8))
    }

    func saveDueSnapshots(now: UInt64, header: FrameHeader, pixels: Data, stale: Bool) throws {
        guard let intervalSeconds = options.snapshotIntervalSeconds else {
            return
        }

        let intervalNanoseconds = UInt64(intervalSeconds * 1_000_000_000)
        if nextSnapshotAt == nil {
            nextSnapshotAt = startedAt
        }

        while let scheduledSnapshotAt = nextSnapshotAt, now >= scheduledSnapshotAt {
            let staleSuffix = stale ? "-stale" : ""
            let filename = String(
                format: "snapshot-%04d-seq-%llu%@.png",
                snapshotCount,
                header.sequence,
                staleSuffix)
            try saveRgbaPng(
                header: header,
                pixels: pixels,
                to: options.outputDirectory.appendingPathComponent(filename))
            snapshotCount += 1
            if isBlack(pixels) {
                blackSnapshots += 1
            }
            if stale {
                staleSnapshots += 1
            }
            nextSnapshotAt = scheduledSnapshotAt + intervalNanoseconds
        }
    }

    while true {
        if let durationSeconds = options.durationSeconds {
            let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
            if Double(elapsedNanoseconds) / 1_000_000_000 >= durationSeconds {
                break
            }
        } else if let frameCount = options.frameCount, receivedFrames >= frameCount {
            break
        }

        do {
            switch try connection.readMessage() {
            case .hello:
                try appendTimeline(event: "hello", sequence: nil, stale: false)
                print("frame transport: hello")
            case let .status(_, message):
                try appendTimeline(event: "status", sequence: nil, stale: false)
                print("frame transport: status=\(message)")
            case let .error(_, message):
                throw NSError(domain: "DroidHatchFrameProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            case let .frame(header, pixels):
                receivedFrames += 1
                if let lastSequence, header.sequence <= lastSequence {
                    throw NSError(domain: "DroidHatchFrameProbe", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sequência de frame não crescente."])
                }
                if let lastSequence, header.sequence > lastSequence + 1 {
                    droppedFrames += header.sequence - lastSequence - 1
                }
                if firstSequence == nil {
                    firstSequence = header.sequence
                }
                lastSequence = header.sequence
                lastFrameHeader = header
                lastFramePixels = pixels
                try appendTimeline(event: "frame", sequence: header.sequence, stale: false)
                print("frame \(receivedFrames): seq=\(header.sequence) size=\(header.width)x\(header.height) bytes=\(pixels.count)")

                if receivedFrames == 1 {
                    try saveRgbaPng(header: header, pixels: pixels, to: options.outputDirectory.appendingPathComponent("first.png"))
                }

                try saveDueSnapshots(
                    now: DispatchTime.now().uptimeNanoseconds,
                    header: header,
                    pixels: pixels,
                    stale: false)

                if let frameCount = options.frameCount, receivedFrames == frameCount {
                    try saveRgbaPng(header: header, pixels: pixels, to: options.outputDirectory.appendingPathComponent("last.png"))
                }
            }
        } catch {
            guard options.continueOnTimeout else {
                throw error
            }
            guard case FrameTransportError.socketReadTimeout = error else {
                throw error
            }

            timeoutEvents += 1
            try appendTimeline(event: "timeout", sequence: lastSequence, stale: lastFrameHeader != nil)
            if let header = lastFrameHeader, let pixels = lastFramePixels {
                try saveDueSnapshots(
                    now: DispatchTime.now().uptimeNanoseconds,
                    header: header,
                    pixels: pixels,
                    stale: true)
            }
        }
    }

    let summary = ProbeSummary(
        receivedFrames: receivedFrames,
        droppedFrames: droppedFrames,
        blackSnapshots: blackSnapshots,
        snapshotCount: snapshotCount,
        staleSnapshots: staleSnapshots,
        timeoutEvents: timeoutEvents,
        firstSequence: firstSequence,
        lastSequence: lastSequence)
    var firstSequenceText = "none"
    if let firstSequence = summary.firstSequence {
        firstSequenceText = String(firstSequence)
    }
    var lastSequenceText = "none"
    if let lastSequence = summary.lastSequence {
        lastSequenceText = String(lastSequence)
    }
    print(
        "summary: frames=\(summary.receivedFrames) dropped=\(summary.droppedFrames) "
        + "snapshots=\(summary.snapshotCount) staleSnapshots=\(summary.staleSnapshots) "
        + "blackSnapshots=\(summary.blackSnapshots) timeouts=\(summary.timeoutEvents) "
        + "first=\(firstSequenceText) last=\(lastSequenceText)")
} catch {
    fputs("droidhatch-frame-probe: \(error)\n", stderr)
    exit(1)
}
