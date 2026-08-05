import Foundation
import Observation

enum BackendHealthStatus: Equatable {
    case unknown
    case checking
    case healthy
    case unhealthy
}

@Observable
final class HealthCheckService {
    private(set) var statuses: [UUID: BackendHealthStatus] = [:]

    private var timer: Timer?
    private var inFlight = Set<UUID>()
    private weak var settings: AppSettings?
    private weak var processController: CaddyProcessController?
    private weak var helperInstaller: HelperInstaller?
    private var vhostsProvider: (() -> [Vhost])?

    func configure(
        settings: AppSettings,
        processController: CaddyProcessController,
        helperInstaller: HelperInstaller,
        vhosts: @escaping () -> [Vhost]
    ) {
        self.settings = settings
        self.processController = processController
        self.helperInstaller = helperInstaller
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
        guard let settings, let helperInstaller, let vhostsProvider else { return }

        let enabled = vhostsProvider().filter(\.isEnabled)
        let enabledIDs = Set(enabled.map(\.id))
        statuses = statuses.filter { enabledIDs.contains($0.key) }

        for vhost in enabled {
            check(vhost: vhost, settings: settings, useStandardPorts: helperInstaller.isEnabled)
        }
    }

    private func check(vhost: Vhost, settings: AppSettings, useStandardPorts: Bool) {
        guard !inFlight.contains(vhost.id) else { return }

        let url: URL?
        switch vhost.kind {
        case .reverseProxy:
            if let target = vhost.proxyTarget, !target.isEmpty {
                if target.contains("://") {
                    url = URL(string: target)
                } else {
                    url = URL(string: "http://\(target)")
                }
            } else {
                url = vhost.browserURL(settings: settings, useStandardPorts: useStandardPorts)
            }
        case .staticSite, .phpSite:
            url = vhost.browserURL(settings: settings, useStandardPorts: useStandardPorts)
        }

        guard let url else {
            statuses[vhost.id] = .unknown
            return
        }

        // Skip wildcard primary domains — no concrete host to probe.
        if vhost.isWildcard, vhost.kind != .reverseProxy {
            statuses[vhost.id] = .unknown
            return
        }

        inFlight.insert(vhost.id)
        statuses[vhost.id] = .checking

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "HEAD"

        let id = vhost.id
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(id)
                if error != nil {
                    self.statuses[id] = .unhealthy
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    self.statuses[id] = .unhealthy
                    return
                }
                self.statuses[id] = (200..<400).contains(http.statusCode) ? .healthy : .unhealthy
            }
        }.resume()
    }
}
