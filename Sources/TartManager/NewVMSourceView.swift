import SwiftUI

struct NewVMSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: CreateMode?

    var body: some View {
        if let mode {
            CreateVMView(mode: mode)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("New virtual machine").font(.system(size: 20, weight: .semibold)).padding(.bottom, 6)
                source("From an OCI image", subtitle: "Clone a registry image or a cached image",
                       symbol: "shippingbox", mode: .image)
                source("From a restore image", subtitle: "Create a macOS VM from an IPSW file",
                       symbol: "internaldrive", mode: .ipsw)
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                        .buttonStyle(WorkspaceButtonStyle())
                }.padding(.top, 6)
            }.padding(24).frame(width: 430)
                .background(WorkspaceStyle.background).foregroundStyle(WorkspaceStyle.text)
        }
    }

    private func source(_ title: String, subtitle: String, symbol: String, mode: CreateMode) -> some View {
        Button { self.mode = mode } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(WorkspaceStyle.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(WorkspaceStyle.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(WorkspaceStyle.muted)
            }.padding(16).workspacePanel().contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
