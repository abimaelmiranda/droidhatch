import CoreGraphics

enum ViewerAspectFitLayout {
    static func rect(sourceSize: CGSize, boundsSize: CGSize) -> CGRect {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              boundsSize.width > 0,
              boundsSize.height > 0 else {
            return .zero
        }

        let sourceAspect = sourceSize.width / sourceSize.height
        let boundsAspect = boundsSize.width / boundsSize.height
        if sourceAspect > boundsAspect {
            let height = boundsSize.width / sourceAspect
            return CGRect(
                x: 0,
                y: (boundsSize.height - height) / 2,
                width: boundsSize.width,
                height: height)
        }

        let width = boundsSize.height * sourceAspect
        return CGRect(
            x: (boundsSize.width - width) / 2,
            y: 0,
            width: width,
            height: boundsSize.height)
    }
}
