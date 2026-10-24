import Foundation

@MainActor
struct ExperimentAPIClient {
    let transport: ActionInboxAPIClient

    func get<Value: Decodable>(_ path: String, query: [URLQueryItem], as type: Value.Type) async throws -> Value {
        let data = try await transport.fetchExperimentData(path: path, queryItems: query)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in try ActionInboxDateDecoder.decode(decoder) }
        return try decoder.decode(ExperimentEnvelope<Value>.self, from: data).data
    }

    func page<Value: Decodable>(_ path: String, offset: Int, query: [URLQueryItem], as type: Value.Type) async throws -> ExperimentPage<Value> {
        try await get(path, query: query + [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "offset", value: String(offset))], as: ExperimentPage<Value>.self)
    }
}
