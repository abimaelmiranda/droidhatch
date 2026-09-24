import CoreGraphics
import Foundation
import ImageIO

public func saveRgbaPng(
    header: FrameHeader,
    pixels: Data,
    to url: URL) throws {
    guard header.pixelFormat == FrameProtocolConstants.rgba8888PixelFormat,
          header.width > 0,
          header.height > 0,
          pixels.count == Int(header.width) * Int(header.height) * 4 else {
        throw FrameTransportError.pngEncodingFailed
    }

    guard let provider = CGDataProvider(data: pixels as CFData),
          let image = CGImage(
              width: Int(header.width),
              height: Int(header.height),
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: Int(header.width) * 4,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent),
          let destination = CGImageDestinationCreateWithURL(
              url as CFURL,
              "public.png" as CFString,
              1,
              nil) else {
        throw FrameTransportError.pngEncodingFailed
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw FrameTransportError.pngEncodingFailed
    }
}
