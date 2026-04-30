import Foundation

enum PhotoStorage {
    static var photosDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appending(path: "photos", directoryHint: .isDirectory)
    }

    /// JPEG データを `Documents/photos/<uuid>.jpg` に保存し、保存先 URL を返す。
    static func save(jpegData: Data) throws -> URL {
        let directory = photosDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "\(UUID().uuidString).jpg", directoryHint: .notDirectory)
        try jpegData.write(to: fileURL, options: [.atomic])
        return fileURL
    }
}
