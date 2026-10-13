import Foundation
import Darwin

/// Reads the current run's flag without changing VM state. Tart holds a
/// POSIX write lock on config.json; its owner identifies the exact VM process,
/// even across app restarts and when another TART_HOME has the same VM name.
enum VMRunSession {
    static func read(atVMDirectory directory: String) -> Bool? {
        let fd = open(directory + "/config.json", O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard let pid = lockOwner(fd), let argv = arguments(pid: pid),
              lockOwner(fd) == pid else { return nil }
        return isSuspendable(arguments: argv)
    }

    private static func lockOwner(_ fd: Int32) -> pid_t? {
        var lock = flock(l_start: 0, l_len: 0, l_pid: 0,
                         l_type: Int16(F_RDLCK), l_whence: Int16(SEEK_SET))
        guard fcntl(fd, F_GETLK, &lock) == 0,
              lock.l_type != F_UNLCK, lock.l_pid > 0 else { return nil }
        return lock.l_pid
    }

    static func arguments(pid: pid_t) -> [String]? {
        var limit: Int32 = 0
        var limitSize = MemoryLayout<Int32>.size
        var limitMIB = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&limitMIB, 2, &limit, &limitSize, nil, 0) == 0,
              limit > 0, limit <= 16 * 1024 * 1024 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(limit))
        var size = buffer.count
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        let result = buffer.withUnsafeMutableBytes {
            sysctl(&mib, 3, $0.baseAddress, &size, nil, 0)
        }
        guard result == 0, size <= buffer.count else { return nil }
        return decodeArguments(Data(buffer.prefix(size)))
    }

    /// KERN_PROCARGS2 contains argc, executable path, padding, argv, then
    /// environment. Bound parsing by argc so environment values cannot be flags.
    static func decodeArguments(_ data: Data) -> [String]? {
        let bytes = [UInt8](data)
        guard bytes.count >= MemoryLayout<Int32>.size else { return nil }
        let argc = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0, argc <= bytes.count else { return nil }
        var index = MemoryLayout<Int32>.size
        guard let pathEnd = bytes[index...].firstIndex(of: 0) else { return nil }
        index = pathEnd
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var argv: [String] = []
        for _ in 0..<argc {
            guard index < bytes.count,
                  let end = bytes[index...].firstIndex(of: 0),
                  let argument = String(bytes: bytes[index..<end], encoding: .utf8)
            else { return nil }
            argv.append(argument)
            index = end + 1
        }
        return argv
    }

    static func isSuspendable(arguments: [String]) -> Bool? {
        guard arguments.count >= 2, arguments[1] == "run" else { return nil }
        return arguments.dropFirst(2).prefix(while: { $0 != "--" }).contains("--suspendable")
    }
}
