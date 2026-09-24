import Foundation

enum DroidHatchUserPaths {
    static var homeDirectory: URL {
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var root: URL {
        homeDirectory.appendingPathComponent(".droidhatch", isDirectory: true)
    }
}
