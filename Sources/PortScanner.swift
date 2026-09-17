import Foundation
import os

/// Один слушающий процесс: один PID может держать несколько портов.
struct ListeningProcess: Identifiable, Hashable {
    let pid: pid_t
    let name: String
    let command: String
    let ports: [Int]

    var id: pid_t { pid }
}

private let scannerLog = Logger(subsystem: "com.localhostkiller.app", category: "PortScanner")

/// Процессы, которые нет смысла (и нельзя) убивать — системные.
let excludedProcessNames: Set<String> = [
    "rapportd",
    "ControlCenter",
    "sharingd",
    "AirPlayXPCHelper",
    "identityservicesd",
]

enum PortScanner {
    /// Запускает lsof в машиночитаемом формате -F и возвращает сгруппированные по PID процессы.
    /// Формат -F pcn: строки-записи с префиксом-полем (p=pid, c=command, n=адрес).
    /// Табличный вывод lsof намеренно не используется — он ломается на командах с пробелами.
    static func scan() -> [ListeningProcess] {
        guard let output = runLsof() else { return [] }
        return parse(output)
    }

    private static func runLsof() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            scannerLog.error("lsof запуск наебнулся: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        // Читаем до завершения, чтобы не упереться в лимит буфера трубы.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let text = String(data: data, encoding: .utf8) else {
            scannerLog.error("lsof выдал не-UTF8, пропускаю")
            return nil
        }
        return text
    }

    /// Разбор формата -F. Каждая строка = одно поле: первый символ — тип поля, остальное — значение.
    /// Записи идут набором: сначала строка p<pid>, затем c<command>, затем одна или несколько строк
    /// n<адрес> для каждого сокета этого процесса. Новая строка p<pid> начинает новую запись.
    static func parse(_ output: String) -> [ListeningProcess] {
        // Аккумулируем по PID: имя + множество портов (дедуп через Set).
        var order: [pid_t] = []
        var names: [pid_t: String] = [:]
        var portsByPid: [pid_t: Set<Int>] = [:]

        var currentPid: pid_t?

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let fieldType = rawLine.first else { continue }
            let value = rawLine.dropFirst()

            switch fieldType {
            case "p":
                guard let pid = pid_t(value) else { currentPid = nil; continue }
                currentPid = pid
                if portsByPid[pid] == nil {
                    portsByPid[pid] = []
                    order.append(pid)
                }
            case "c":
                if let pid = currentPid {
                    names[pid] = String(value)
                }
            case "n":
                if let pid = currentPid, let port = port(fromAddress: value) {
                    portsByPid[pid, default: []].insert(port)
                }
            default:
                continue
            }
        }

        let processes: [ListeningProcess] = order.compactMap { pid in
            let name = names[pid] ?? "?"
            if excludedProcessNames.contains(name) { return nil }
            guard let ports = portsByPid[pid], !ports.isEmpty else { return nil }
            return ListeningProcess(
                pid: pid,
                name: name,
                command: commandLine(for: pid),
                ports: ports.sorted()
            )
        }

        return sorted(processes)
    }

    /// Достаёт номер порта из адреса lsof: `*:3000`, `127.0.0.1:7768`, `[::1]:5432`.
    /// Порт — всё после последнего двоеточия (у IPv6 двоеточий много, поэтому именно последнее).
    private static func port(fromAddress address: Substring) -> Int? {
        guard let colonIndex = address.lastIndex(of: ":") else { return nil }
        let portPart = address[address.index(after: colonIndex)...]
        return Int(portPart)
    }

    /// Полная командная строка процесса через `ps -o command=`. Пустая строка если процесс уже ушёл.
    private static func commandLine(for pid: pid_t) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "command=", "-p", String(pid)]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Сначала node-процессы, потом остальные; внутри группы — по младшему порту, затем по имени.
    private static func sorted(_ processes: [ListeningProcess]) -> [ListeningProcess] {
        processes.sorted { lhs, rhs in
            let lhsNode = lhs.name == "node"
            let rhsNode = rhs.name == "node"
            if lhsNode != rhsNode { return lhsNode }

            let lhsPort = lhs.ports.first ?? Int.max
            let rhsPort = rhs.ports.first ?? Int.max
            if lhsPort != rhsPort { return lhsPort < rhsPort }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
