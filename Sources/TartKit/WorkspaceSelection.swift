/// Reconciles a saved local-VM identity with the latest inventory, including deletion.
public enum WorkspaceSelection {
    public static func resolve(preferredName: String?, localVMs: [VMEntry]) -> VMEntry? {
        localVMs.first { $0.name == preferredName } ?? localVMs.first
    }
}
