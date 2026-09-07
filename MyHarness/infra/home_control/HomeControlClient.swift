import Foundation

struct HomeControlReceipt: Decodable {
    let requestId: UUID
    let device: HomeAppliance
    let status: String
    let sentAt: String
}
struct HomeControlDevice: Decodable, Identifiable {
    let device: HomeAppliance
    let name: String
    let transport: String
    var id: String { device.rawValue }
}
enum HomeAppliance: String, Codable { case light, airConditioner }
enum HomeControlCommand: Encodable {
    case power(HomeAppliance, Bool)
    case climate(temperature: Int, mode: String, fan: String)
    enum CodingKeys: String, CodingKey { case action, device, power, temperature, mode, fan }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .power(let device, let on):
            try container.encode("power", forKey: .action)
            try container.encode(device, forKey: .device)
            try container.encode(on ? "on" : "off", forKey: .power)
        case .climate(let temperature, let mode, let fan):
            try container.encode("climate", forKey: .action)
            try container.encode(HomeAppliance.airConditioner, forKey: .device)
            try container.encode(temperature, forKey: .temperature)
            try container.encode(mode, forKey: .mode)
            try container.encode(fan, forKey: .fan)
        }
    }
}
struct HomeControlClient {
    let config: ActionInboxConfig
    private struct Envelope<T: Decodable>: Decodable { let data: T }
    private struct Failure: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
    func devices() async throws -> [HomeControlDevice] {
        struct Devices: Decodable { let devices: [HomeControlDevice] }
        let value: Devices = try await request(path: "api/home-control/devices", method: "GET", body: Data())
        return value.devices
    }
    func send(_ command: HomeControlCommand) async throws -> HomeControlReceipt {
        let receipt: HomeControlReceipt = try await request(path: "api/home-control/commands", method: "POST", body: JSONEncoder().encode(command))
        guard receipt.status == "signalSent" else { throw HomeControlError.message("送信結果を確認できません。家電の状態を確認してください。") }
        return receipt
    }
    private func request<T: Decodable>(path: String, method: String, body: Data) async throws -> T {
        let token = try await HomeControlSession.shared.accessToken(config: config)
        var request = URLRequest(url: config.apiBaseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw HomeControlError.message("通信結果を確認できません。家電の状態を確認してください。自動再送はしていません。") }
        guard let http = response as? HTTPURLResponse else { throw HomeControlError.message("サーバーの応答を確認できません。") }
        if http.statusCode == 401 { throw HomeControlError.message("MyHarnessで再ログインしてください。") }
        guard (200..<300).contains(http.statusCode) else {
            if let failure = try? JSONDecoder().decode(Failure.self, from: data) { throw HomeControlError.message(failure.error.message) }
            throw HomeControlError.message("操作できませんでした（HTTP \(http.statusCode)）。")
        }
        return try JSONDecoder().decode(Envelope<T>.self, from: data).data
    }
}
