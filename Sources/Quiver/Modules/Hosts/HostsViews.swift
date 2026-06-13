import SwiftUI

// MARK: - Full editor (main window detail pane)

struct HostsSettingsView: View {
    @ObservedObject var module: HostsModule
    @ObservedObject var viewModel: HostsViewModel

    @State private var showingAdd = false
    @State private var editingRule: HostRule?
    @State private var pendingDelete: HostRule?

    init(module: HostsModule) {
        _module = ObservedObject(wrappedValue: module)
        _viewModel = ObservedObject(wrappedValue: module.viewModel)
    }

    private var busy: Bool { viewModel.isApplyingChange || module.isUpdatingPrivilegedAccess }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Write mode") {
                SettingRow(
                    title: "Passwordless writes",
                    subtitle: module.passwordlessEnabled
                        ? "A one-time root-owned helper applies changes without prompting."
                        : "Each change uses the standard macOS administrator prompt. Turn this on to approve once and stop being asked."
                ) {
                    HStack(spacing: 8) {
                        if module.isUpdatingPrivilegedAccess { ProgressView().controlSize(.small) }
                        Toggle("", isOn: Binding(
                            get: { module.passwordlessEnabled },
                            set: { module.setPasswordless($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(module.isUpdatingPrivilegedAccess)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("RULES")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
                    Text("· \(viewModel.ruleCount)").font(.caption2).foregroundStyle(.tertiary)
                    if viewModel.isApplyingChange { ProgressView().controlSize(.small) }
                    Spacer()
                    Button { module.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).help("Reload /etc/hosts")
                    Button { showingAdd = true } label: { Label("Add Rule", systemImage: "plus") }
                        .controlSize(.small)
                        .keyboardShortcut("n")
                }

                if viewModel.rules.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "tray").font(.title2).foregroundStyle(.secondary)
                            Text("No host rules yet.").foregroundStyle(.secondary)
                            Text("Add one to start mapping hostnames.").font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.rules) { rule in
                            HostsRuleRow(
                                rule: rule,
                                busy: busy,
                                onToggle: { enabled in _ = viewModel.setRule(rule, enabled: enabled) },
                                onEdit: { editingRule = rule },
                                onDelete: { pendingDelete = rule }
                            )
                        }
                    }
                }

                Text(viewModel.statusMessage).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .sheet(isPresented: $showingAdd) {
            RuleEditorSheet(
                title: "Add Host Rule", buttonTitle: "Add",
                initialIPAddresses: "127.0.0.1", initialHostnames: "", initialComment: "", initialEnabled: true
            ) { ip, hosts, comment, enabled in
                viewModel.addRule(ipAddressesField: ip, hostnamesField: hosts, comment: comment, enabled: enabled)
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorSheet(
                title: "Edit Host Rule", buttonTitle: "Save",
                initialIPAddresses: rule.ipAddresses.joined(separator: " "),
                initialHostnames: rule.hostnamesJoined,
                initialComment: rule.comment,
                initialEnabled: rule.hasAnyEnabled
            ) { ip, hosts, comment, enabled in
                viewModel.updateRule(rule, ipAddressesField: ip, hostnamesField: hosts, comment: comment, enabled: enabled)
            }
        }
        .alert("Remove this rule?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { rule in
            Button("Remove", role: .destructive) { _ = viewModel.removeRule(rule); pendingDelete = nil }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { rule in
            Text("This removes \(rule.displayTitle) from /etc/hosts.")
        }
    }
}

private struct HostsRuleRow: View {
    let rule: HostRule
    let busy: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { rule.hasAnyEnabled }, set: onToggle))
                .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(busy)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.hostnamesJoined.isEmpty ? "(no hostname)" : rule.hostnamesJoined)
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if rule.isPartiallyEnabled {
                        Text("partial").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                            .foregroundStyle(.orange)
                    }
                }
                Text(rule.ipAddressesJoined).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                if !rule.comment.isEmpty {
                    Text(rule.comment).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button("Edit", action: onEdit).controlSize(.small).disabled(busy)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .controlSize(.small).disabled(busy).help("Remove rule")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
        .opacity(rule.hasAnyEnabled ? 1 : 0.6)
    }
}

// MARK: - Popover quick controls

struct HostsQuickControls: View {
    @ObservedObject var viewModel: HostsViewModel

    init(module: HostsModule) {
        _viewModel = ObservedObject(wrappedValue: module.viewModel)
    }

    private let inlineLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.rules.isEmpty {
                Text("No host rules yet — open the editor to add one.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.rules.prefix(inlineLimit)) { rule in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { rule.hasAnyEnabled },
                            set: { _ = viewModel.setRule(rule, enabled: $0) }
                        ))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .disabled(viewModel.isApplyingChange)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(rule.hostnamesJoined.isEmpty ? "(no hostname)" : rule.hostnamesJoined)
                                .font(.caption).lineLimit(1)
                            Text(rule.ipAddressesJoined)
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                }
                if viewModel.rules.count > inlineLimit {
                    Text("+\(viewModel.rules.count - inlineLimit) more — open the editor")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Add / edit sheet

private struct RuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let buttonTitle: String
    let onSave: (String, String, String, Bool) -> Bool

    @State private var ip: String
    @State private var hosts: String
    @State private var comment: String
    @State private var enabled: Bool

    init(title: String, buttonTitle: String, initialIPAddresses: String, initialHostnames: String, initialComment: String, initialEnabled: Bool, onSave: @escaping (String, String, String, Bool) -> Bool) {
        self.title = title
        self.buttonTitle = buttonTitle
        self.onSave = onSave
        _ip = State(initialValue: initialIPAddresses)
        _hosts = State(initialValue: initialHostnames)
        _comment = State(initialValue: initialComment)
        _enabled = State(initialValue: initialEnabled)
    }

    private var canSave: Bool {
        !ip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !hosts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.bold())
            Text("Use spaces or commas between IPs and hostnames. A rule can mix IPv4 and IPv6.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            field("IP addresses", text: $ip, prompt: "127.0.0.1 ::1")
            field("Hostnames", text: $hosts, prompt: "example.local api.example.local")
            field("Comment", text: $comment, prompt: "Optional")

            Toggle("Rule enabled", isOn: $enabled).toggleStyle(.switch)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(buttonTitle) { if onSave(ip, hosts, comment, enabled) { dismiss() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField(prompt, text: text).textFieldStyle(.roundedBorder)
        }
    }
}
