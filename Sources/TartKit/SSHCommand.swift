/// The copyable remote-access command shown in the detail pane.
public enum SSHCommand {
    public static func text(user: String, ip: String) -> String {
        "ssh \(user)@\(ip)"
    }
}
