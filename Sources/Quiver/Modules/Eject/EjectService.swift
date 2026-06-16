import AppKit
import Combine

/// Lists external/ejectable volumes and ejects them, refreshing as drives mount and unmount.
@MainActor
final class EjectService: ObservableObject {
    struct Volume: Identifiable, Equatable {
        let url: URL
        let name: String
        let capacity: Int64?       // total bytes, if known
        var id: URL { url }
    }

    @Published private(set) var volumes: [Volume] = []

    /// Routed to the module so failures (e.g. a busy disk) reach the shell's alert.
    var onError: ((String) -> Void)?

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification,
                     NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
    }

    private static let keys: Set<URLResourceKey> = [
        .volumeNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
        .volumeIsInternalKey, .volumeIsRootFileSystemKey, .volumeTotalCapacityKey,
    ]

    func refresh() {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(Self.keys), options: .skipHiddenVolumes) ?? []

        volumes = urls.compactMap { url -> Volume? in
            guard let values = try? url.resourceValues(forKeys: Self.keys) else { return nil }
            let ejectable = (values.volumeIsEjectable ?? false) || (values.volumeIsRemovable ?? false)
            let internalDrive = values.volumeIsInternal ?? false
            let isRoot = values.volumeIsRootFileSystem ?? false
            guard ejectable, !internalDrive, !isRoot else { return nil }
            let name = values.volumeName ?? url.lastPathComponent
            let capacity = values.volumeTotalCapacity.map { Int64($0) }
            return Volume(url: url, name: name, capacity: capacity)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Eject one volume. Unmounting can block, so it runs off the main thread; the result returns on main.
    func eject(_ volume: Volume) {
        let url = volume.url
        let name = volume.name
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            } catch {
                let message = "Couldn’t eject “\(name)”: \(error.localizedDescription)"
                DispatchQueue.main.async { [weak self] in self?.onError?(message) }
            }
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
    }

    func ejectAll() {
        for volume in volumes { eject(volume) }
    }

    static func capacityString(_ bytes: Int64?) -> String? {
        guard let bytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
