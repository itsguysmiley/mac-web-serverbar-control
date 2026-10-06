import Cocoa
import Darwin

// MARK: - CONFIG (MacPorts layout) ────────────────────────────────────────────

enum Cfg {
    static let nginxBin   = "/opt/local/sbin/nginx"
    static let nginxConf  = "/opt/local/etc/nginx/nginx.conf"
    static let nginxPort: UInt16 = 80

    static let mariadbConf = "/opt/local/etc/mariadb-10.11/my.cnf"
    static let mariadbBinCandidates = [
        "/opt/local/lib/mariadb-10.11/bin/mariadbd",
        "/opt/local/lib/mariadb-10.11/bin/mysqld",
        "/opt/local/libexec/mariadb-10.11/mariadbd",
        "/opt/local/sbin/mariadbd",
        "/opt/local/sbin/mysqld",
    ]
    static let mariadbPort: UInt16 = 3306

    static let phpBin   = "/opt/local/bin/php"
    static let fpmBin   = "/opt/local/sbin/php-fpm84"
    static let fpmConf  = "/opt/local/etc/php84/php-fpm.conf"
    static let phpIni   = "/opt/local/etc/php84/php.ini"

    static let docRoot  = "/Users/geoff/Sites"
    static let baseURL  = "http://localhost"

    static let env = ["PATH": "/opt/local/bin:/opt/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"]
}

let supportDir: String = {
    let d = NSHomeDirectory() + "/Library/Application Support/ServerBar"
    try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
    return d
}()

// MARK: - Helpers ─────────────────────────────────────────────────────────────

func isListening(_ port: UInt16) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let r = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    return r == 0
}

func waitFor(port: UInt16, open: Bool, timeout: TimeInterval) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if isListening(port) == open { return true }
        Thread.sleep(forTimeInterval: 0.25)
    }
    return isListening(port) == open
}

func tail(_ path: String, lines: Int = 12) -> String {
    guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
    return s.split(separator: "\n").suffix(lines).joined(separator: "\n")
}

func makeProcess(_ path: String, _ args: [String], log: String) -> Process {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.environment = Cfg.env
    FileManager.default.createFile(atPath: log, contents: nil)
    let h = FileHandle(forWritingAtPath: log)
    p.standardOutput = h
    p.standardError = h
    return p
}

func debug(_ msg: String) {
    let path = supportDir + "/serverbar.log"
    let line = "\(Date()) \(msg)\n"
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

func exec(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> (ok: Bool, out: String) {
    guard FileManager.default.isExecutableFile(atPath: path) else {
        debug("NOT EXECUTABLE: \(path)")
        return (false, "Not found or not executable:\n\(path)")
    }
    let log = supportDir + "/exec-" + (path as NSString).lastPathComponent + ".log"
    let p = makeProcess(path, args, log: log)
    do { try p.run() } catch {
        debug("LAUNCH FAILED: \(path) \(error)")
        return (false, "Could not launch \(path):\n\(error)")
    }
    let end = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.1) }
    if p.isRunning {
        p.terminate()
        debug("TIMEOUT after \(Int(timeout))s: \(path) \(args.joined(separator: " "))")
        return (false, "Timed out after \(Int(timeout))s:\n\(path) \(args.joined(separator: " "))\n\n" + tail(log))
    }
    debug("\(path) \(args.joined(separator: " ")) -> exit \(p.terminationStatus)")
    return (p.terminationStatus == 0, tail(log))
}

func pidAlive(_ file: String) -> Bool {
    guard let s = try? String(contentsOfFile: file, encoding: .utf8),
          let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
    return kill(pid, 0) == 0
}

func killPidFile(_ file: String) {
    guard let s = try? String(contentsOfFile: file, encoding: .utf8),
          let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
    kill(pid, SIGTERM)
}

func capture(_ path: String, _ args: [String]) -> String? {
    let r = exec(path, args)
    return r.ok ? r.out.trimmingCharacters(in: .whitespacesAndNewlines) : nil
}

func showAlert(_ title: String, _ text: String) {
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

func statusLight(_ on: Bool) -> NSImage {
    NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
        (on ? NSColor.systemGreen : NSColor.systemRed).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        return true
    }
}

