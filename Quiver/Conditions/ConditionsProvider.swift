import Foundation

protocol ConditionsProvider: Sendable {
    /// Single best-available snapshot "right now" for a spot.
    func currentConditions(spot: Spot) async throws -> ConditionsSnapshot

    /// Hourly forecast snapshots out to `hours` (capped at 168).
    func forecast(spot: Spot, hours: Int) async throws -> [ConditionsSnapshot]
}

enum ConditionsError: Error, LocalizedError {
    case badResponse(URLResponse?)
    case decoding(String)
    case missingField(String)
    case network(any Error)

    var errorDescription: String? {
        switch self {
        case .badResponse(let r): "Bad HTTP response: \(String(describing: r))"
        case .decoding(let m): "Decoding failed: \(m)"
        case .missingField(let f): "Missing field: \(f)"
        case .network(let e): "Network: \(e.localizedDescription)"
        }
    }
}

/// Light wrapper around URLSession for typed JSON GETs.
struct JSONFetcher: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func get<T: Decodable>(_ url: URL, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ConditionsError.badResponse(response)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let preview = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw ConditionsError.decoding("\(error)  body=\(preview)")
        }
    }

    func getText(_ url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ConditionsError.badResponse(response)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Gemini (LLM recommender) networking
//
// Lives here alongside `JSONFetcher` so adding the Gemini integration needs no new `.swift` file
// (xcodegen isn't installed; a brand-new file wouldn't be in the generated project). `GeminiClient`
// mirrors `JSONFetcher`'s typed-GET + body-preview-on-failure style, but POSTs a structured-output
// request and returns the model's JSON text payload.

/// Gemini configuration. The key is resolved, in priority order, from (1) the user's own key entered
/// in Settings and stored in the Keychain, (2) a `GEMINI_API_KEY` Info.plist entry injected at build
/// time (Config.xcconfig → optional Secrets.xcconfig), else (3) empty. When empty, the whole Gemini
/// path is skipped and the app falls back to the rule engine — so tests and offline runs behave
/// deterministically with no key configured.
enum GeminiConfig {
    /// Never commit a real key here — it ships inside the binary and is extractable. Empty keeps the
    /// public repo, tests, and offline runs deterministic on the rule engine.
    private static let devKey = ""

    static var apiKey: String {
        // 1. The user's own key, entered in-app (Keychain).
        if let k = KeychainStore.geminiKey?.trimmingCharacters(in: .whitespaces), !k.isEmpty {
            return k
        }
        // 2. Build-time key injected via Info.plist.
        if let k = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
           !k.trimmingCharacters(in: .whitespaces).isEmpty {
            return k
        }
        // 3. Nothing configured.
        return devKey
    }

    /// Flash = fast/cheap; good enough for this. Revisit `pro` if quality lags.
    static let model = "gemini-2.5-flash"

    static var isConfigured: Bool { !apiKey.isEmpty }
}

enum GeminiError: Error, LocalizedError {
    case notConfigured
    case badResponse(URLResponse?)
    case noContent
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Gemini API key is not configured."
        case .badResponse(let r): "Bad Gemini response: \(String(describing: r))"
        case .noContent: "Gemini returned no content."
        case .decoding(let m): "Gemini decode failed: \(m)"
        }
    }
}

/// Thin POST wrapper around the Gemini `generateContent` REST endpoint. Returns the raw JSON text
/// the model produced (the structured-output payload), which callers decode into their own contract.
struct GeminiClient: Sendable {
    let session: URLSession
    let apiKey: String
    let model: String
    let timeout: TimeInterval

    init(
        session: URLSession = .shared,
        apiKey: String = GeminiConfig.apiKey,
        model: String = GeminiConfig.model,
        timeout: TimeInterval = 10
    ) {
        self.session = session
        self.apiKey = apiKey
        self.model = model
        self.timeout = timeout
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    /// POST a structured-output request and return the model's JSON text as `Data`.
    /// `responseSchema` is an OpenAPI-subset schema dict (built with `JSONSerialization`-friendly types).
    func generateJSON(
        systemInstruction: String,
        userPrompt: String,
        responseSchema: [String: Any]
    ) async throws -> Data {
        guard isConfigured else { throw GeminiError.notConfigured }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemInstruction]]],
            "contents": [["role": "user", "parts": [["text": userPrompt]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": responseSchema,
                "temperature": 0.4,
                // gemini-2.5-flash runs an internal "thinking" pass by default that adds seconds of
                // latency. This is a constrained sizing/selection task with a strict schema, so we
                // disable thinking for a much faster response. Bump the budget back up if quality lags.
                "thinkingConfig": ["thinkingBudget": 0]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GeminiError.badResponse(response)
        }

        // Envelope: { candidates: [ { content: { parts: [ { text: "<json>" } ] } } ] }
        do {
            let envelope = try JSONDecoder().decode(GeminiEnvelope.self, from: data)
            guard let text = envelope.candidates?.first?.content?.parts?.first?.text,
                  let textData = text.data(using: .utf8) else {
                throw GeminiError.noContent
            }
            return textData
        } catch let e as GeminiError {
            throw e
        } catch {
            let preview = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw GeminiError.decoding("\(error)  body=\(preview)")
        }
    }

    // Minimal decodable view of the Gemini response envelope.
    private struct GeminiEnvelope: Decodable {
        let candidates: [Candidate]?
        struct Candidate: Decodable { let content: Content? }
        struct Content: Decodable { let parts: [Part]? }
        struct Part: Decodable { let text: String? }
    }
}
