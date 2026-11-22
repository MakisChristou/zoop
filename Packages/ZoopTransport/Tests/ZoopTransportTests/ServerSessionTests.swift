import Foundation
import XCTest
@testable import ZoopTransport

final class ServerSessionTests: XCTestCase {
    func testSessionDoesNotPersistCredentialsOrCache() {
        let session = ServerSession.make()
        defer { session.invalidateAndCancel() }
        XCTAssertNil(session.configuration.urlCache)
        XCTAssertNil(session.configuration.httpCookieStorage)
        XCTAssertFalse(session.configuration.httpShouldSetCookies)
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 20)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 60)
    }

    // Real HTTP redirects exercise Foundation itself, not just the delegate method.
    // An isolated loopback server records whether any body reaches the destination.
    func testRedirectsNeverForwardBodies() async throws {
        #if os(macOS)
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", """
        from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_POST(self):
                self.rfile.read(int(self.headers.get('Content-Length', 0)))
                code = int(self.path.strip('/'))
                self.send_response(code)
                self.send_header('Location', 'http://localhost:%d/destination' % self.server.server_port)
                self.end_headers()
            def do_GET(self):
                self.send_response(200); self.end_headers()
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        print(server.server_port, flush=True)
        server.serve_forever()
        """]
        process.standardOutput = output
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let line = output.fileHandleForReading.availableData
        let port = try XCTUnwrap(Int(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        let session = ServerSession.make()
        defer { session.invalidateAndCancel() }
        for code in [301, 302, 303, 307, 308] {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(code)")!)
            request.httpMethod = "POST"
            request.httpBody = Data("synthetic-only".utf8)
            request.setValue("Bearer synthetic-only", forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, code)
            XCTAssertEqual(response.url, request.url)
        }
        #endif
    }
}
