import Foundation
import Observation

enum BackendHealthStatus: Equatable {
    case unknown
    case checking
    case healthy
    case unhealthy
}

private final class HealthCheckSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

@MainActor
@Observable
final class HealthCheckService: BackendHealthChecking {
    private(set) var statuses: [UUID: BackendHealthStatus] = [:]

    private var timer: Timer?
    private var checkGenerations: [UUID: UInt64] = [:]
    private var isStarted = false

    private weak var settings: AppSettings?
    private weak var processController: CaddyProcessController?
    private weak var vhostStore: VhostStore?

    private let sessionDelegate = HealthCheckSessionDelegate()
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        config.waitsForConnectivity = false
        session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }

    func attach(
        settings: AppSettings,
        processController: CaddyProcessController,
        vhostStore: VhostStore
    ) {
        self.settings = settings
        self.processController = processController
        self.vhostStore = vhostStore
    }

    func start() {
        stop()
        isStarted = true
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        watchProcessStatus()
        checkAll()
    }

    func stop() {
        isStarted = false
        timer?.invalidate()
        timer = nil
    }

    func status(for id: UUID) -> BackendHealthStatus {
        statuses[id] ?? .unknown
    }

    func checkAll() {
        guard let processController, case .running = processController.status else {
            statuses = [:]
            checkGenerations = [:]
            return
        }
        guard let settings, let vhostStore else { return }

        let enabled = vhostStore.vhosts.filter(\.isEnabled)
        let enabledIDs = Set(enabled.map(\.id))
        statuses = statuses.filter { enabledIDs.contains($0.key) }
        checkGenerations = checkGenerations.filter { enabledIDs.contains($0.key) }

        for vhost in enabled {
            check(vhost: vhost, settings: settings)
        }
    }

    private func watchProcessStatus() {
        guard isStarted, let processController else { return }
        withObservationTracking {
            _ = processController.status
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.checkAll()
                self.watchProcessStatus()
            }
        }
    }

    private func check(vhost: Vhost, settings: AppSettings) {
        if vhost.isWildcard, vhost.kind != .reverseProxy {
            statuses[vhost.id] = .unknown
            return
        }

        guard let request = makeRequest(for: vhost, settings: settings) else {
            statuses[vhost.id] = .unknown
            return
        }

        let id = vhost.id
        let kind = vhost.kind
        let generation = (checkGenerations[id] ?? 0) + 1
        checkGenerations[id] = generation
        statuses[id] = .checking

        session.dataTask(with: request) { [weak self] _, response, error in
            Task { @MainActor in
                guard let self else { return }
                guard self.checkGenerations[id] == generation else { return }

                if let http = response as? HTTPURLResponse {
                    self.statuses[id] = (200..<500).contains(http.statusCode) ? .healthy : .unhealthy
                    return
                }

                if kind != .reverseProxy,
                   let urlError = error as? URLError,
                   urlError.code == .cancelled {
                    self.statuses[id] = .healthy
                    return
                }

                self.statuses[id] = .unhealthy
            }
        }.resume()
    }

    private func makeRequest(for vhost: Vhost, settings: AppSettings) -> URLRequest? {
        switch vhost.kind {
        case .reverseProxy:
            guard let target = vhost.proxyTarget?.trimmingCharacters(in: .whitespaces), !target.isEmpty else {
                return nil
            }
            let url: URL?
            if target.contains("://") {
                url = URL(string: target)
            } else {
                url = URL(string: "http://\(target)")
            }
            guard let url else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.setValue(vhost.domain, forHTTPHeaderField: "Host")
            return request

        case .staticSite, .phpSite:
            let port = settings.httpPort
            guard let url = URL(string: "http://localhost:\(port)/") else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.setValue(vhost.domain, forHTTPHeaderField: "Host")
            return request
        }
    }
}
