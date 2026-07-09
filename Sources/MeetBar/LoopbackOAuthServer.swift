import Foundation
import MeetBarCore
import Network

final class LoopbackOAuthServer: @unchecked Sendable {
    struct Callback {
        let code: String
        let state: String
    }

    private let queue = DispatchQueue(label: "digital.perceptiv.meetbar.oauth-loopback")
    private var listener: NWListener?
    private var callbackContinuation: CheckedContinuation<Callback, Error>?

    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.receive(connection)
        }

        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port else {
                        continuation.resume(throwing: MeetBarError.oauthCallbackFailed("No callback port was assigned."))
                        return
                    }
                    continuation.resume(returning: port)
                    listener.stateUpdateHandler = nil
                case .failed(let error):
                    continuation.resume(throwing: error)
                    listener.stateUpdateHandler = nil
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        return URL(string: "http://127.0.0.1:\(port.rawValue)/oauth/callback")!
    }

    func waitForCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                self?.callbackContinuation = continuation
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self else { return }
            defer {
                connection.cancel()
                self.stop()
            }

            if let error {
                self.callbackContinuation?.resume(throwing: error)
                self.callbackContinuation = nil
                return
            }

            guard
                let data,
                let request = String(data: data, encoding: .utf8),
                let requestLine = request.components(separatedBy: "\r\n").first,
                let target = requestLine.split(separator: " ").dropFirst().first,
                let components = URLComponents(string: "http://127.0.0.1\(target)")
            else {
                self.finishWithError(MeetBarError.oauthCallbackFailed("The browser callback was invalid."), connection: connection)
                return
            }

            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if let message = query["error"] {
                self.finishWithError(MeetBarError.oauthCallbackFailed(message), connection: connection)
                return
            }
            guard let code = query["code"], let state = query["state"] else {
                self.finishWithError(MeetBarError.missingAuthorizationCode, connection: connection)
                return
            }

            let html = """
            <!doctype html><html><head><meta charset="utf-8"><title>MeetBar connected</title></head>
            <body style="font: -apple-system-body; text-align:center; padding:64px">
            <h1>MeetBar is connected</h1><p>You can close this tab and return to MeetBar.</p>
            </body></html>
            """
            self.send(html: html, status: "200 OK", connection: connection)
            self.callbackContinuation?.resume(returning: Callback(code: code, state: state))
            self.callbackContinuation = nil
        }
    }

    private func finishWithError(_ error: Error, connection: NWConnection) {
        send(
            html: "<html><body><h1>MeetBar could not connect</h1><p>Return to the app and try again.</p></body></html>",
            status: "400 Bad Request",
            connection: connection
        )
        callbackContinuation?.resume(throwing: error)
        callbackContinuation = nil
    }

    private func send(html: String, status: String, connection: NWConnection) {
        let body = Data(html.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in })
    }
}
