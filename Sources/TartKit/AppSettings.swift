import Foundation
import os

/// Persisted app settings (`UserDefaults`-backed, injectable suite for tests).
public struct AppSettings {
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static let storagePathKey = "storagePath"
    static let sshUserKey = "sshUser"
    static let snapshotsFolderKey = "snapshotsFolder"
    static let appearanceKey = "appearance"

    /// Appearance preference; missing or unknown values follow macOS.
    public var appearance: AppAppearance {
        get {
            AppAppearance(rawValue: defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.appearanceKey) }
    }

    /// Last selected local VM, restored by identity after the first successful inventory.
    public var selectedVMName: String? {
        get { defaults.string(forKey: "selectedVMName") }
        nonmutating set { defaults.set(newValue, forKey: "selectedVMName") }
    }

    /// Configured tart home ("VM storage"). `nil` until onboarding completes.
    /// Set only through `AppModel.attemptChooseStorage` (validated) — see
    /// `Sources/TartManager/AppModel.swift`.
    public var storagePath: String? {
        get { defaults.string(forKey: Self.storagePathKey) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: Self.storagePathKey)
            } else {
                defaults.removeObject(forKey: Self.storagePathKey)
            }
        }
    }

    /// Username for the copyable ssh command. Defaults to "admin".
    /// Trimming happens on read; an empty value falls back to "admin".
    public var sshUser: String {
        get {
            let value = defaults.string(forKey: Self.sshUserKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? "admin" : value
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.sshUserKey)
        }
    }

    /// Snapshot archives folder; nil until chosen or defaulted. Resolution is
    /// owned by `SnapshotService.resolveDirectory` (Issue 14) — nil here means
    /// "next to VM storage", never a volatile fallback.
    public var snapshotsFolder: String? {
        get { defaults.string(forKey: Self.snapshotsFolderKey) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: Self.snapshotsFolderKey)
            } else {
                defaults.removeObject(forKey: Self.snapshotsFolderKey)
            }
        }
    }

    static let pruneRetentionDaysKey = "pruneRetentionDays"

    /// The retention-age choices offered for prune.
    public static let pruneRetentionChoices = [7, 14, 30]

    /// Prune retention age in days; persisted, validated to the offered
    /// choices, defaulting to 14 (both when unset and when an unknown value
    /// is found — so the picker remembers its value across launches).
    public var pruneRetentionDays: Int {
        get {
            let raw = defaults.integer(forKey: Self.pruneRetentionDaysKey)
            return Self.pruneRetentionChoices.contains(raw) ? raw : 14
        }
        nonmutating set {
            guard Self.pruneRetentionChoices.contains(newValue) else { return }
            defaults.set(newValue, forKey: Self.pruneRetentionDaysKey)
        }
    }
}

extension AppSettings {
    static let sharedFoldersKey = "vmSharedFolders"

    /// Saved host-folder shares for a VM (empty for unknown VMs).
    public func sharedFolders(for vm: String) -> [VMFolderShare] {
        guard let data = defaults.data(forKey: Self.sharedFoldersKey),
              let byVM = try? JSONDecoder()
                  .decode([String: [VMFolderShare]].self, from: data) else { return [] }
        return byVM[vm] ?? []
    }

    /// Persists the share list for one VM (empty array removes its entry).
    /// The single write surface: the editor writes through
    /// `model.settings.setSharedFolders(...)` — there is no AppModel wrapper
    /// (finding 9). Logs the persisted count/tags, never host paths.
    public func setSharedFolders(_ shares: [VMFolderShare], for vm: String) {
        let key = Self.sharedFoldersKey
        var byVM: [String: [VMFolderShare]] = [:]
        if let data = defaults.data(forKey: key) {
            byVM = (try? JSONDecoder().decode([String: [VMFolderShare]].self, from: data)) ?? [:]
        }
        if shares.isEmpty {
            byVM.removeValue(forKey: vm)
        } else {
            byVM[vm] = shares
        }
        guard let data = try? JSONEncoder().encode(byVM) else {
            Logger.sharedFolders.error("failed to encode share list for \(vm, privacy: .public)")
            return
        }
        defaults.set(data, forKey: key)
        let summary = shares.map { "\($0.name)\($0.customTag.map { "@\($0)" } ?? "")" }
            .joined(separator: ", ")
        Logger.sharedFolders.info(
            "persisted \(shares.count, privacy: .public) share(s) for \(vm, privacy: .public): \(summary, privacy: .public)")
    }
}
