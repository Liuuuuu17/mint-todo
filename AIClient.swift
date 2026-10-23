import Foundation
import Security

protocol SecretStore {
    func read() throws -> String?
    func save(_ value: String) throws
    func clear() throws
}
struct AIKeychain: SecretStore {
    var service = "com.codex.orbtodo.ai"
    var account = "api-key"
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    func read() throws -> String? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw PlanFailure("无法读取钥匙串中的 API Key（\(status)）。") }
        return String(data: data, encoding: .utf8)
    }
    func save(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PlanFailure("API Key 不能为空。") }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var request = query; request[kSecValueData as String] = Data(value.utf8)
            request[kSecAttrLabel as String] = "Mint Todo AI API Key"
            status = SecItemAdd(request as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw PlanFailure("API Key 未能保存到钥匙串（\(status)）。") }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PlanFailure("无法清除钥匙串密钥（\(status)）。") }
    }
}
struct AIConfiguration {
    var baseURL: String
    var model: String
    static func endpoint(_ base: String) throws -> URL {
        guard var components = URLComponents(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { throw PlanFailure("API Base URL 无效，请填写不含密钥或查询参数的服务地址。") }
        guard components.scheme == "https" || (components.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw PlanFailure("远程 API 地址必须使用 HTTPS；本机 localhost 可使用 HTTP。")
        }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") { path += path.isEmpty ? "/v1/chat/completions" : "/chat/completions" }
        components.path = path
        guard let url = components.url else { throw PlanFailure("API 地址无法转换为请求 URL。") }
        return url
    }
    static func modelsEndpoint(_ base: String) throws -> URL {
        let chat = try endpoint(base)
        var components = URLComponents(url: chat, resolvingAgainstBaseURL: false)!
        components.path = String(components.path.dropLast("/chat/completions".count)) + "/models"
        guard let url = components.url else { throw PlanFailure("模型列表地址无效。") }
        return url
    }
}
// Reject redirects so Authorization can never follow a provider redirect to another host.
final class NoAIRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct AIClient {
    let session: URLSession
    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 120
        self.session = session ?? URLSession(configuration: config, delegate: NoAIRedirects(), delegateQueue: nil)
    }
    func complete(config: AIConfiguration, key: String?, system: String, user: String) async throws -> String {
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PlanFailure("尚未配置 API Key，请到 AI 设置中保存密钥。") }
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PlanFailure("请填写模型名称。") }
        var request = URLRequest(url: try AIConfiguration.endpoint(config.baseURL))
        request.httpMethod = "POST"; request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": config.model, "stream": false,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]]])
        let data = try await responseData(for: request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]], let choice = choices.first,
              let message = choice["message"] as? [String: Any] else { throw PlanFailure("服务返回非标准响应，需要兼容 Chat Completions 的 choices/message 结构。") }
        if choice["finish_reason"] as? String == "length" { throw PlanFailure("输出被截断，计划未保存。请缩小范围或在服务端增加输出额度后重试。") }
        guard let text = message["content"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PlanFailure("模型返回空内容或不支持的内容格式，请重试。") }
        return text
    }
    func models(baseURL: String, key: String?) async throws -> [String] {
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlanFailure("请先填写 API Key，或使用当前地址已保存的密钥。")
        }
        var request = URLRequest(url: try AIConfiguration.modelsEndpoint(baseURL))
        request.httpMethod = "GET"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let data = try await responseData(for: request)
        struct ModelList: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let response = try? JSONDecoder().decode(ModelList.self, from: data) else {
            throw PlanFailure("模型列表格式不兼容，需要 data 数组和 id 字段；仍可手动填写模型名称。")
        }
        let models = Set(response.data.map(\.id).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).sorted()
        guard !models.isEmpty else { throw PlanFailure("服务返回的模型列表为空；仍可手动填写模型名称。") }
        return models
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw PlanFailure(error.code == .timedOut ? "请求超时。输入内容已保留，可以重试或缩小计划规模。" : "无法连接 API。请检查网络、Base URL 和服务状态。")
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw PlanFailure("服务未返回 HTTP 响应。") }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw PlanFailure("鉴权失败，请检查 API Key 和该模型的访问权限。")
        case 404: throw PlanFailure("接口或模型不存在，请检查请求地址；若服务不支持模型列表，可手动填写模型名称。")
        case 429: throw PlanFailure("服务限流或额度不足，请稍后重试。")
        default: throw PlanFailure("API 请求失败（HTTP \(http.statusCode)），请检查服务配置后重试。")
        }
        guard data.count <= 10_000_000 else { throw PlanFailure("API 响应超过 10 MB，请缩小请求范围。") }
        return data
    }

}
