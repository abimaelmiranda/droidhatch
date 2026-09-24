import Foundation
import SQLite3

final class AppCatalogStore {
    private let databaseURL: URL

    init(fileManager: FileManager = .default) {
        let root = DroidHatchUserPaths.root
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        databaseURL = root.appendingPathComponent("apps.db")
    }

    func loadApps() throws -> [InstalledApp] {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        try ensureSchema(database: database)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            AppCatalogSchema.selectApps,
            -1,
            &statement,
            nil) == SQLITE_OK,
              let statement else {
            throw databaseError(database)
        }
        defer { sqlite3_finalize(statement) }

        var apps: [InstalledApp] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let iconBytes: Data?
            if let blob = sqlite3_column_blob(statement, AppCatalogSchema.Column.iconBlob.rawValue) {
                iconBytes = Data(
                    bytes: blob,
                    count: Int(sqlite3_column_bytes(statement, AppCatalogSchema.Column.iconBlob.rawValue)))
            } else {
                iconBytes = nil
            }

            apps.append(InstalledApp(
                alias: text(statement, column: AppCatalogSchema.Column.alias.rawValue),
                packageName: text(statement, column: AppCatalogSchema.Column.packageName.rawValue),
                containerName: text(statement, column: AppCatalogSchema.Column.containerName.rawValue),
                installedAt: text(statement, column: AppCatalogSchema.Column.installedAt.rawValue),
                iconData: iconBytes,
                iconMime: optionalText(statement, column: AppCatalogSchema.Column.iconMime.rawValue)))
        }
        return apps
    }

    func findByPackageName(_ packageName: String) throws -> InstalledApp? {
        try loadApps().first { $0.packageName == packageName }
    }

    func save(
        alias: String,
        packageName: String,
        containerName: String,
        iconData: Data? = nil,
        iconMime: String? = nil,
        installedAt: String = ISO8601DateFormatter().string(from: Date())) throws {
        let database = try openDatabase()
        defer { sqlite3_close(database) }
        try ensureSchema(database: database)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            AppCatalogSchema.upsertApp,
            -1,
            &statement,
            nil) == SQLITE_OK,
              let statement else {
            throw databaseError(database)
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in [alias, packageName, containerName, installedAt].enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else {
                throw databaseError(database)
            }
        }
        try bindBlob(
            iconData,
            to: statement,
            index: AppCatalogSchema.Column.iconBlob.rawValue + 1,
            database: database)
        if let iconMime {
            guard sqlite3_bind_text(
                statement,
                AppCatalogSchema.Column.iconMime.rawValue + 1,
                iconMime,
                -1,
                transient) == SQLITE_OK else {
                throw databaseError(database)
            }
        } else {
            guard sqlite3_bind_null(
                statement,
                AppCatalogSchema.Column.iconMime.rawValue + 1) == SQLITE_OK else {
                throw databaseError(database)
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError(database)
        }
    }

    func remove(alias: String) throws {
        let database = try openDatabase()
        defer { sqlite3_close(database) }
        try ensureSchema(database: database)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM apps WHERE alias = ?;", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError(database)
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, alias, -1, transient) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError(database)
        }
    }

    private func ensureSchema(database: OpaquePointer) throws {
        try execute(AppCatalogSchema.createTable, database: database)
        try addColumnIfNeeded("icon_blob BLOB", database: database)
        try addColumnIfNeeded("icon_mime TEXT", database: database)
        try addColumnIfNeeded("icon_hash TEXT", database: database)
    }

    private func openDatabase() throws -> OpaquePointer {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil) == SQLITE_OK,
            let database else {
            throw NSError(
                domain: "DroidHatchGUI.Database",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Não foi possível abrir (databaseURL.path)"])
        }
        return database
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message: String
            if let error {
                message = String(cString: error)
            } else {
                message = databaseError(database).localizedDescription
            }
            sqlite3_free(error)
            throw NSError(
                domain: "DroidHatchGUI.Database",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func addColumnIfNeeded(_ definition: String, database: OpaquePointer) throws {
        guard let columnName = definition
            .split(separator: " ", maxSplits: 1)
            .first
            .map(String.init) else {
            throw databaseError(database)
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            AppCatalogSchema.tableInfo,
            -1,
            &statement,
            nil) == SQLITE_OK,
              let statement else {
            throw databaseError(database)
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let value = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: value).caseInsensitiveCompare(columnName) == .orderedSame {
                return
            }
        }

        try execute("ALTER TABLE apps ADD COLUMN \(definition);", database: database)
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func optionalText(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private func bindBlob(
        _ data: Data?,
        to statement: OpaquePointer,
        index: Int32,
        database: OpaquePointer) throws {
        guard let data, !data.isEmpty else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw databaseError(database)
            }
            return
        }

        let result = data.withUnsafeBytes { bytes in
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            return sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), transient)
        }
        guard result == SQLITE_OK else {
            throw databaseError(database)
        }
    }

    private func databaseError(_ database: OpaquePointer) -> NSError {
        NSError(
            domain: "DroidHatchGUI.Database",
            code: Int(sqlite3_errcode(database)),
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
}
