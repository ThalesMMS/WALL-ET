import Foundation
import Network

extension ElectrumService {
    func connect() {
        connectionStatePublisher.send(.connecting)

        let host = NWEndpoint.Host(currentServer.host)
        let port = NWEndpoint.Port(rawValue: UInt16(currentServer.port))!

        let parameters: NWParameters
        if currentServer.useSSL {
            parameters = NWParameters.tls
            let options = NWProtocolTLS.Options()
            parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        } else {
            parameters = .tcp
        }

        connection = NWConnection(host: host, port: port, using: parameters)

        connection?.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionStateChange(state)
        }

        connection?.start(queue: queue)
        startReceiving()
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        requestsLock.lock()
        pendingRequests.values.forEach { $0.timeoutWorkItem?.cancel() }
        pendingRequests.removeAll()
        requestsLock.unlock()
        connectionStatePublisher.send(.disconnected)
    }

    func ensureConnected() {
        if connection == nil {
            connect()
        }
    }

    private func handleConnectionStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            connectionStatePublisher.send(.connected)
            performHandshake()
        case .failed(let error):
            connectionStatePublisher.send(.failed(error))
            reconnect()
        case .cancelled:
            connectionStatePublisher.send(.disconnected)
        default:
            break
        }
    }

    private func reconnect() {
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.connect()
        }
    }

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                self?.handleReceivedData(data)
            }

            if let error {
                print("Receive error: \(error)")
            }

            if !isComplete {
                self?.startReceiving()
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        let responses = string.split(separator: "\n")

        for response in responses {
            guard let responseData = response.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                continue
            }
            handleResponse(json)
        }
    }
}
