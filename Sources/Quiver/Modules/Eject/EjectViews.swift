import SwiftUI

/// Inline controls shown in the menu-bar popover: each external drive with an eject button.
struct EjectQuickControls: View {
    @ObservedObject var module: EjectModule
    @ObservedObject private var service: EjectService

    init(module: EjectModule) {
        self.module = module
        self.service = module.service
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if service.volumes.isEmpty {
                Text("No external drives connected")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(service.volumes) { volume in
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive.fill").foregroundStyle(.secondary).font(.caption)
                        Text(volume.name).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 8)
                        Button {
                            service.eject(volume)
                        } label: {
                            Image(systemName: "eject.fill").font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Eject \(volume.name)")
                    }
                }
                if service.volumes.count > 1 {
                    Divider()
                    Button("Eject All") { service.ejectAll() }
                        .controlSize(.small)
                }
            }
        }
    }
}

/// Full settings pane: the same list with capacities, plus a note about busy disks.
struct EjectSettingsView: View {
    @ObservedObject var module: EjectModule
    @ObservedObject private var service: EjectService

    init(module: EjectModule) {
        self.module = module
        self.service = module.service
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "External Drives") {
                if service.volumes.isEmpty {
                    Text("No external or removable drives are connected.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(service.volumes.enumerated()), id: \.element.id) { index, volume in
                        HStack(spacing: 10) {
                            Image(systemName: "externaldrive.fill")
                                .font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(volume.name).font(.system(size: 13, weight: .medium))
                                if let capacity = EjectService.capacityString(volume.capacity) {
                                    Text(capacity).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Eject") { service.eject(volume) }
                                .controlSize(.small)
                        }
                        if index != service.volumes.count - 1 { Divider() }
                    }

                    if service.volumes.count > 1 {
                        Divider()
                        HStack {
                            Spacer()
                            Button("Eject All") { service.ejectAll() }
                                .controlSize(.small).buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            Text("A drive that’s still in use can’t be ejected — close any apps or Finder windows using it and try again.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
