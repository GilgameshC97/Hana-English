import Foundation
import Network
import Observation

@Observable
final class HanaNetworkMonitor {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "HanaNetworkMonitor")

    private(set) var isExpensive = false
    private(set) var usesCellular = false
    private(set) var status: NWPath.Status = .requiresConnection

    var shouldTreatAsMetered: Bool {
        isExpensive || usesCellular
    }

    var statusTitle: String {
        switch status {
        case .satisfied:
            "Connected"
        case .unsatisfied:
            "Disconnected"
        case .requiresConnection:
            "Connection Required"
        @unknown default:
            "Unknown"
        }
    }

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.status = path.status
                self?.isExpensive = path.isExpensive
                self?.usesCellular = path.usesInterfaceType(.cellular)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
