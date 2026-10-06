# ServerBar

A tiny macOS menu bar app for starting and stopping a manually installed local web stack (**nginx**, **PHP-FPM** and **MariaDB**), in the spirit of XAMPP's control panel. No Dock icon, no dependencies, one Swift source file.

```
 ● Stop Nginx            (green/red status light)
 ● Start MariaDB
   Start All Services
   Stop All Services
 ─────────────────────
   Open www Root
   Open Localhost
   Open phpinfo()
 ─────────────────────
   Edit Configs  ▸  Nginx
                    MariaDB
                    php8.4
                    php-fpm
 ─────────────────────
   Quit All and Exit App
```

## Why

Homebrew has deprecated Intel Macs, and many people now run nginx, PHP and MariaDB from MacPorts or a manual build. ServerBar gives that setup a one-click control panel without launchd plists, root-owned daemons or a terminal.

Built and tested on an Intel MacBook Pro (2019) with a MacPorts install. Because it is plain Swift/AppKit it should also build on Apple Silicon, but that is untested.

## Features

- **Start/Stop toggles** for nginx (with PHP-FPM) and MariaDB, each with a red/green status light.
- **Start All / Stop All** services.
- **Autostart on launch:** anything not already running is started when the app opens.
- **Open www Root** (reveals your web root in Finder), **Open Localhost**, and **Open phpinfo()** (creates `phpinfo.php` in your web root if missing).
- **Edit Configs** opens nginx, MariaDB, `php.ini` and `php-fpm.conf` in your default text editor. The PHP entry shows the active version (e.g. `php8.4`).
- **Quit All and Exit App** stops everything, then exits.
- **Real status:** the lights reflect whether the port is actually accepting connections, so they stay correct if you start or stop a service from the terminal.
- **Errors you can read:** a failed start or stop shows an alert with the service's own output, and a debug log is kept.
- Runs entirely as your user. No `sudo`, no password prompts.

## Requirements

- macOS with the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not required.
- nginx, PHP (with PHP-FPM) and MariaDB already installed and configured.
- An nginx config that passes `.php` requests to `127.0.0.1:9000`.

## Build

```bash
git clone https://github.com/itsguysmiley/mac-web-serverbar-control.git
cd mac-web-serverbar-control
# edit the Cfg block at the top of main.swift first (see Configuration)
./build.sh
open ServerBar.app
```

`build.sh` compiles `main.swift` with `swiftc` and assembles `ServerBar.app` with an `Info.plist` that sets `LSUIElement` (menu bar only). If `AppIcon.icns` exists next to the script, it is bundled as the app icon.

To install it:

```bash
cp -R ServerBar.app /Applications/
```

To start it at login, add it under **System Settings → General → Login Items**. Combined with autostart, your whole stack comes up when you log in.

## Configuration

All paths live in the `Cfg` enum at the top of `main.swift`. The defaults match a **MacPorts** layout with PHP 8.4 and MariaDB 10.11:

```swift
enum Cfg {
    static let nginxBin   = "/opt/local/sbin/nginx"
    static let nginxConf  = "/opt/local/etc/nginx/nginx.conf"
    static let nginxPort: UInt16 = 80

    static let mariadbConf = "/opt/local/etc/mariadb-10.11/my.cnf"
    static let mariadbBinCandidates = [ ... ]   // first executable one is used
    static let mariadbPort: UInt16 = 3306

    static let phpBin   = "/opt/local/bin/php"
    static let fpmBin   = "/opt/local/sbin/php-fpm84"   // "" to disable PHP-FPM
    static let fpmConf  = "/opt/local/etc/php84/php-fpm.conf"
    static let phpIni   = "/opt/local/etc/php84/php.ini"

    static let docRoot  = "/Users/you/Sites"            // your nginx `root`
    static let baseURL  = "http://localhost"
}
```

Find your own paths with:

```bash
which -a nginx php php-fpm
nginx -V 2>&1 | tr ' ' '\n' | grep -E 'conf-path|pid-path|prefix'
php --ini
grep -nE '^\s*(root|listen|fastcgi_pass)\b' /path/to/nginx.conf
```

