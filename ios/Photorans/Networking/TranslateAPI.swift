import Foundation

struct TranslateResponse: Decodable, Sendable {
    let originalText: String
    let translatedText: String
    let model: String
}

enum TranslateError: LocalizedError {
    case missingBaseURL
    case invalidBaseURL(String)
    case requestFailed(underlying: Error)
    case timeout
    case server(status: Int, message: String?)
    case decoding

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "API_BASE_URL が設定されていません。"
        case .invalidBaseURL(let raw):
            return "API_BASE_URL の形式が不正です: \(raw)"
        case .requestFailed:
            return "ネットワークエラーが発生しました。接続を確認してください。"
        case .timeout:
            return "サーバへの接続がタイムアウトしました。"
        case .server(let status, let message):
            if let message, !message.isEmpty {
                return "サーバエラー (\(status)): \(message)"
            }
            return "サーバエラー (\(status))"
        case .decoding:
            return "サーバ応答の解析に失敗しました。"
        }
    }
}

actor TranslateAPI {
    static let shared = TranslateAPI()

    private let session: URLSession

    init(timeout: TimeInterval = 60) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    func translate(jpegData: Data) async throws -> TranslateResponse {
        let url = try Self.translateURL()
        let boundary = "PhotoransBoundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.makeMultipartBody(jpegData: jpegData, boundary: boundary)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw TranslateError.timeout
        } catch {
            throw TranslateError.requestFailed(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslateError.server(status: -1, message: nil)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw TranslateError.server(status: http.statusCode, message: Self.extractErrorMessage(from: data))
        }

        do {
            return try JSONDecoder().decode(TranslateResponse.self, from: data)
        } catch {
            throw TranslateError.decoding
        }
    }

    private static func translateURL() throws -> URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              !raw.isEmpty else {
            throw TranslateError.missingBaseURL
        }
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        guard let url = URL(string: "\(trimmed)/translate") else {
            throw TranslateError.invalidBaseURL(raw)
        }
        return url
    }

    private static func makeMultipartBody(jpegData: Data, boundary: String) -> Data {
        var body = Data()
        let header =
            "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n" +
            "Content-Type: image/jpeg\r\n\r\n"
        body.append(Data(header.utf8))
        body.append(jpegData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["error"] as? String else {
            return nil
        }
        return message
    }
}
