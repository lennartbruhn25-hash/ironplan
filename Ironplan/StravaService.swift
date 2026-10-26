import Foundation
import AuthenticationServices
import UIKit

/// Strava-Anbindung über die offizielle API.
/// Dafür legst du einmal eine eigene „API-Anwendung“ auf strava.com/settings/api an
/// (Callback-Domain: localhost) und trägst Client-ID und Client-Secret in der App ein.
@MainActor
final class StravaService: NSObject, ASWebAuthenticationPresentationContextProviding {
    struct Token: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: TimeInterval
        var athleteName: String?
    }

    enum StravaError: LocalizedError {
        case missingCredentials, cancelled, badResponse(String)
        var errorDescription: String? {
            switch self {
            case .missingCredentials: return "Bitte zuerst Client-ID und Client-Secret in den Einstellungen eintragen."
            case .cancelled: return "Anmeldung abgebrochen."
            case .badResponse(let msg): return "Strava: \(msg)"
            }
        }
    }

    private static let redirectURI = "ironplan://localhost"
    private var session: ASWebAuthenticationSession?

    private(set) var token: Token? = Storage.load(Token.self, key: Storage.stravaTokenKey)
    var isConnected: Bool { token != nil }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    func connect(clientID: String, clientSecret: String) async throws {
        let id = clientID.trimmingCharacters(in: .whitespaces)
        let secret = clientSecret.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !secret.isEmpty else { throw StravaError.missingCredentials }

        var comps = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "read,activity:read_all"),
        ]
        guard let authURL = comps.url else { throw StravaError.badResponse("Ungültige Adresse") }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let s = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "ironplan") { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? StravaError.cancelled)
                }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            s.start()
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            throw StravaError.badResponse(err)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw StravaError.badResponse("Kein Code erhalten")
        }

        token = try await requestToken(params: [
            "client_id": id, "client_secret": secret, "code": code, "grant_type": "authorization_code",
        ])
        Storage.save(token, key: Storage.stravaTokenKey)
    }

    func disconnect() {
        token = nil
        Storage.remove(key: Storage.stravaTokenKey)
    }

    func activities(since start: Date, clientID: String, clientSecret: String) async throws -> [ActivityRecord] {
        guard var current = token else { return [] }
        if current.expiresAt < Date().timeIntervalSince1970 + 120 {
            var refreshed = try await requestToken(params: [
                "client_id": clientID, "client_secret": clientSecret,
                "refresh_token": current.refreshToken, "grant_type": "refresh_token",
            ])
            refreshed.athleteName = refreshed.athleteName ?? current.athleteName
            current = refreshed
            token = refreshed
            Storage.save(refreshed, key: Storage.stravaTokenKey)
        }

        var comps = URLComponents(string: "https://www.strava.com/api/v3/athlete/activities")!
        comps.queryItems = [
            URLQueryItem(name: "after", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "per_page", value: "100"),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)

        let list = try JSONDecoder().decode([StravaActivity].self, from: data)
        let iso = ISO8601DateFormatter()
        return list.compactMap { a in
            guard let date = iso.date(from: a.start_date) else { return nil }
            return ActivityRecord(
                id: "strava-\(a.id)",
                source: .strava,
                appName: a.device_name ?? "Strava",
                sport: Self.sport(for: a.sport_type ?? a.type ?? ""),
                name: a.name,
                start: date,
                minutes: Int((Double(a.moving_time) / 60).rounded()),
                distanceKm: a.distance > 0 ? a.distance / 1000 : nil,
                avgHeartRate: a.average_heartrate.map { Int($0.rounded()) })
        }
    }

    // MARK: Intern

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_at: TimeInterval
        let athlete: Athlete?
        struct Athlete: Decodable { let firstname: String? }
    }

    private struct StravaActivity: Decodable {
        let id: Int
        let name: String
        let type: String?
        let sport_type: String?
        let start_date: String
        let moving_time: Int
        let distance: Double
        let average_heartrate: Double?
        let device_name: String?
    }

    private func requestToken(params: [String: String]) async throws -> Token {
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        return Token(accessToken: t.access_token, refreshToken: t.refresh_token,
                     expiresAt: t.expires_at, athleteName: t.athlete?.firstname)
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw StravaError.badResponse("Keine Antwort") }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw StravaError.badResponse("Fehler \(http.statusCode) \(text.prefix(120))")
        }
    }

    static func sport(for type: String) -> Sport {
        switch type {
        case "Swim": return .swim
        case "Ride", "VirtualRide", "GravelRide", "MountainBikeRide", "EBikeRide", "Velomobile": return .bike
        case "Run", "VirtualRun", "TrailRun": return .run
        case "WeightTraining", "Crossfit", "Workout", "Pilates": return .strength
        default: return .other
        }
    }
}
