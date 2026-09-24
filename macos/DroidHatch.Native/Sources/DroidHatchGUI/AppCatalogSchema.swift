import Foundation

enum AppCatalogSchema {
    enum Column: Int32 {
        case alias = 0
        case packageName = 1
        case containerName = 2
        case installedAt = 3
        case iconBlob = 4
        case iconMime = 5
    }

    static let selectApps = """
        SELECT alias, package_name, container_name, installed_at,
               icon_blob, icon_mime
        FROM apps
        ORDER BY alias COLLATE NOCASE;
        """

    static let upsertApp = """
        INSERT INTO apps (alias, package_name, container_name, installed_at, icon_blob, icon_mime)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(alias) DO UPDATE SET
            package_name = excluded.package_name,
            container_name = excluded.container_name,
            installed_at = excluded.installed_at,
            icon_blob = COALESCE(excluded.icon_blob, apps.icon_blob),
            icon_mime = COALESCE(excluded.icon_mime, apps.icon_mime);
        """

    static let createTable = """
        CREATE TABLE IF NOT EXISTS apps (
            alias TEXT NOT NULL COLLATE NOCASE PRIMARY KEY,
            package_name TEXT NOT NULL UNIQUE,
            container_name TEXT NOT NULL,
            installed_at TEXT NOT NULL,
            icon_blob BLOB,
            icon_mime TEXT,
            icon_hash TEXT
        );
        """

    static let tableInfo = "PRAGMA table_info(apps);"

}
