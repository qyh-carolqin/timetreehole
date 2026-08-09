import Foundation

// MARK: - 网络请求引擎 · URLSession 封装

/// 全局共享单例，负责所有 HTTP 请求的发送、设备认证注入、错误处理与重试
@MainActor
final class NetworkManager: @unchecked Sendable {

    static let shared = NetworkManager()

    // MARK: - 配置

    /// 后端 API 基础地址（唯一真源: APIConfig，勿在此重复硬编码）
    let baseURL = APIConfig.baseURL

    /// 设备唯一标识（匿名用户认证）
    private let deviceIdKey = "com.timetreehole.deviceId"

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 4
        session  = URLSession(configuration: config)
        decoder  = JSONDecoder()
        encoder  = JSONEncoder()
        decoder.keyDecodingStrategy  = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        encoder.keyEncodingStrategy  = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - 设备 ID 管理

    /// 获取或生成设备 ID（首次启动时创建并持久化）
    var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIdKey), !existing.isEmpty {
            return existing
        }
        let newId = "ios-" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        return newId
    }

    /// 设备平台标识
    var platform: String { "ios" }

    /// 设备型号（如 iPhone16,1）
    var model: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    // MARK: - 请求构造

    /// 构造带认证头的请求
    private func buildRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json",
        extraHeaders: [String: String] = [:]
    ) -> URLRequest {
        let url = URL(string: baseURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue(deviceId,  forHTTPHeaderField: "X-Device-Id")
        req.setValue(platform,  forHTTPHeaderField: "X-Platform")
        req.setValue(model,     forHTTPHeaderField: "X-Model")
        for (key, value) in extraHeaders {
            req.setValue(value, forHTTPHeaderField: key)
        }
        req.httpBody = body
        return req
    }

    // MARK: - 通用请求方法

    /// 发送 JSON 请求并解码响应
    func request<T: Decodable>(_ path: String, method: String = "GET", body: Encodable? = nil) async throws -> T {
        var requestBody: Data?
        if let body = body {
            requestBody = try encoder.encode(body)
        }
        let req = buildRequest(path: path, method: method, body: requestBody)
        return try await execute(req)
    }

    /// 发送请求，返回原始 Data（用于音频流等二进制响应）
    func requestData(_ path: String, method: String = "GET") async throws -> Data {
        let req = buildRequest(path: path, method: method)
        return try await executeData(req)
    }

    /// 发送无响应体的请求（如 DELETE）
    func requestVoid(_ path: String, method: String) async throws {
        let req = buildRequest(path: path, method: method)
        _ = try await executeVoid(req)
    }

    // MARK: - Multipart 文件上传

    /// 上传音频文件 + 表单字段
    func upload(
        path: String,
        fileData: Data,
        fileName: String,
        mimeType: String = "audio/mp4",
        fields: [String: String] = [:]
    ) async throws -> UploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        // 表单字段
        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // 文件字段
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let req = buildRequest(
            path: path,
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )

        return try await execute(req)
    }

    // MARK: - 底层执行

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func executeData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func executeVoid(_ request: URLRequest) async throws -> HTTPURLResponse {
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return response as! HTTPURLResponse
    }

    // MARK: - 响应校验

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError("无效的服务器响应")
        }

        switch http.statusCode {
        case 200...299: return
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        case 413: throw APIError.fileTooLarge
        case 429: throw APIError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        case 500...599:
            if let errorBody = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                throw APIError.serverError(errorBody.message ?? "服务器内部错误")
            }
            throw APIError.serverError("服务器内部错误")
        default:
            let body = String(data: data, encoding: .utf8)
            throw APIError.httpError(http.statusCode, body)
        }
    }
}

// MARK: - 错误类型

enum APIError: LocalizedError, Equatable {
    case networkError(String)
    case decodingError(String)
    case unauthorized
    case notFound
    case fileTooLarge
    case rateLimited(retryAfter: String?)
    case serverError(String)
    case httpError(Int, String?)
    case unknown

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "网络错误: \(msg)"
        case .decodingError(let msg): return "数据解析错误: \(msg)"
        case .unauthorized:           return "未授权，请重新打开应用"
        case .notFound:              return "内容不存在或已被删除"
        case .fileTooLarge:          return "音频文件过大（不超过 20MB）"
        case .rateLimited:           return "请求过于频繁，请稍后再试"
        case .serverError(let msg):  return msg
        case .httpError(let code, _):   return "服务器响应异常 (\(code))"
        case .unknown:               return "未知错误"
        }
    }

    /// 是否值得重试
    var isRetryable: Bool {
        switch self {
        case .networkError, .serverError, .rateLimited: return true
        default: return false
        }
    }
}

struct ErrorBody: Decodable {
    let error: String?
    let message: String?
}

// MARK: - 通用 API 响应类型

/// 列表响应 (Paginated / Non-paginated)
struct APIListResponse<T: Decodable>: Decodable {
    let seeds: [T]?
    let notifications: [T]?
    let total: Int?
    let unread: Int?
}

/// 单对象响应
struct APIItemResponse<T: Decodable>: Decodable {
    let seed: T?
}

/// 上传响应
struct UploadResponse: Decodable {
    let uuid: String?
    let success: Bool?
    let message: String?
    let quota: QuotaUsageInfo?
}

struct QuotaUsageInfo: Decodable {
    let creditsUsed: Int?
    let remainingFree: Int?
}

/// 简单成功响应
struct APISuccessResponse: Decodable {
    let success: Bool
    let message: String?
}

/// 统计响应
struct APIStatsResponse: Decodable {
    let totalPublic: Int?
    let totalSeeds: Int?
}

/// 未读计数响应
struct APIUnreadResponse: Decodable {
    let count: Int
}
