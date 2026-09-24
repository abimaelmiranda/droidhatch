import AppKit
import CoreGraphics
import DroidHatchFrameTransport

@MainActor
final class PreciseScrollInputController {
    private enum Metrics {
        static let normalizedMaximum: CGFloat = 1_000_000
        static let sensitivity: CGFloat = 1.25
        static let maximumDelta: CGFloat = 45_000
        static let rebaseInset: CGFloat = 120_000
        static let rebaseCoordinate: CGFloat = 500_000
        static let releaseDelay: DispatchTimeInterval = .milliseconds(400)
    }

    var sendTouch: ((InputTouchAction, UInt32, UInt32) -> Void)?

    private var isActive = false
    private var coordinates: (x: UInt32, y: UInt32)?
    private var releaseGeneration: UInt64 = 0

    func handle(
        event: NSEvent,
        frameSize: CGSize?,
        boundsSize: CGSize,
        pointInView: NSPoint) {
        let directionMultiplier: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        let deltaX = event.scrollingDeltaX * directionMultiplier
        let deltaY = event.scrollingDeltaY * directionMultiplier
        guard deltaX.isFinite, deltaY.isFinite else {
            return
        }

        if !isActive {
            guard event.phase.contains(.began),
                  let startCoordinates = normalizedCoordinates(
                      for: pointInView,
                      frameSize: frameSize,
                      boundsSize: boundsSize) else {
                return
            }
            isActive = true
            coordinates = startCoordinates
            sendTouch?(.down, startCoordinates.x, startCoordinates.y)
        }

        guard let currentCoordinates = coordinates,
              let frameSize else {
            finish()
            return
        }

        let contentRect = ViewerAspectFitLayout.rect(
            sourceSize: frameSize,
            boundsSize: boundsSize)
        guard contentRect.width > 0, contentRect.height > 0 else {
            finish()
            return
        }

        let normalizedDeltaX = limitedDelta(
            deltaX / contentRect.width * Metrics.normalizedMaximum * Metrics.sensitivity)
        let normalizedDeltaY = limitedDelta(
            deltaY / contentRect.height * Metrics.normalizedMaximum * Metrics.sensitivity)
        let proposedX = CGFloat(currentCoordinates.x) + normalizedDeltaX
        let proposedY = CGFloat(currentCoordinates.y) - normalizedDeltaY
        let shouldRebaseX = shouldRebase(
            current: CGFloat(currentCoordinates.x),
            proposed: proposedX,
            delta: normalizedDeltaX)
        let shouldRebaseY = shouldRebase(
            current: CGFloat(currentCoordinates.y),
            proposed: proposedY,
            delta: -normalizedDeltaY)

        var baseCoordinates = currentCoordinates
        if shouldRebaseX || shouldRebaseY {
            sendTouch?(.up, currentCoordinates.x, currentCoordinates.y)
            baseCoordinates = (
                x: shouldRebaseX
                    ? UInt32(Metrics.rebaseCoordinate)
                    : currentCoordinates.x,
                y: shouldRebaseY
                    ? UInt32(Metrics.rebaseCoordinate)
                    : currentCoordinates.y)
            coordinates = baseCoordinates
            sendTouch?(.down, baseCoordinates.x, baseCoordinates.y)
        }

        let nextCoordinates = (
            x: clamped(CGFloat(baseCoordinates.x) + normalizedDeltaX),
            y: clamped(CGFloat(baseCoordinates.y) - normalizedDeltaY))
        coordinates = nextCoordinates
        if deltaX != 0 || deltaY != 0 {
            sendTouch?(.move, nextCoordinates.x, nextCoordinates.y)
        }

        scheduleRelease()

        let phaseEnded = event.phase.contains(.ended)
            || event.phase.contains(.cancelled)
        let momentumEnded = event.momentumPhase.contains(.ended)
            || event.momentumPhase.contains(.cancelled)
        if momentumEnded || (phaseEnded && event.momentumPhase.isEmpty) {
            finish()
        }
    }

    func finish() {
        releaseGeneration &+= 1
        guard isActive else {
            return
        }
        isActive = false
        guard let lastCoordinates = coordinates else {
            return
        }
        coordinates = nil
        sendTouch?(.up, lastCoordinates.x, lastCoordinates.y)
    }

    private func scheduleRelease() {
        releaseGeneration &+= 1
        let generation = releaseGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.releaseDelay) { [weak self] in
            guard let self, self.releaseGeneration == generation else {
                return
            }
            self.finish()
        }
    }

    private func clamped(_ value: CGFloat) -> UInt32 {
        UInt32(max(0, min(Metrics.normalizedMaximum, value)))
    }

    private func limitedDelta(_ value: CGFloat) -> CGFloat {
        max(-Metrics.maximumDelta, min(Metrics.maximumDelta, value))
    }

    private func shouldRebase(
        current: CGFloat,
        proposed: CGFloat,
        delta: CGFloat) -> Bool {
        let approachingLowerBoundary = current <= Metrics.rebaseInset && delta < 0
        let approachingUpperBoundary = current >= Metrics.normalizedMaximum - Metrics.rebaseInset
            && delta > 0
        return proposed <= 0
            || proposed >= Metrics.normalizedMaximum
            || approachingLowerBoundary
            || approachingUpperBoundary
    }

    private func normalizedCoordinates(
        for pointInView: NSPoint,
        frameSize: CGSize?,
        boundsSize: CGSize) -> (x: UInt32, y: UInt32)? {
        guard let frameSize,
              frameSize.width > 0,
              frameSize.height > 0 else {
            return nil
        }

        let contentRect = ViewerAspectFitLayout.rect(
            sourceSize: frameSize,
            boundsSize: boundsSize)
        guard contentRect.contains(pointInView) else {
            return nil
        }

        let x = (pointInView.x - contentRect.minX) / contentRect.width
        let y = 1 - ((pointInView.y - contentRect.minY) / contentRect.height)
        return (clamped(x * Metrics.normalizedMaximum), clamped(y * Metrics.normalizedMaximum))
    }

}
