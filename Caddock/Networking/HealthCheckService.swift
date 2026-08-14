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

@Observable
final class HealthCheckService {
    private(set) var statuses: [UUID: BackendHealthStatus] = [:]

    private var timer: Timer?
    private var inFlight = Set<UUID>()
    private weak var settings: AppSettings?
    private weak var processController: CaddyProcessController?
    private var vhostsProvider: (() -> [Vhost])?

    private let sessionDelegate = HealthCheckSessionDelegate()
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        config.waitsForConnectivity = false
        session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }

    func configure(
        settings: AppSettings,
        processController: CaddyProcessController,
        vhosts: @escaping () -> [Vhost]
    ) {
        self.settings = settings
        self.processController = processController
        self.vhostsProvider = vhosts
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkAll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        checkAll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func status(for id: UUID) -> BackendHealthStatus {
        statuses[id] ?? .unknown
    }

    func checkAll() {
        guard let processController, case .running = processController.status else {
            statuses = [:]
            return
        }
        guard let settings, let vhostsProvider else { return }

        let enabled = vhostsProvider().filter(\.isEnabled)
        let enabledIDs = Set(enabled.map(\.id))
        statuses = statuses.filter { enabledIDs.contains($0.key) }

        for vhost in enabled {
            check(vhost: vhost, settings: settings)
        }
    }

    private func check(vhost: Vhost, settings: AppSettings) {
        guard !inFlight.contains(vhost.id) else { return }

        if vhost.isWildcard, vhost.kind != .reverseProxy {
            statuses[vhost.id] = .unknown
            return
        }

        guard let request = makeRequest(for: vhost, settings: settings) else {
            statuses[vhost.id] = .unknown
            return
        }

        inFlight.insert(vhost.id)
        statuses[vhost.id] = .checking

        let id = vhost.id
        let kind = vhost.kind
        session.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(id)

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
