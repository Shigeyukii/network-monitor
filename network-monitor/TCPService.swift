import Foundation
import Network

struct TCPService {
    nonisolated func check(host: String, port: Int, timeoutSeconds: Double = 3.0) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                continuation.resume(returning: false)
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .tcp
            )

            var resumed = false
            let resume: (Bool) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(returning: result)
            }

            let timeoutWork = DispatchWorkItem { resume(false) }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + timeoutSeconds,
                execute: timeoutWork
            )

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeoutWork.cancel()
                    resume(true)
                case .failed, .cancelled:
                    timeoutWork.cancel()
                    resume(false)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }
}