For other layouts (a manual build under `/usr/local`, for example), change the paths and rebuild. PHP-FPM is expected on port `9000` and is started and stopped together with nginx. Set `fpmBin = ""` if you run PHP some other way.

## One-time setup: run as your user

ServerBar cannot start or stop root-owned processes. If you previously ran nginx with `sudo`, stop it and give your user the directories it writes to. Adjust paths to your install:

```bash
sudo pkill nginx
sudo chown -R "$USER":staff /opt/local/var/log/nginx /opt/local/var/run/nginx
```

Do the same for MariaDB's data, run and log directories if they are root-owned. Ports 80 and 3306 work for a normal user on current versions of macOS. If port 80 is refused on yours, change `listen` in nginx to a high port such as 8080 and update `nginxPort` and `baseURL` to match.

A fresh MariaDB install needs its data directory initialised once (for example with `mariadb-install-db`) before the first start.

## How it works

| Action | What ServerBar does |
| --- | --- |
| Status light | Connects to `127.0.0.1:<port>`; refreshed each time the menu opens |
| Start nginx | Launches PHP-FPM in the foreground (`--nodaemonize`) as a child process if port 9000 is closed, then runs `nginx -c <conf>` |
| Stop nginx | `nginx -s stop`; if the port is still open after a few seconds, terminates whatever is listening on it. Then stops PHP-FPM |
| Start MariaDB | Launches `mariadbd --defaults-file=<conf>` as a child process and waits for the port |
| Stop MariaDB | `SIGTERM` to the child (or pid file), with a fallback to the port listener |

Because Stop falls back to terminating the listener on the port, it will also stop an instance you started by hand. It will stop *anything* listening on ports 80, 9000 or 3306, so don't point it at ports used by something else.

## Troubleshooting

ServerBar writes logs to `~/Library/Application Support/ServerBar/`:

| File | Contents |
| --- | --- |
| `serverbar.log` | Every command the app ran and its exit status |
| `mariadb.log` | MariaDB's stdout/stderr |
| `php-fpm.log` | PHP-FPM's stdout/stderr |
| `exec-*.log` | Output of the last run of each short-lived command |

Common problems:

- **Light stays red after Start:** read the alert, then the logs above, then `error.log` in your nginx log directory.
- **`Permission denied` on a log or pid file:** a directory or file is still owned by root. Re-run the `chown` step above.
- **`Address already in use`:** something else holds the port. Find it with `lsof -nP -iTCP:80 -sTCP:LISTEN`.
- **No menu bar icon:** run `./ServerBar.app/Contents/MacOS/ServerBar` in a terminal to see any error. Make sure `main.swift` is saved and non-empty before building.
- **App won't open (`Killed: 9`):** sign it ad hoc: `codesign --force --sign - ServerBar.app && xattr -cr ServerBar.app`.
- **PHP shows connection refused:** PHP-FPM isn't listening on `127.0.0.1:9000`. Check `listen =` in `php-fpm.conf` or `php-fpm.d/*.conf`.

## Custom app icon

macOS needs an `.icns` file. From a square 1024×1024 PNG:

```bash
mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s icon-1024.png --out AppIcon.iconset/icon_${s}x${s}.png > /dev/null
  sips -z $((s*2)) $((s*2)) icon-1024.png --out AppIcon.iconset/icon_${s}x${s}@2x.png > /dev/null
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
```

Rebuild with `./build.sh`. If Finder still shows the generic icon, copy the app to `/Applications` and run `killall Dock Finder`. The menu bar itself uses the `server.rack` SF Symbol.

## Limitations

- The app is not sandboxed and not notarised. It is intended for local development on your own machine.
- Only one nginx/PHP-FPM/MariaDB set is managed, with ports and paths fixed at build time.
- The nginx pid path used for the stop fallback is set in the source and should match your build.
- Status is port-based, not process-based, so a different program holding a port shows as "running".

## License

Add the license of your choice (MIT is a common default).