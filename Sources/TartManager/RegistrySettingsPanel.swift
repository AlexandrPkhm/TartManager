import SwiftUI
import TartKit

/// Settings → Storage → Registries. Default pulls an image of the default
/// registry; Custom signs in to or out of a host that the user enters. All
/// gates are `AppModel` queries; the view holds only draft field values.
struct RegistrySettingsPanel: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedReference: String?
    @State private var pullRefusal: String?
    @State private var confirmingLowSpace = false
    @State private var registryURL = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        SettingsPanel(title: "Registries") {
            LabeledContent("Registry") {
                Picker("Registry", selection: Binding(
                    get: { model.registryMode },
                    set: { model.setRegistryMode($0) })) {
                    ForEach(RegistryMode.allCases, id: \.self) { mode in
                        Text(RegistrySettingsCopy.modeLabel(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            switch model.registryMode {
            case .standard: defaultRegistryContent
            case .custom: customRegistryContent
            }
        }
        .task { await model.refreshDefaultRegistryImages() }
        .confirmationDialog("Low disk space",
                            isPresented: $confirmingLowSpace,
                            titleVisibility: .visible) {
            Button("Pull Anyway") { startPull() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(RegistrySettingsCopy.lowSpaceMessage)
        }
    }

    // MARK: Default registry

    /// The selection when it is still in the list, else the first image: a
    /// download can replace the list while the panel is open.
    private var effectiveReference: String? {
        let images = model.defaultRegistryImages
        if let selectedReference, images.contains(where: { $0.reference == selectedReference }) {
            return selectedReference
        }
        return images.first?.reference
    }

    @ViewBuilder
    private var defaultRegistryContent: some View {
        LabeledContent("Image") {
            Picker("Image", selection: Binding(
                get: { effectiveReference ?? "" },
                set: {
                    selectedReference = $0
                    pullRefusal = nil
                })) {
                ForEach(model.defaultRegistryImages) { image in
                    Text(image.label).tag(image.reference)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        HStack {
            Spacer()
            Button("Pull") { requestPull() }
                .disabled(effectiveReference.map { model.pullBlockReason(reference: $0) != nil } ?? true)
        }
        if let pullRefusal {
            Text(pullRefusal)
                .font(.footnote)
                .foregroundStyle(WorkspaceStyle.error)
        } else if let reason = effectiveReference.flatMap({ model.pullBlockReason(reference: $0) }) {
            // A disabled state, such as a running pull, is not an error.
            Text(reason)
                .font(.footnote)
                .foregroundStyle(WorkspaceStyle.muted)
        }
        Text(RegistrySettingsCopy.pullCaption)
            .font(.footnote)
            .foregroundStyle(WorkspaceStyle.muted)
    }

    private func requestPull() {
        model.invalidateStorageProbeCache()
        if model.createSpaceVerdict()?.isTight == true {
            confirmingLowSpace = true
        } else {
            startPull()
        }
    }

    private func startPull() {
        guard let reference = effectiveReference else { return }
        pullRefusal = model.startPull(reference: reference)
    }

    // MARK: Custom registry

    private var host: String? { RegistryCredentialRules.normalizedHost(from: registryURL) }
    private var tartUnavailable: Bool { model.makeTartClient() == nil }

    @ViewBuilder
    private var customRegistryContent: some View {
        LabeledContent("Registry URL") {
            TextField("e.g. ghcr.io", text: $registryURL)
                .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 280)
        }
        LabeledContent("Username") {
            TextField("Username", text: $username)
                .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 280)
        }
        LabeledContent("Password / token") {
            SecureField("Password / token", text: $password)
                .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 280)
        }
        if !registryURL.isEmpty && host == nil {
            Text(RegistrySettingsCopy.hostError)
                .font(.caption)
                .foregroundStyle(WorkspaceStyle.error)
        }
        HStack {
            Button("Sign In") {
                // Snapshot BEFORE the Task: the Task body runs
                // asynchronously and would read the cleared @State values;
                // the captured locals live exactly as long as the operation,
                // and the UI state is cleared synchronously — the secret
                // never lingers.
                guard let host else { return }
                let username = username
                let password = password
                self.password = ""
                Task {
                    await model.registryLogin(host: host, username: username, password: password)
                }
            }
            .disabled(model.registryOperationInFlight
                      || tartUnavailable
                      || host == nil
                      || username.isEmpty
                      || password.isEmpty)
            Spacer()
            Button("Sign Out", role: .destructive) {
                guard let host else { return }
                Task { await model.registryLogout(host: host) }
            }
            .disabled(model.registryOperationInFlight
                      || tartUnavailable
                      || host == nil)
        }
        Text(RegistrySettingsCopy.signInCaption)
            .font(.footnote)
            .foregroundStyle(WorkspaceStyle.muted)
        if tartUnavailable {
            Text(RegistrySettingsCopy.signInUnavailableCaption)
                .font(.footnote)
                .foregroundStyle(WorkspaceStyle.muted)
        }
    }
}