// MARK: - Services ────────────────────────────────────────────────────────────

func listenerPIDs(_ port: UInt16) -> [Int32] {
    let r = exec("/usr/sbin/lsof", ["-nP", "-t", "-iTCP:\(port)", "-sTCP:LISTEN"])
    return r.out.split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
}

func terminateListeners(_ port: UInt16) {
    for pid in listenerPIDs(port) { kill(pid, SIGTERM) }
}

enum Nginx {
    static let fpmPid = supportDir + "/php-fpm.pid"
    static var running: Bool { isListening(Cfg.nginxPort) }
    static var fpmRunning: Bool { isListening(9000) }
    static var fpmChild: Process?

    static func start() {
        if !Cfg.fpmBin.isEmpty && !fpmRunning {
            let p = makeProcess(Cfg.fpmBin, ["--nodaemonize", "--fpm-config", Cfg.fpmConf, "--pid", fpmPid],
                                log: supportDir + "/php-fpm.log")
            do { try p.run(); fpmChild = p; debug("php-fpm spawned pid \(p.processIdentifier)") }
            catch { showAlert("php-fpm failed to launch", "\(error)") }
            if !waitFor(port: 9000, open: true, timeout: 5) {
                showAlert("php-fpm is not listening on 9000 (nginx will still be started)", tail(supportDir + "/php-fpm.log"))
            }
        }
        let r = exec(Cfg.nginxBin, ["-c", Cfg.nginxConf])
        if !r.ok { showAlert("nginx failed to start", r.out); return }
        if !waitFor(port: Cfg.nginxPort, open: true, timeout: 4) {
            showAlert("nginx started but port \(Cfg.nginxPort) isn't open", r.out)
        }
    }

    static func stop() {
        if running {
            _ = exec(Cfg.nginxBin, ["-c", Cfg.nginxConf, "-s", "stop"])
            if !waitFor(port: Cfg.nginxPort, open: false, timeout: 3) {
                terminateListeners(Cfg.nginxPort)
            }
        }
        if !Cfg.fpmBin.isEmpty {
            if let p = fpmChild, p.isRunning { p.terminate() } else { killPidFile(fpmPid) }
            if !waitFor(port: 9000, open: false, timeout: 3) { terminateListeners(9000) }
            fpmChild = nil
        }
        if !waitFor(port: Cfg.nginxPort, open: false, timeout: 5) {
            showAlert("nginx is still running", "Port \(Cfg.nginxPort) is still open after stopping.")
        }
    }
}

enum MariaDB {
    static var child: Process?
    static let pidFile = supportDir + "/mariadb.pid"
    static let logFile = supportDir + "/mariadb.log"
    static var running: Bool { isListening(Cfg.mariadbPort) }

    static var binary: String? {
        Cfg.mariadbBinCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func start() {
        guard let bin = binary else {
            showAlert("MariaDB binary not found",
                      "Checked:\n" + Cfg.mariadbBinCandidates.joined(separator: "\n"))
            return
        }
        let p = makeProcess(bin, ["--defaults-file=\(Cfg.mariadbConf)", "--pid-file=\(pidFile)"], log: logFile)
        do { try p.run() } catch { showAlert("MariaDB failed to launch", "\(error)"); return }
        child = p
        if !waitFor(port: Cfg.mariadbPort, open: true, timeout: 20) {
            let state = p.isRunning ? "Still starting or not listening on \(Cfg.mariadbPort)."
                                    : "Exited with status \(p.terminationStatus)."
            showAlert("MariaDB did not start", state + "\n\n" + tail(logFile))
        }
    }

    static func stop() {
        guard running else { return }
        if let p = child, p.isRunning { p.terminate() } else { killPidFile(pidFile) }
        if !waitFor(port: Cfg.mariadbPort, open: false, timeout: 8) {
            terminateListeners(Cfg.mariadbPort)
        }
        if !waitFor(port: Cfg.mariadbPort, open: false, timeout: 15) {
            showAlert("MariaDB is still running", "Port \(Cfg.mariadbPort) is still open after stopping.")
        }
    }
}

// MARK: - App ─────────────────────────────────────────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let work = DispatchQueue(label: "serverbar.work")
    private lazy var phpVersion: String = {
        capture(Cfg.phpBin, ["-r", "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;"]) ?? "?"
    }()

