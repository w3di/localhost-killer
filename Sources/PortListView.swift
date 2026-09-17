import SwiftUI

struct PortListView: View {
    @ObservedObject var model: PortViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if model.processes.isEmpty {
                Text(model.isScanning ? "Сканирую…" : "Никто не слушает порты")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.processes) { process in
                            ProcessRow(
                                process: process,
                                denied: model.deniedPids.contains(process.pid),
                                onKill: { model.kill(process) }
                            )
                            if process.id != model.processes.last?.id {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }

            Divider()

            loginRow

            Divider()

            footer
        }
        .frame(width: 440)
        .onAppear {
            model.startPolling()
            model.refreshLaunchAtLogin()
        }
        .onDisappear { model.stopPolling() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "network")
            Text("Localhost Killer")
                .font(.headline)
            Spacer()
            Text("\(model.processes.count) proc")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var loginRow: some View {
        Toggle(isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )) {
            Label("Launch at Login", systemImage: "power")
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                model.killAllNode()
            } label: {
                Label("Kill all node", systemImage: "trash")
            }
            .disabled(model.nodeProcesses.isEmpty)

            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ProcessRow: View {
    let process: ListeningProcess
    let denied: Bool
    let onKill: () -> Void

    @State private var hoveringKill = false

    private var portsLabel: String {
        process.ports.map { ":\($0)" }.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(portsLabel)
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(denied ? Color.red : Color.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(process.name)
                        .font(.body)
                        .foregroundStyle(denied ? Color.red : Color.primary)
                    Text("\(process.pid)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(process.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onKill) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(hoveringKill ? Color.red : Color.secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .onHover { hoveringKill = $0 }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Полная команда в тултипе; при отказе прав — сообщение вместо неё.
        .help(denied ? "Permission denied — процесс чужого пользователя или root" : process.command)
    }
}
