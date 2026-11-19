import Foundation

enum ServerSignIn {
    struct Account: Decodable { let id: Int64; let email: String }
    struct Identity: Decodable { let account: Account; let devices: [String] }
    struct Login: Decodable { let token: String; let account: Account; let devices: [String] }
    enum Failure: LocalizedError {
        case address, rejected, unavailable, changed
        var errorDescription: String? {
            switch self {
            case .address: "Use an HTTPS server address."
            case .rejected: "Email or password wasn’t accepted."
            case .unavailable: "Couldn’t sign in. Check your server and try again."
            case .changed: "Server connection changed. Try again."
            }
        }
    }
    static func address(_ value: String) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              url.scheme == "https" || (url.scheme == "http" && ["127.0.0.1", "localhost", "[::1]"].contains(host))
        else { throw Failure.address }
        return url
    }
    private static func send(_ base: URL, path: String, method: String, token: String? = nil, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpShouldHandleCookies = false
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.unavailable }
        if response.statusCode == 401 { throw Failure.rejected }
        guard (200..<300).contains(response.statusCode) else { throw Failure.unavailable }
        return data
    }
    @MainActor static func signIn(server: String, email: String, password: String) async throws {
        let base = try address(server)
        let normalized = base.absoluteString.hasSuffix("/") ? String(base.absoluteString.dropLast()) : base.absoluteString
        let old = Settings.credential
        let body = try JSONEncoder().encode(["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password])
        let response = try await send(base, path: "v1/auth/native/login", method: "POST", body: body)
        let login = try JSONDecoder().decode(Login.self, from: response)
        let new = ServerCredential(server: normalized, token: login.token, accountID: login.account.id, email: login.account.email, devices: login.devices)
        guard Settings.credential == old else { throw Failure.changed }
        // Authenticate the old token before preserving its Health journal. Never transfer another account's consent.
        if let old, old.server.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == normalized,
           let data = try? await send(base, path: "v1/auth/me", method: "GET", token: old.token),
           let identity = try? JSONDecoder().decode(Identity.self, from: data), identity.account.id == login.account.id {
            Settings.preserveHealthScopes(from: old, to: new, devices: login.devices)
        }
        guard !Task.isCancelled, Settings.credential == old else { throw Failure.changed }
        do { try Settings.save(new) }
        catch {
            _ = try? await send(base, path: "v1/auth/native/logout", method: "POST", token: new.token)
            throw error
        }
        if let old, old.server.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == normalized {
            _ = try? await send(base, path: "v1/auth/native/logout", method: "POST", token: old.token)
        }
    }
    @MainActor static func signOut() async throws {
        guard let old = Settings.credential, let base = URL(string: old.server) else { return }
        // Establish a non-secret alias before retiring an old token installation.
        // Signing back into the same account must not restart Health imports/exports.
        if old.accountID == nil,
           let data = try? await send(base, path: "v1/auth/me", method: "GET", token: old.token),
           let identity = try? JSONDecoder().decode(Identity.self, from: data) {
            let mapped = ServerCredential(server: old.server.trimmingCharacters(in: CharacterSet(charactersIn: "/")), token: old.token, accountID: identity.account.id)
            Settings.preserveHealthScopes(from: old, to: mapped, devices: identity.devices)
        }
        // Require a server receipt before claiming the phone token was revoked.
        do { _ = try await send(base, path: "v1/auth/native/logout", method: "POST", token: old.token) }
        catch Failure.rejected { /* Already revoked by the operator. */ }
        guard Settings.credential == old else { throw Failure.changed }
        try Settings.clear()
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
