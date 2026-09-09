import Foundation

/// Opt-in copy of an encrypted archive into the user's iCloud Drive.
///
/// Not a Zoon server. `FileManager` talks to Apple's ubiquity daemon; there
/// is no `URLSession` and no endpoint of ours. Off until the user taps
/// Back up now. The passphrase is never stored — same contract as the
/// share-sheet export in `MoreView`.
enum ICloudArchiveSync {


    static let filename = "ZoonBackup.json"
    static let documentsFolder = "Documents"

    enum Status: Equatable, Sendable {
        /// No iCloud account, or the ubiquity container is not entitled.
        case unavailable
        /// Container exists, no backup file yet.
        case empty
        case present(modified: Date, bytes: Int)
    }

    enum Failure: LocalizedError {
        case unavailable
        case empty

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "iCloud isn't available on this device. Sign in to iCloud in Settings, or use Export instead."
            case .empty:
                "There's no Zoon backup in iCloud yet."
            }
        }
    }

    /// Injectable so tests never touch the real ubiquity container.
    struct Container: Sendable {
        var root: @Sendable () -> URL?

        init(_ root: @escaping @Sendable () -> URL?) {
            self.root = root
        }

        static let live = Container {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }

        static func folder(_ url: URL) -> Container {
            Container { url }
        }
    }

    static func documentsURL(container: Container = .live) -> URL? {
        container.root()?.appendingPathComponent(documentsFolder, isDirectory: true)
    }

    static func fileURL(container: Container = .live) -> URL? {
        documentsURL(container: container)?.appendingPathComponent(filename)
    }

    static func status(
        container: Container = .live,
        fileManager: FileManager = .default
    ) -> Status {
        guard let url = fileURL(container: container) else { return .unavailable }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return .empty }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate ?? .distantPast
        let bytes = values?.fileSize ?? 0
        return .present(modified: modified, bytes: bytes)
    }

    static func write(
        _ data: Data,
        container: Container = .live,
        fileManager: FileManager = .default
    ) throws {
        guard let dir = documentsURL(container: container),
              let file = fileURL(container: container) else {
            throw Failure.unavailable
        }
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    static func read(
        container: Container = .live,
        fileManager: FileManager = .default
    ) throws -> Data {
        guard let file = fileURL(container: container) else { throw Failure.unavailable }
        guard fileManager.fileExists(atPath: file.path) else { throw Failure.empty }
        return try Data(contentsOf: file)
    }
}
