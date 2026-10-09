import Foundation

nonisolated struct APIClient: Sendable {
    func data(
        _ request: APIRequest,
        baseURL: URL
    ) async throws -> Data {
        let urlRequest = try request.makeURLRequest(baseURL: baseURL)

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw IceometicsError.invalidResponse
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                throw IceometicsError.httpStatus(httpResponse.statusCode)
            }

            return data
        } catch let error as IceometicsError {
            throw error
        } catch {
            throw IceometicsError.network(error.localizedDescription)
        }
    }

    func send<T: Decodable & Sendable>(
        _ request: APIRequest,
        baseURL: URL,
        as type: T.Type
    ) async throws -> T {
        let data = try await data(request, baseURL: baseURL)

        do {
            return try IceometicsJSON.decoder.decode(type, from: data)
        } catch {
            throw IceometicsError.decoding(error.localizedDescription)
        }
    }
}
