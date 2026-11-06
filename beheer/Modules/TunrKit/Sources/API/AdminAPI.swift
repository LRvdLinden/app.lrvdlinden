import Foundation

/// Fout van de functie `admin` (veld `error` uit het antwoord) of van het netwerk.
struct APIError: Error, LocalizedError, Equatable {
    let code: String
    let status: Int

    var isUnauthorized: Bool { status == 401 || code == "unauthorized" }

    var errorDescription: String? {
        switch code {
        case "network": return L("Geen verbinding met de server.")
        case "not_configured": return L("De app is nog niet ingericht.")
        case "unauthorized": return L("Je sessie is verlopen. Log opnieuw in.")
        case "invalid_credentials", "bad_credentials": return L("Onjuiste gebruikersnaam of wachtwoord.")
        case "rate_limited", "too_many_attempts", "blocked":
            return L("Te veel pogingen. Probeer het over 15 minuten opnieuw.")
        case "build_not_found", "not_found": return L("Deze build staat niet (meer) op de server. Vernieuw de lijst.")
        case "builds_not_ready": return L("Downloads zijn nog niet ingericht.")
        case "decode": return L("Onverwacht antwoord van de server.")
        default:
            if status == 429 { return L("Te veel pogingen. Probeer het over 15 minuten opnieuw.") }
            return String(format: L("Er ging iets mis op de server (%@)."), code)
        }
    }
}

/// Praat met de Edge Function `admin`: `POST {SUPABASE_URL}/functions/v1/admin` met kopregel `apikey`,
/// JSON `{ "action": "...", ... }` en na inloggen `Authorization: Bearer <token>`.
struct AdminAPI {
    var session: URLSession = .shared

    func send<T: Decodable>(_ action: String, token: String?, params: [String: Any] = [:], as type: T.Type) async throws -> T {
        let data = try await raw(action, token: token, params: params)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError(code: "decode", status: 200)
        }
    }

    func raw(_ action: String, token: String?, params: [String: Any] = [:]) async throws -> Data {
        guard Config.isConfigured, let url = Config.adminFunction else {
            throw APIError(code: "not_configured", status: 0)
        }
        var payload: [String: Any] = params
        payload["action"] = action

        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Config.publishableKey, forHTTPHeaderField: "apikey")
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            if error is CancellationError { throw error }
            if let u = error as? URLError, u.code == .cancelled { throw CancellationError() }
            throw APIError(code: "network", status: 0)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            let code = body?.error ?? (status == 401 ? "unauthorized" : "server_error")
            throw APIError(code: code, status: status)
        }
        return data
    }

    private struct ErrorBody: Decodable {
        let error: String?
    }
}
