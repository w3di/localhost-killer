import SwiftUI
import ServiceManagement
import os

/// Интервал автообновления, пока попап открыт.
let refreshInterval: TimeInterval = 3.0

private let appLog = Logger(subsystem: "com.localhostkiller.app", category: "App")

@MainActor
final class PortViewModel: ObservableObject {
    @Published private(set) var processes: [ListeningProcess] = []
    /// PID-ы, которые не удалось убить из-за EPERM — рисуем красным с тултипом.
    @Published private(set) var deniedPids: Set<pid_t> = []
    @Published private(set) var isScanning = false
    /// Включён ли автозапуск при входе в систему (SMAppService).
    @Published var launchAtLogin = false

    private var timer: Timer?

    var nodeProcesses: [ListeningProcess] {
        processes.filter { $0.name == "node" }
    }

    /// Сканирование в фоне, результат — на главный поток.
    func refresh() {
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let result = PortScanner.scan()
            await MainActor.run {
                self.processes = result
                // Чистим из деньдов те PID-ы, которых уже нет в списке.
                let alive = Set(result.map(\.pid))
                self.deniedPids.formIntersection(alive)
                self.isScanning = false
            }
        }
    }

    /// Старт таймера при открытии попапа + немедленное обновление.
    func startPolling() {
        refresh()
        timer?.invalidate()
        let t = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Стоп таймера при закрытии попапа — чтобы не жрать CPU.
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func kill(_ process: ListeningProcess) {
        let pid = process.pid
        Task.detached(priority: .userInitiated) {
            let result = ProcessKiller.kill(pid: pid)
            await MainActor.run {
                switch result {
                case .ok:
                    self.deniedPids.remove(pid)
                case .permissionDenied, .failed:
                    self.deniedPids.insert(pid)
                }
                self.refresh()
            }
        }
    }

    /// Синхронизирует @Published с реальным статусом системного login item.
    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Регистрирует/снимает приложение из «Объектов входа» через ServiceManagement (macOS 13+).
    /// Ad-hoc подписи достаточно для локального запуска.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            appLog.error("Login item \(enabled ? "register" : "unregister") наебнулся: \(error.localizedDescription, privacy: .public)")
        }
        // Читаем фактический статус — вдруг система не дала переключить.
        refreshLaunchAtLogin()
    }

    func killAllNode() {
        let pids = nodeProcesses.map(\.pid)
        guard !pids.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            var deniedAcc: [pid_t] = []
            for pid in pids {
                if case .ok = ProcessKiller.kill(pid: pid) {} else { deniedAcc.append(pid) }
            }
            let denied = deniedAcc
            await MainActor.run {
                self.deniedPids.formUnion(denied)
                self.refresh()
            }
        }
    }
}

@main
struct LocalhostKillerApp: App {
    @StateObject private var model = PortViewModel()

    var body: some Scene {
        MenuBarExtra {
            PortListView(model: model)
        } label: {
            // Иконка + число активных портов (число сокетов, не процессов).
            let count = model.processes.reduce(0) { $0 + $1.ports.count }
            HStack(spacing: 3) {
                Image(systemName: "network")
                if count > 0 {
                    Text("\(count)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
