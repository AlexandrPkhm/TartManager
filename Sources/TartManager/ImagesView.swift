import SwiftUI
import TartKit

struct ImagesView: View {
    let images: [VMEntry]
    @State private var cloneTarget: VMEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Images").font(.system(size: 22, weight: .semibold)).tracking(-0.6)
                    Text("Clone an image to create a virtual machine.")
                        .font(.system(size: 12)).foregroundStyle(WorkspaceStyle.muted)
                }.padding(.bottom, 13)
                if images.isEmpty {
                    WorkspaceEmptyState(symbol: "shippingbox", title: "No cached images",
                                        message: "Create a VM from an OCI image to download it.") { EmptyView() }
                }
                ForEach(images) { entry in imageCard(entry) }
            }.padding(.horizontal, 32).padding(.top, 29).padding(.bottom, 22)
        }
        .sheet(item: $cloneTarget) { entry in
            // OCI references must use the image-creation coordinator; the
            // local-clone sheet deliberately rejects nonlocal sources.
            CreateVMView(imageReference: entry.name)
        }
    }

    private func imageCard(_ entry: VMEntry) -> some View {
        let display = OCIImageDisplay(reference: entry.name)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "shippingbox").foregroundStyle(WorkspaceStyle.muted)
                Text(display.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(display.isDigest ? "Digest" : "Tagged").font(.system(size: 11))
                    .foregroundStyle(WorkspaceStyle.accent).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(WorkspaceStyle.selected, in: RoundedRectangle(cornerRadius: 5))
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(display.repository)
                if let version = display.version { Text(version) }
            }.font(.system(size: 11, design: .monospaced)).foregroundStyle(WorkspaceStyle.muted)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(display.reference)
            HStack {
                Text("Cached OCI image").font(.system(size: 11)).foregroundStyle(WorkspaceStyle.muted)
                Spacer()
                Button { cloneTarget = entry } label: { Label("Clone…", systemImage: "doc.on.doc") }
                    .buttonStyle(WorkspaceButtonStyle())
                    .accessibilityLabel("Clone \(display.reference)")
            }
        }.padding(18).workspacePanel()
            .contextMenu {
                Button("Copy image reference") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(display.reference, forType: .string)
                }
            }
    }
}
