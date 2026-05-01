import Foundation

struct SavedPhoto {
    /// Documents 配下の相対パス (例: `photos/<uuid>.jpg`)。SwiftData に永続化する用。
    let relativePath: String
}

enum PhotoStorage {
    static let photosSubdirectory = "photos"

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var photosDirectory: URL {
        documentsDirectory.appending(path: photosSubdirectory, directoryHint: .isDirectory)
    }

    /// JPEG データを `Documents/photos/<uuid>.jpg` に保存し、相対パスを返す。
    static func save(jpegData: Data) throws -> SavedPhoto {
        let directory = photosDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = directory.appending(path: filename, directoryHint: .notDirectory)
        try jpegData.write(to: fileURL, options: [.atomic])
        return SavedPhoto(relativePath: "\(photosSubdirectory)/\(filename)")
    }

    /// 永続化された相対パスから現在の Documents 配下の絶対 URL を解決する。
    static func absoluteURL(for relativePath: String) -> URL {
        documentsDirectory.appending(path: relativePath, directoryHint: .notDirectory)
    }
}
