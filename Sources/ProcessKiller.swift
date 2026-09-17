import Foundation
import os

private let killerLog = Logger(subsystem: "com.localhostkiller.app", category: "ProcessKiller")

/// Через сколько после SIGTERM проверять живучесть и добивать SIGKILL.
let sigkillEscalationDelay: TimeInterval = 2.0

enum KillResult: Equatable {
    case ok
    case permissionDenied   // EPERM — чужой пользователь / root-процесс
    case failed(String)     // прочая ошибка errno
}

enum ProcessKiller {
    /// SIGTERM, затем — если процесс через `sigkillEscalationDelay` ещё жив — SIGKILL.
    /// Блокирующий вызов: держать в фоне, не на главном потоке.
    static func kill(pid: pid_t) -> KillResult {
        if Darwin.kill(pid, SIGTERM) != 0 {
            let err = errno
            return classify(errno: err, pid: pid, signal: "SIGTERM")
        }

        // kill(pid, 0) == 0 значит процесс ещё существует и мы имеем на него права.
        Thread.sleep(forTimeInterval: sigkillEscalationDelay)
        if Darwin.kill(pid, 0) == 0 {
            killerLog.notice("PID \(pid) пережил SIGTERM, добиваю SIGKILL")
            if Darwin.kill(pid, SIGKILL) != 0 {
                let err = errno
                // ESRCH тут — не ошибка: процесс успел умереть в зазоре.
                if err == ESRCH { return .ok }
                return classify(errno: err, pid: pid, signal: "SIGKILL")
            }
        }
        return .ok
    }

    private static func classify(errno err: Int32, pid: pid_t, signal: String) -> KillResult {
        switch err {
        case EPERM:
            killerLog.error("\(signal) для PID \(pid): EPERM")
            return .permissionDenied
        case ESRCH:
            // Процесс уже мёртв — считаем успехом.
            return .ok
        default:
            let message = String(cString: strerror(err))
            killerLog.error("\(signal) для PID \(pid) наебнулся: \(message, privacy: .public)")
            return .failed(message)
        }
    }
}