    func applicationDidFinishLaunching(_ n: Notification) {
        if let b = statusItem.button {
            if let img = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "ServerBar") {
                img.isTemplate = true
                b.image = img
            } else {
                b.title = "⚙︎ Srv"
            }
        }
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
        work.async {
            if !Nginx.running { Nginx.start() }
            if !MariaDB.running { MariaDB.start() }
        }
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    private func item(_ title: String, _ sel: Selector?, light: Bool? = nil, object: Any? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        i.representedObject = object
        if let l = light { i.image = statusLight(l) }
        return i
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let ng = Nginx.running, db = MariaDB.running

        menu.addItem(item(ng ? "Stop Nginx" : "Start Nginx", #selector(toggleNginx), light: ng))
        menu.addItem(item(db ? "Stop MariaDB" : "Start MariaDB", #selector(toggleMariaDB), light: db))
        menu.addItem(item("Start All Services", #selector(startAll)))
        menu.addItem(item("Stop All Services", #selector(stopAll)))
        menu.addItem(.separator())

        menu.addItem(item("Open www Root", #selector(revealSites)))

        menu.addItem(item("Open Localhost", #selector(openURLItem(_:)), object: Cfg.baseURL))
        menu.addItem(item("Open phpinfo()", #selector(openPhpInfo)))
        menu.addItem(.separator())

        let edit = NSMenuItem(title: "Edit Configs", action: nil, keyEquivalent: "")
        let es = NSMenu()
        es.addItem(item("Nginx", #selector(editFile(_:)), object: Cfg.nginxConf))
        es.addItem(item("MariaDB", #selector(editFile(_:)), object: Cfg.mariadbConf))
        es.addItem(item("php\(phpVersion)", #selector(editFile(_:)), object: Cfg.phpIni))
        if !Cfg.fpmBin.isEmpty {
            es.addItem(item("php-fpm", #selector(editFile(_:)), object: Cfg.fpmConf))
        }
        edit.submenu = es
        menu.addItem(edit)
        menu.addItem(.separator())

        menu.addItem(item("Quit All and Exit App", #selector(quitAll)))
    }

    @objc private func toggleNginx() {
        work.async { debug("toggleNginx: running=\(Nginx.running)"); Nginx.running ? Nginx.stop() : Nginx.start(); debug("toggleNginx done: running=\(Nginx.running)") }
    }

    @objc private func toggleMariaDB() {
        work.async { MariaDB.running ? MariaDB.stop() : MariaDB.start() }
    }

    @objc private func startAll() {
        work.async {
            if !Nginx.running { Nginx.start() }
            if !MariaDB.running { MariaDB.start() }
        }
    }

    @objc private func stopAll() {
        work.async { Nginx.stop(); MariaDB.stop() }
    }

    @objc private func quitAll() {
        work.async {
            Nginx.stop(); MariaDB.stop()
            exit(0)
        }
    }

    @objc private func openURLItem(_ s: NSMenuItem) {
        if let str = s.representedObject as? String, let url = URL(string: str) { NSWorkspace.shared.open(url) }
    }

    @objc private func openPhpInfo() {
        let file = "\(Cfg.docRoot)/phpinfo.php"
        if !FileManager.default.fileExists(atPath: file) {
            do { try "<?php phpinfo();\n".write(toFile: file, atomically: true, encoding: .utf8) }
            catch { showAlert("Couldn't create phpinfo.php", "\(file)\n\n\(error.localizedDescription)"); return }
        }
        NSWorkspace.shared.open(URL(string: "\(Cfg.baseURL)/phpinfo.php")!)
    }

    @objc private func revealSites() {
        NSWorkspace.shared.open(URL(fileURLWithPath: Cfg.docRoot))
    }

    @objc private func editFile(_ s: NSMenuItem) {
        guard let path = s.representedObject as? String else { return }
        let r = exec("/usr/bin/open", ["-t", path])
        if !r.ok { showAlert("Couldn't open \(path)", r.out) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()