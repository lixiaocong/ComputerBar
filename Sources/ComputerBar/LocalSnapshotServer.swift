import Foundation
import Network
#if canImport(ComputerBarShared)
import ComputerBarShared
#endif

final class LocalSnapshotServer: @unchecked Sendable {
    static let shared = LocalSnapshotServer()

    private let queue = DispatchQueue(label: "com.computerbar.local-snapshot-server")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private var listener: NWListener?
    private var currentPayload: Data?

    private init() {}

    func start() {
        queue.async {
            guard self.listener == nil else { return }

            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                let port = NWEndpoint.Port(rawValue: ComputerBarWidgetConstants.localSnapshotServerPort)!
                let listener = try NWListener(using: parameters, on: port)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    if case .failed = state {
                        self.listener?.cancel()
                        self.listener = nil
                    }
                }
                self.listener = listener
                listener.start(queue: self.queue)
            } catch {
                self.listener = nil
            }
        }
    }

    func update(snapshot: WidgetSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        queue.async {
            self.currentPayload = data
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed = state {
                connection.cancel()
            }
        }
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, _, _ in
            self?.respond(to: connection)
        }
    }

    private func respond(to connection: NWConnection) {
        let payload = currentPayload
        let header: String
        let body: Data

        if let payload {
            header = """
            HTTP/1.1 200 OK\r
            Content-Type: application/json\r
            Cache-Control: no-store\r
            Connection: close\r
            Content-Length: \(payload.count)\r
            \r
            """
            body = payload
        } else {
            header = """
            HTTP/1.1 204 No Content\r
            Cache-Control: no-store\r
            Connection: close\r
            Content-Length: 0\r
            \r
            """
            body = Data()
        }

        let responseData = Data(header.utf8) + body
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
