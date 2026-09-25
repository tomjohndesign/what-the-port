import AppKit
import Combine
import Foundation

/// Restores the terminal however the process exits.
private var activeScreen: TerminalScreen?

/// The `wtp` terminal UI: the popover's server list, Clean up and server
/// details, driven by the same scanner as the menu bar app.
@MainActor
final class TerminalApp {
    private enum Page: Equatable {
        case servers
        case detail(Int)
        case help
    }

    private enum Action {
        case select(Int)
        case back
        case toggleInfo
        case toggleProcesses
        case toggleCPU
        case menuItem(Int)
        case key(InputEvent)
    }

    /// One thing you can do to a server. The same list drives the Actions
    /// menu, the single-key shortcuts and the footer.
    private struct ServerAction {
        let label: String
        let key: String?
        var isEnabled = true
        var isDestructive = false
        let run: () -> Void
    }

    /// Rows of content plus the clickable areas within them.
    private struct Block {
        var lines: [Line] = []
        var targets: [(line: Int, columns: Range<Int>, action: Action)] = []

        mutating func add(_ line: Line, action: Action? = nil) {
            if let action { targets.append((lines.count, 0..<Int.max, action)) }
            lines.append(line)
        }
    }

    private let screen = TerminalScreen()
    private let monitor = ServerMonitor()
    private var palette: TerminalPalette!
    private var subscriptions = Set<AnyCancellable>()
    private var sources: [DispatchSourceProtocol] = []
    private var ticker: Timer?
    private var renderScheduled = false

    private var page: Page = .servers
    private var pageBeforeHelp: Page = .servers
    private var selectedPort: Int?
    private var selectedIndex = 0
    private var listOffset = 0
    private var detailOffset = 0
    private var helpOffset = 0
    private var isCleaning = false
    private var selection = Set<Int>()
    private var confirmingStop: Int?
    /// The Actions menu: which server it's for and the highlighted item.
    private var menu: (port: Int, index: Int)?
    private var toast: (text: String, isError: Bool, until: Date)?
    private var cpuShowsAll = UserDefaults.standard.bool(forKey: "servers.cpuShowsAll")
    private var infoExpanded = UserDefaults.standard.bool(forKey: "detail.infoExpanded")
    private var processesExpanded = UserDefaults.standard.bool(forKey: "detail.processesExpanded")
    private var targets: [(row: Int, columns: Range<Int>, action: Action)] = []

    static func run() -> Never {
        let app = TerminalApp()
        app.start()
        RunLoop.main.run()
        exit(0)
    }

    private func start() {
        monitor.handlesAlerts = false
        activeScreen = screen
        atexit { activeScreen?.leave() }
        screen.enter()
        screen.queryColors()
        palette = TerminalPalette(screen: screen)

        monitor.scanNow()
        monitor.start()
        selectedPort = monitor.servers.first?.port
        monitor.objectWillChange.sink { [weak self] _ in self?.setNeedsRender() }.store(in: &subscriptions)
        monitor.github.objectWillChange.sink { [weak self] _ in self?.setNeedsRender() }.store(in: &subscriptions)

        let input = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        input.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = read(STDIN_FILENO, &buffer, buffer.count)
            MainActor.assumeIsolated {
                guard count > 0 else {
                    if count == 0 { self?.quit() }
                    return
                }
                self?.handle(TerminalScreen.parse(Array(buffer[0..<count])))
            }
        }
        input.resume()
        sources.append(input)

        for number in [SIGWINCH, SIGTERM, SIGHUP, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    if number == SIGWINCH {
                        self?.screen.updateSize()
                        self?.render()
                    } else {
                        self?.quit()
                    }
                }
            }
            source.resume()
            sources.append(source)
        }

        // Uptimes, idle times and messages change without a new scan.
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.setNeedsRender() }
        }
        render()
    }

    private func quit() -> Never {
        screen.leave()
        exit(0)
    }

    private func suspend() {
        screen.leave()
        signal(SIGTSTP, SIG_DFL)
        kill(getpid(), SIGTSTP)
        // Resumed with `fg`.
        screen.enter()
        screen.updateSize()
        render()
    }

    private func setNeedsRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    // MARK: - Input

    private func handle(_ events: [InputEvent]) {
        for event in events { handle(event) }
        render()
    }

    private func handle(_ event: InputEvent) {
        switch event {
        case .control("c"): quit()
        case .control("z"): suspend(); return
        case .control("l"): screen.invalidate(); return
        default: break
        }

        if let port = confirmingStop {
            confirmingStop = nil
            switch event {
            case .character("y"), .character("Y"), .character("s"), .enter:
                if let server = monitor.server(port: port) { stop(server) }
            default:
                break
            }
            return
        }

        if case .click(let x, let y) = event {
            let target = targets.last { $0.row == y && $0.columns.contains(x) }
            switch target?.action {
            case .menuItem?, .key?:
                break
            default:
                // Clicking outside the menu closes it.
                if menu != nil {
                    menu = nil
                    return
                }
            }
            if let target { perform(target.action) }
            return
        }

        if menu != nil {
            handleMenu(event)
            return
        }

        switch page {
        case .help:
            switch event {
            case .up, .character("k"), .scrollUp: helpOffset -= 1
            case .down, .character("j"), .scrollDown: helpOffset += 1
            case .pageUp: helpOffset -= max(screen.rows - 8, 1)
            case .pageDown, .character(" "): helpOffset += max(screen.rows - 8, 1)
            default: page = pageBeforeHelp
            }
        case .servers:
            handleServers(event)
        case .detail(let port):
            guard let server = monitor.server(port: port) else {
                page = .servers
                return
            }
            handleDetail(event, server: server)
        }
    }

    private func perform(_ action: Action) {
        switch action {
        case .select(let port):
            if selectedPort == port {
                if isCleaning { toggle(port) } else { openDetail(port) }
            } else {
                selectedPort = port
                if isCleaning { toggle(port) }
            }
        case .back:
            handle(.escape)
        case .toggleInfo:
            infoExpanded.toggle()
        case .toggleProcesses:
            processesExpanded.toggle()
        case .toggleCPU:
            cpuShowsAll.toggle()
        case .menuItem(let index):
            guard let port = menu?.port, let server = monitor.server(port: port) else { return }
            let items = actions(for: server)
            if items.indices.contains(index), items[index].isEnabled { run(items[index]) }
        case .key(let event):
            handle(event)
        }
    }

    private func handleServers(_ event: InputEvent) {
        let servers = visibleServers
        let server = servers.first { $0.port == selectedPort }
        switch event {
        case .up, .character("k"), .scrollUp: moveSelection(-1)
        case .down, .character("j"), .scrollDown: moveSelection(1)
        case .home, .character("g"): selectedPort = servers.first?.port
        case .end, .character("G"): selectedPort = servers.last?.port
        case .pageUp: moveSelection(-max(listCapacity, 1))
        case .pageDown: moveSelection(max(listCapacity, 1))
        case .character("?"): showHelp()
        case .character("q"), .escape:
            // Escape steps back a level: out of Clean up, then out of wtp.
            if isCleaning { setCleaning(false) } else { quit() }
        default:
            if isCleaning {
                handleCleaning(event)
                return
            }
            switch event {
            case .enter, .right, .character("l"):
                if let server { openDetail(server.port) }
            case .character(" "), .character("."):
                if let server { openMenu(server) }
            case .character("c"):
                if !monitor.servers.isEmpty { setCleaning(true) }
            case .character("t"):
                cpuShowsAll.toggle()
            default:
                if let server { runShortcut(event, server: server) }
            }
        }
    }

    private func handleCleaning(_ event: InputEvent) {
        switch event {
        case .character(" "), .character("x"):
            if let port = selectedPort { toggle(port) }
        case .character("a"):
            let ports = Set(visibleServers.map(\.port))
            selection = selection == ports ? [] : ports
        case .enter:
            let servers = visibleServers.filter { selection.contains($0.port) }
            guard !servers.isEmpty else { return }
            let memory = servers.reduce(0) { $0 + $1.memory }
            servers.forEach { monitor.stop($0) }
            setCleaning(false)
            show("Stopping \(servers.count) \(servers.count == 1 ? "server" : "servers") · freeing \(Format.bytesString(memory))")
        case .escape, .character("c"):
            setCleaning(false)
        default:
            break
        }
    }

    private func handleDetail(_ event: InputEvent, server: Server) {
        switch event {
        case .escape, .left, .backspace, .character("h"), .character("q"):
            page = .servers
        case .up, .character("k"), .scrollUp: detailOffset -= 1
        case .down, .character("j"), .scrollDown: detailOffset += 1
        case .pageUp: detailOffset -= max(screen.rows - 8, 1)
        case .pageDown: detailOffset += max(screen.rows - 8, 1)
        case .home, .character("g"): detailOffset = 0
        case .end, .character("G"): detailOffset = .max
        case .tab, .backTab:
            let servers = monitor.servers
            guard let index = servers.firstIndex(where: { $0.port == server.port }), servers.count > 1 else { return }
            let next = servers[(index + (event == .tab ? 1 : servers.count - 1)) % servers.count]
            openDetail(next.port)
        case .enter: openInBrowser(server)
        case .character(" "), .character("."): openMenu(server)
        case .character("i"): infoExpanded.toggle()
        case .character("p"): processesExpanded.toggle()
        case .character("?"): showHelp()
        default: runShortcut(event, server: server)
        }
    }

    // MARK: - Server actions

    private func actions(for server: Server) -> [ServerAction] {
        let github = monitor.github.result(for: server)
        let root = server.cwdExists ? server.project.root ?? server.cwd : nil
        var items = [ServerAction(label: "Open localhost:\(server.port)", key: "o") { [unowned self] in openInBrowser(server) }]
        if let preview = github?.preview {
            let label = preview.state == .building ? "Vercel preview · building" : preview.state == .failed ? "Vercel preview · failed" : "Vercel preview"
            items.append(ServerAction(label: label, key: "v") { NSWorkspace.shared.open(preview.url) })
        }
        if let pr = github?.pullRequest {
            items.append(ServerAction(label: "Pull request #\(pr.number)", key: "u") { NSWorkspace.shared.open(pr.url) })
        }
        if let agent = server.agent {
            items.append(ServerAction(label: "Resume \(agent.kind.rawValue) in \(TerminalLauncher.current.name)", key: "a") { [unowned self] in
                SessionLauncher.resume(agent, fallbackDirectory: server.cwd)
                show("Resuming in \(TerminalLauncher.current.name)")
            })
        }
        items.append(ServerAction(label: server.agent.map { "Restart · runs outside \($0.kind.rawValue)" } ?? "Restart", key: "r",
                                  isEnabled: server.launch != nil && server.cwdExists) { [unowned self] in restart(server) })
        let count = server.processes.count
        items.append(ServerAction(label: "Stop \(count) \(count == 1 ? "process" : "processes")", key: "s", isDestructive: true) { [unowned self] in
            confirmingStop = server.port
        })
        if let root {
            items.append(ServerAction(label: "Open in editor", key: "e") { EditorLauncher.open(root) })
            items.append(ServerAction(label: "Reveal in Finder", key: "f") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: root) })
        }
        if let transcript = server.agent?.transcript {
            items.append(ServerAction(label: "Show transcript", key: nil) { NSWorkspace.shared.selectFile(transcript.path, inFileViewerRootedAtPath: "") })
        }
        items.append(ServerAction(label: "Copy URL", key: "y") { [unowned self] in copy(server.url.absoluteString, label: "URL") })
        if let command = server.command {
            items.append(ServerAction(label: "Copy command", key: "Y") { [unowned self] in copy(command, label: "command") })
        }
        if let agent = server.agent {
            items.append(ServerAction(label: "Copy session ID", key: nil) { [unowned self] in copy(agent.id, label: "session ID") })
        }
        return items
    }

    private func runShortcut(_ event: InputEvent, server: Server) {
        guard case .character(let character) = event,
              let item = actions(for: server).first(where: { $0.key == String(character) }) else { return }
        if item.isEnabled {
            run(item)
        } else if item.key == "r" {
            show("Can’t restart :\(server.port): its command or folder is gone", isError: true)
        }
    }

    private func run(_ item: ServerAction) {
        menu = nil
        item.run()
    }

    private func openMenu(_ server: Server) {
        menu = (server.port, 0)
    }

    private func handleMenu(_ event: InputEvent) {
        guard let current = menu, let server = monitor.server(port: current.port) else {
            menu = nil
            return
        }
        let items = actions(for: server)
        func step(_ delta: Int) {
            var index = current.index
            for _ in items.indices {
                index = (index + delta + items.count) % items.count
                if items[index].isEnabled { break }
            }
            menu = (current.port, index)
        }
        switch event {
        case .up, .character("k"), .scrollUp, .backTab: step(-1)
        case .down, .character("j"), .scrollDown, .tab: step(1)
        case .home: menu = (current.port, 0)
        case .end: menu = (current.port, items.count - 1)
        case .enter, .right:
            let index = min(current.index, items.count - 1)
            if items[index].isEnabled { run(items[index]) }
        case .character(let character) where items.contains(where: { $0.key == String(character) }):
            runShortcut(event, server: server)
            menu = nil
        default:
            // Escape, space, q or anything else closes the menu.
            menu = nil
        }
    }

    // MARK: - Actions

    private var visibleServers: [Server] {
        isCleaning ? monitor.servers.filter { !$0.isProtected } : monitor.servers
    }

    private func moveSelection(_ delta: Int) {
        let servers = visibleServers
        guard !servers.isEmpty else { return }
        let index = servers.firstIndex { $0.port == selectedPort } ?? 0
        selectedPort = servers[min(max(index + delta, 0), servers.count - 1)].port
    }

    private func openDetail(_ port: Int) {
        guard let server = monitor.server(port: port) else { return }
        selectedPort = port
        detailOffset = 0
        page = .detail(port)
        monitor.github.refresh(server, maxAge: 30)
    }

    private func showHelp() {
        pageBeforeHelp = page
        helpOffset = 0
        page = .help
    }

    private func setCleaning(_ cleaning: Bool) {
        isCleaning = cleaning
        selection = cleaning
            ? Set(monitor.cleanUpCandidates.filter { !$0.reason.isLeak }.map(\.server.port))
            : []
        if cleaning, !visibleServers.contains(where: { $0.port == selectedPort }) {
            selectedPort = visibleServers.first?.port
        }
    }

    private func toggle(_ port: Int) {
        if selection.contains(port) { selection.remove(port) } else { selection.insert(port) }
    }

    private func stop(_ server: Server) {
        monitor.stop(server)
        if page == .detail(server.port) { page = .servers }
        show("Stopping \(server.project.name) :\(server.port)")
    }

    private func restart(_ server: Server) {
        guard server.launch != nil, server.cwdExists else {
            show("Can’t restart :\(server.port): its command or folder is gone", isError: true)
            return
        }
        monitor.restart(server)
        if let agent = server.agent {
            show("Restarting :\(server.port) outside the \(agent.kind.rawValue) session")
        } else {
            show("Restarting :\(server.port)")
        }
    }

    private func openInBrowser(_ server: Server) {
        NSWorkspace.shared.open(server.url)
        show("Opened localhost:\(server.port)")
    }

    private func copy(_ string: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        show("Copied \(label)")
    }

    private func show(_ text: String, isError: Bool = false) {
        toast = (text, isError, Date().addingTimeInterval(2.5))
    }

    // MARK: - Rendering

    private var width: Int { min(screen.columns, 100) }
    /// Columns for content inside the side insets.
    private var inner: Int { max(width - 4, 10) }
    private var listCapacity = 0

    private func render() {
        renderScheduled = false
        if let toast, toast.until < Date() { self.toast = nil }
        if let port = menu?.port, monitor.server(port: port) == nil { menu = nil }
        targets = []
        syncSelection()

        let top: Block, body: Block, footer: Block
        var offset = 0
        switch page {
        case .servers:
            (top, body, footer) = (serversTop(), serversBody(), serversFooter())
        case .detail(let port):
            if let server = monitor.server(port: port) {
                (top, body, footer) = (detailTop(server), detailBody(server), detailFooter(server))
                offset = detailOffset
            } else {
                page = .servers
                (top, body, footer) = (serversTop(), serversBody(), serversFooter())
            }
        case .help:
            (top, body, footer) = (helpTop(), helpBody(), hintsFooter([("↑ ↓", "Scroll"), ("esc", "Back")]))
            offset = helpOffset
        }

        // Content sits at the top like the popover; long lists scroll.
        let available = max(screen.rows - top.lines.count - footer.lines.count, 0)
        if case .servers = page {
            offset = listOffset(body: body, available: available)
        } else {
            offset = min(max(offset, 0), max(body.lines.count - available, 0))
            if case .detail = page { detailOffset = offset } else { helpOffset = offset }
        }
        let visible = Array(body.lines.dropFirst(offset).prefix(available))

        var lines = top.lines + visible
        var frameTargets = top.targets.map { (row: $0.line, columns: $0.columns, action: $0.action) }
        for target in body.targets where target.line >= offset && target.line < offset + available {
            frameTargets.append((top.lines.count + target.line - offset, target.columns, target.action))
        }
        let footerRow = lines.count
        lines += footer.lines
        frameTargets += footer.targets.map { (footerRow + $0.line, $0.columns, $0.action) }
        targets = frameTargets
        screen.draw(lines)
    }

    /// When the selected server goes away, selects the one that took its place.
    private func syncSelection() {
        let servers = visibleServers
        if let index = servers.firstIndex(where: { $0.port == selectedPort }) {
            selectedIndex = index
        } else {
            selectedPort = servers.isEmpty ? nil : servers[min(selectedIndex, servers.count - 1)].port
        }
    }

    /// Keeps the selected row in view.
    private func listOffset(body: Block, available: Int) -> Int {
        listCapacity = max((available - 1) / 3, 1)
        guard body.lines.count > available else {
            listOffset = 0
            return 0
        }
        let servers = visibleServers
        if let index = servers.firstIndex(where: { $0.port == selectedPort }) {
            // One blank line, then two lines per row with a blank line between rows.
            let rowTop = 1 + index * 3
            if rowTop < listOffset { listOffset = rowTop - (index == 0 ? 1 : 0) }
            if rowTop + 2 > listOffset + available { listOffset = rowTop + 2 - available + (index == servers.count - 1 ? 1 : 0) }
        }
        listOffset = min(max(listOffset, 0), body.lines.count - available)
        return listOffset
    }

    /// Content lines start two columns in, like the popover's 16-point inset.
    private func padded(_ line: Line) -> Line {
        [Span("  ")] + line.fitted(to: inner) + [Span("  ")]
    }

    private func divider() -> Line {
        [Span(String(repeating: "─", count: width), palette.track)]
    }

    private func centered(_ line: Line) -> Line {
        let lineWidth = min(line.width, inner)
        let left = (inner - lineWidth) / 2
        return padded([Span(String(repeating: " ", count: left))] + line.truncated(to: inner))
    }

    // MARK: Servers

    private func serversTop() -> Block {
        var block = Block()
        block.add(centered([Span(isCleaning ? "Clean up" : "Servers", palette.text1.bold())]))
        block.add([])

        let amount: (number: String, unit: String)
        let selected = visibleServers.filter { selection.contains($0.port) }
        if isCleaning {
            amount = Format.total(selected.reduce(0) { $0 + $1.memory })
        } else {
            amount = Format.total(monitor.totalMemory)
        }
        let left: Line = [Span(amount.number, palette.text1.bold()), Span(" " + amount.unit, palette.text3)]
        let right: Line
        if isCleaning {
            right = [Span(selection.isEmpty ? "Pick servers to stop" : "freed by stopping \(selected.count)", palette.text2)]
        } else {
            let percent = cpuShowsAll ? (monitor.systemCPU ?? 0) : monitor.serversShareOfCPU
            right = [Span(cpuShowsAll ? "CPU (all)" : "CPU (servers)", palette.text3), Span("  " + Format.percent(percent), palette.text2)]
        }
        let cpuStart = 2 + inner - right.width
        block.add(padded(Line.split(left, right, width: inner)))
        if !isCleaning { block.targets.append((block.lines.count - 1, cpuStart..<(cpuStart + right.width), .toggleCPU)) }

        let bar = memoryBar()
        block.add(padded(bar.line))
        for (range, port) in bar.segments {
            block.targets.append((block.lines.count - 1, (range.lowerBound + 2)..<(range.upperBound + 2), .select(port)))
        }
        block.add(padded(memoryLegend()))
        block.add(divider())
        return block
    }

    /// Servers as raised blocks in their port colors, other apps on a lower
    /// baseline, free memory as the track. The selected row's server stands
    /// taller and the rest dim, like hovering a row in the app.
    private func memoryBar() -> (line: Line, segments: [(Range<Int>, Int)]) {
        let servers = visibleServers
        let breakdown = MemoryBreakdown(monitor: monitor)
        let others = breakdown.topApps.reduce(0) { $0 + $1.memory } + breakdown.everythingElse
        let filled = breakdown.devServers + others
        let capacity = Double(max(breakdown.total ?? filled, filled, 1))
        let columns = inner

        var serverColumns = servers.map { max(Int((Double($0.memory) / capacity * Double(columns)).rounded()), 1) }
        var otherColumns = Int((Double(others) / capacity * Double(columns)).rounded())
        while serverColumns.reduce(0, +) + otherColumns > columns {
            if otherColumns > 0 {
                otherColumns -= 1
            } else if let index = serverColumns.indices.max(by: { serverColumns[$0] < serverColumns[$1] }), serverColumns[index] > 1 {
                serverColumns[index] -= 1
            } else {
                break
            }
        }

        var line: Line = []
        var segments: [(Range<Int>, Int)] = []
        for (server, count) in zip(servers, serverColumns) {
            let isFocused = server.port == selectedPort
            var style = palette.port(monitor.colorIndex(for: server.port))
            let isDimmed = isCleaning ? !selection.contains(server.port) && !isFocused : !isFocused
            if isDimmed { style = palette.faded(style, 0.35) }
            segments.append((line.width..<(line.width + count), server.port))
            line.append(Span(String(repeating: isFocused ? "█" : "▅", count: count), style))
        }
        line.append(Span(String(repeating: "▂", count: otherColumns), palette.faint))
        let free = columns - line.width
        if free > 0 { line.append(Span(String(repeating: "▂", count: free), palette.track)) }
        return (line, segments)
    }

    private func memoryLegend() -> Line {
        let breakdown = MemoryBreakdown(monitor: monitor)
        func amount(_ bytes: UInt64) -> String {
            let value = Format.total(bytes)
            return "\(value.number) \(value.unit)"
        }
        var line: Line = [
            Span("▅ ", palette.text1), Span("Servers ", palette.text2), Span(amount(breakdown.devServers), palette.text3),
            Span("   ▂ ", palette.faint), Span("Other apps ", palette.text2), Span(amount(breakdown.otherApps), palette.text3),
        ]
        if let total = breakdown.total {
            line += [Span("   ▂ ", palette.track), Span("Free ", palette.text2),
                     Span("\(Format.total(breakdown.free).number) of \(amount(total))", palette.text3)]
        }
        return line
    }

    private func serversBody() -> Block {
        var block = Block()
        let servers = visibleServers
        guard !servers.isEmpty else {
            block.add([])
            for _ in 0..<5 {
                block.add(centered([Span("● ● ● ● ●", palette.faint)]))
            }
            block.add([])
            block.add(centered([Span(monitor.hasScanned ? "Nothing listening" : "Scanning…", palette.text2)]))
            block.add(centered([Span("Dev servers on ports \(monitor.minPort)–\(monitor.maxPort) show up here.", palette.text3)]))
            block.add([])
            return block
        }
        block.add([])
        for (index, server) in servers.enumerated() {
            if index > 0 { block.add([]) }
            for line in serverRow(server, isSelected: server.port == selectedPort) {
                block.add(line, action: .select(server.port))
            }
        }
        block.add([])
        return block
    }

    private func serverRow(_ server: Server, isSelected: Bool) -> [Line] {
        let status = monitor.status(of: server)
        let attention = status == .attention
        let portStyle = palette.port(monitor.colorIndex(for: server.port))
        let reason = isCleaning ? monitor.cleanUpReason(for: server) : nil
        let content = inner

        var first: Line = []
        var second: Line = []
        if isCleaning {
            let isOn = selection.contains(server.port)
            first += [Span(isOn ? "[✓]" : "[ ]", isOn ? palette.text1.bold() : palette.text3), Span(" ")]
            second += [Span("    ")]
        }
        first += portLabel(server.port, status: status, style: portStyle)
        let indent = 7 - (1 + String(server.port).count)
        first.append(Span(String(repeating: " ", count: max(indent, 1))))
        second.append(Span("       "))

        let name = (server.project.branch ?? server.project.name).replacingOccurrences(of: "-", with: " ")
        first.append(Span(name, palette.text1.bold()))

        let memoryStyle = attention ? palette.amber : palette.text1
        let right: Line = [
            Span(sparkline(server.history.map { Double($0.memory) }, columns: 8), attention ? palette.amber : palette.faded(palette.text1, 0.7)),
            Span(padLeft(Format.bytesString(server.memory), 9), memoryStyle),
        ]
        let lineOne = Line.split(first, right, width: content)
        let contextWidth = content - second.width
        let lineTwo = second + context(for: server, status: status, reason: reason, width: contextWidth)

        var lines = [lineOne, lineTwo.fitted(to: content)]
        if !server.cwdExists, status == .idle { lines = lines.map { palette.faded($0, 0.55) } }
        let highlight = isSelected ? palette.highlight : nil
        return lines.enumerated().map { index, line in
            // Without a highlight color, a marker shows the selection.
            let marker = isSelected && highlight == nil && index == 0 ? "›" : " "
            return [Span(" ")] + ([Span(marker, palette.text1.bold())] + line + [Span(" ")]).background(highlight) + [Span(" ")]
        }
    }

    private func portLabel(_ port: Int, status: ServerStatus, style: TextStyle) -> Line {
        let colon: TextStyle
        switch status {
        case .running: colon = style
        case .attention: colon = style.bold()
        case .idle: colon = palette.faded(style, 0.45)
        }
        return [Span(":", colon), Span(String(port), style.bold())]
    }

    private func context(for server: Server, status: ServerStatus, reason: CleanUpReason?, width: Int) -> Line {
        if let reason {
            return [Span(reason.label, reason.isLeak ? palette.amber : palette.text2)]
        }
        if status == .attention, server.isLeaking() {
            let span = server.history.last.map { last in server.history.first.map { last.time.timeIntervalSince($0.time) } ?? 0 } ?? 0
            return [Span("+\(Format.bytesString(UInt64(server.memoryGrowth))) in \(Format.duration(span))", palette.amber)]
        }
        if status == .attention {
            return [Span("Over \(MemoryChart.trim(Double(monitor.alertThreshold) / Format.gigabyte)) GB", palette.amber)]
        }
        var line: Line = []
        if let agent = server.agent { line += [Span(agentGlyph(agent.kind), palette.text2), Span(" ")] }
        let text = contextText(server)
        if server.cwdExists, server.project.branch != nil {
            let suffix = " · " + text
            let available = max(width - line.width - TextWidth.of(suffix), 1)
            let project = server.project.name.replacingOccurrences(of: "-", with: " ")
            line.append(Span([Span(project)].truncated(to: available).map(\.text).joined(), palette.text2))
            line.append(Span(suffix, palette.text2))
        } else {
            line.append(Span(text, palette.text2))
        }
        return line
    }

    /// Uptime or idle time, prefixed with the location when there's no branch.
    private func contextText(_ server: Server) -> String {
        if !server.cwdExists { return "Worktree deleted · idle \(Format.shortDuration(server.idleFor))" }
        let time = server.idleFor > 60 * 60
            ? "idle \(Format.shortDuration(server.idleFor))"
            : server.uptime.map { "up \(Format.shortDuration($0))" } ?? ""
        if server.project.branch != nil { return time }
        return [server.locationLabel, time].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func agentGlyph(_ kind: AgentKind) -> String {
        switch kind {
        case .claudeCode: return "✳"
        case .codex: return ">_"
        }
    }

    private func serversFooter() -> Block {
        if let footer = messageFooter() { return footer }
        if isCleaning {
            let selected = visibleServers.filter { selection.contains($0.port) }
            let stopLabel = selected.isEmpty
                ? "Stop servers"
                : "Stop \(selected.count) \(selected.count == 1 ? "server" : "servers") · free \(Format.bytesString(selected.reduce(0) { $0 + $1.memory }))"
            return hintsFooter([("space", "Select"), ("a", "All"), ("⏎", stopLabel), ("esc", "Cancel")],
                               destructive: selected.isEmpty ? nil : "⏎", disabled: selected.isEmpty ? "⏎" : nil)
        }
        guard !monitor.servers.isEmpty else { return hintsFooter([("?", "Keys"), ("q", "Quit")]) }
        let count = monitor.suggestedCleanUpCount
        return hintsFooter([("⏎", "Details"), ("space", "Actions"), ("o", "Open"), ("s", "Stop"),
                            ("c", count > 0 ? "Clean up \(count)" : "Clean up"), ("?", "Keys"), ("q", "Quit")])
    }

    // MARK: Details

    private func detailTop(_ server: Server) -> Block {
        var block = Block()
        let name = TextWidth.prefix(server.project.name, width: inner - 4)
        let left = max((inner - TextWidth.of(name)) / 2, 2)
        block.add(padded([Span("‹", palette.text2), Span(String(repeating: " ", count: left - 1)), Span(name, palette.text1.bold())]))
        block.targets.append((0, 0..<4, .back))
        block.add([])

        let status = monitor.status(of: server)
        let port = portLabel(server.port, status: status, style: palette.port(monitor.colorIndex(for: server.port)))
        let running: Line = server.uptime.map { [Span("Running for \(Format.duration($0))", palette.text3)] } ?? []
        block.add(padded(Line.split(port, running, width: inner)))
        block.add(divider())
        return block
    }

    private func detailBody(_ server: Server) -> Block {
        var block = Block()
        let labelWidth = 13
        let valueWidth = inner - labelWidth
        func row(_ label: String, _ value: Line, middle: Bool = false) -> Line {
            var value = value
            if middle, value.count == 1, value[0].width > valueWidth {
                value[0].text = TextWidth.middle(value[0].text, width: valueWidth)
            }
            return padded([Span(label.padding(toLength: labelWidth, withPad: " ", startingAt: 0), palette.text3)] + value.truncated(to: valueWidth))
        }

        // Info: the essentials, then the rest behind "N more".
        let github = monitor.github.result(for: server)
        var primary: [Line] = []
        if let agent = server.agent {
            primary.append(row("Session", [Span(agentGlyph(agent.kind) + " ", palette.text1), Span(agent.title ?? agent.kind.rawValue, palette.text1), Span(" ↗", palette.text2)]))
        }
        if let branch = server.project.branch {
            primary.append(row("Branch", [Span(branch, palette.text1)]))
        }
        let folder = folderText(server)
        let folderIsPrimary = primary.count < 2
        if folderIsPrimary, let folder {
            primary.append(row("Folder", [Span(folder, palette.text2)], middle: true))
        }

        var secondary: [Line] = []
        if let workspace = server.conductorWorkspace {
            secondary.append(row("Workspace", [Span("Conductor · \(workspace)", palette.text2)]))
        }
        // Folder moves here when Session and Branch fill the first two rows.
        if !folderIsPrimary, let folder {
            secondary.append(row("Folder", [Span(folder, palette.text2)], middle: true))
        }
        if let framework = server.project.framework {
            secondary.append(row("Framework", [Span(framework, palette.text2)]))
        }
        if let command = server.command {
            secondary.append(row("Command", [Span(command, palette.text2)], middle: true))
        }
        if let started = server.startedAt {
            secondary.append(row("Started", [Span(Format.time(started), palette.text2)]))
        }
        if let pr = github?.pullRequest {
            secondary.append(row("Pull request", [Span("#\(pr.number) ", palette.text1), Span(pr.title, palette.text2), Span(" \(pr.state)", palette.text3)]))
        }
        if let agent = server.agent {
            secondary.append(row("Session ID", [Span(agent.id, palette.text2)], middle: true))
        }
        if !server.addresses.isEmpty {
            secondary.append(row("Address", [Span(server.addresses.joined(separator: " · "), palette.text2)], middle: true))
        }

        block.add([])
        primary.forEach { block.add($0) }
        if infoExpanded { secondary.forEach { block.add($0) } }
        if !secondary.isEmpty {
            let label = infoExpanded ? "Less ▴" : "\(secondary.count) more ▾"
            block.add(padded([Span(String(repeating: " ", count: labelWidth)), Span(label, palette.text3), Span("   i", palette.text2.bold())]))
            block.targets.append((block.lines.count - 1, (2 + labelWidth)..<(2 + labelWidth + TextWidth.of(label) + 4), .toggleInfo))
        }
        block.add([])
        block.add(divider())

        // Charts
        block.add([])
        let hasHistory = server.history.count > 1
        block.add(padded(Line.split([Span("Memory", palette.text2), Span("  " + Format.bytesString(server.memory), palette.text1.bold())],
                                    [Span("10 min", palette.text3)], width: inner)))
        memoryChart(server).forEach { block.add(padded($0)) }
        block.add([])
        block.add(padded([Span("CPU", palette.text2), Span("  " + Format.percent(server.cpu), palette.text1.bold())]))
        cpuChart(server).forEach { block.add(padded($0)) }
        if !hasHistory {
            block.add(padded([Span("History fills in while wtp runs.", palette.text3)]))
        }
        block.add([])
        block.add(divider())

        // Processes
        block.add([])
        let summary = "\(server.processes.count) · \(Format.bytesString(server.memory))"
        block.add(padded(Line.split([Span("Processes ", palette.text2), Span(processesExpanded ? "▾" : "▸", palette.text3), Span("   p", palette.text2.bold())],
                                    [Span(summary, palette.text2)], width: inner)), action: .toggleProcesses)
        if processesExpanded {
            let largest = max(server.processes.map(\.memory).max() ?? 1, 1)
            for process in server.processes {
                let tree = (process.depth > 0 ? String(repeating: "  ", count: process.depth - 1) + "└ " : "") + process.name
                let isListener = process.pid == server.pid
                let filled = max(Int((8 * Double(process.memory) / Double(largest)).rounded()), 1)
                let right: Line = [
                    Span(String(process.pid).padding(toLength: 8, withPad: " ", startingAt: 0), palette.text3),
                    Span(String(repeating: "━", count: filled), isListener ? palette.text1 : palette.text2),
                    Span(String(repeating: "─", count: 8 - filled), palette.track),
                    Span(padLeft(Format.bytesString(process.memory), 10), palette.text1),
                ]
                block.add(padded(Line.split([Span(tree, isListener ? palette.text1 : palette.text2)], right, width: inner)))
            }
        }
        block.add([])
        return block
    }

    private func folderText(_ server: Server) -> String? {
        guard let path = server.cwd else { return nil }
        let abbreviated = (path as NSString).abbreviatingWithTildeInPath
        let parts = abbreviated.split(separator: "/")
        guard parts.count > 3 else { return abbreviated }
        return "\(parts.first!)/…/" + parts.suffix(2).joined(separator: "/")
    }

    private func detailFooter(_ server: Server) -> Block {
        if let footer = messageFooter() { return footer }
        return hintsFooter([("⏎", "Open localhost:\(server.port)"), ("space", "Actions"),
                            ("i", infoExpanded ? "Less info" : "More info"),
                            ("p", processesExpanded ? "Hide processes" : "Processes"), ("?", "Keys"), ("esc", "Back")])
    }

    // MARK: Charts

    /// Line chart over the last ten minutes, with the alert threshold dotted in amber.
    private func memoryChart(_ server: Server) -> [Line] {
        let threshold = Double(monitor.alertThreshold) / Format.gigabyte
        let values = server.history.map { (time: $0.time, gb: Double($0.memory) / Format.gigabyte) }
        let top = max(threshold, (values.map(\.gb).max() ?? 0) * 1.1)
        let thresholdLabel = "\(MemoryChart.trim(threshold)) GB"
        let gutter = TextWidth.of(thresholdLabel) + 1
        let rows = 4
        var canvas = BrailleCanvas(columns: inner - gutter - 1, rows: rows)
        func y(_ gb: Double) -> Int { Int(((1 - gb / max(top, 0.001)) * Double(canvas.dotHeight - 1)).rounded()) }
        canvas.plot(points(values.map { ($0.time, $0.gb) }, canvas: canvas, y: y))

        var marks = BrailleCanvas(columns: canvas.columns, rows: rows)
        let thresholdY = y(threshold)
        for x in stride(from: 0, to: marks.dotWidth, by: 2) { marks.set(x, thresholdY) }
        let thresholdRow = thresholdY / 4

        return (0..<rows).map { row in
            var label = ""
            var labelStyle = palette.text3
            if row == thresholdRow {
                label = thresholdLabel
                labelStyle = palette.faded(palette.amber, 0.85)
            } else if row == rows - 1 {
                label = "0"
            }
            var line: Line = [Span(padLeft(label, gutter - 1) + " ", labelStyle), Span("│", palette.track)]
            for column in 0..<canvas.columns {
                if !canvas.isEmpty(row: row, column: column) {
                    line.append(Span(String(canvas.character(row: row, column: column)), palette.text1))
                } else if !marks.isEmpty(row: row, column: column) {
                    line.append(Span(String(marks.character(row: row, column: column)), palette.faded(palette.amber, 0.6)))
                } else {
                    line.append(Span(" "))
                }
            }
            return line
        }
    }

    /// Bars over the last ten minutes, the latest one brightest.
    private func cpuChart(_ server: Server) -> [Line] {
        let rows = 4
        let gutter = 5
        let columns = inner - gutter - 1
        let start = Date().addingTimeInterval(-ScanEngine.historyWindow)
        var buckets = [[Double]](repeating: [], count: max(columns, 0))
        for sample in server.history {
            let fraction = sample.time.timeIntervalSince(start) / ScanEngine.historyWindow
            let index = min(max(Int(fraction * Double(columns)), 0), columns - 1)
            if index >= 0 { buckets[index].append(min(sample.cpu, 100)) }
        }
        let latest = buckets.lastIndex { !$0.isEmpty }
        let blocks: [Character] = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        return (0..<rows).map { row in
            let label = row == 0 ? "100%" : row == rows - 1 ? "0" : ""
            var line: Line = [Span(padLeft(label, gutter - 1) + " ", palette.text3), Span("│", palette.track)]
            for (index, bucket) in buckets.enumerated() {
                guard !bucket.isEmpty else {
                    line.append(Span(" "))
                    continue
                }
                let value = bucket.reduce(0, +) / Double(bucket.count)
                var eighths = Int((value / 100 * Double(rows * 8)).rounded())
                if value >= 1 { eighths = max(eighths, 1) }
                let fromBottom = rows - 1 - row
                let level = min(max(eighths - fromBottom * 8, 0), 8)
                let style = index == latest ? palette.faded(palette.text1, 0.85) : palette.faded(palette.text1, 0.32)
                line.append(Span(String(blocks[level]), style))
            }
            return line
        }
    }

    /// Positions timed values on a canvas spanning the last ten minutes.
    private func points(_ values: [(Date, Double)], canvas: BrailleCanvas, y: (Double) -> Int) -> [(x: Int, y: Int)] {
        let start = Date().addingTimeInterval(-ScanEngine.historyWindow)
        var byColumn: [Int: Double] = [:]
        for (time, value) in values {
            let fraction = time.timeIntervalSince(start) / ScanEngine.historyWindow
            let x = min(max(Int((fraction * Double(canvas.dotWidth - 1)).rounded()), 0), canvas.dotWidth - 1)
            byColumn[x] = value
        }
        return byColumn.keys.sorted().map { (x: $0, y: y(byColumn[$0]!)) }
    }

    /// The row sparkline: evenly spaced samples, scaled to their own range.
    private func sparkline(_ values: [Double], columns: Int) -> String {
        guard values.count > 1, let low = values.min(), let high = values.max() else {
            return String(repeating: "⠄", count: columns)
        }
        var canvas = BrailleCanvas(columns: columns, rows: 1)
        let range = max(high - low, high * 0.05, 1)
        let width = canvas.dotWidth - 1
        var byColumn: [Int: Double] = [:]
        for (index, value) in values.enumerated() {
            byColumn[Int((Double(index) / Double(values.count - 1) * Double(width)).rounded())] = value
        }
        let points = byColumn.keys.sorted().map { x -> (x: Int, y: Int) in
            let fraction = (1 - (byColumn[x]! - low) / range) * 0.8 + 0.1
            return (x, Int((fraction * 3).rounded()))
        }
        canvas.plot(points)
        return canvas.text(row: 0)
    }

    // MARK: Footer and help

    private func messageFooter() -> Block? {
        if let port = confirmingStop, let server = monitor.server(port: port) {
            var block = Block()
            block.add(divider())
            let count = server.processes.count
            let question: Line = [Span("Stop \(server.project.name) ", palette.text1), Span(":\(port)", palette.port(monitor.colorIndex(for: port)).bold()),
                                  Span(" and its \(count) \(count == 1 ? "process" : "processes")?", palette.text1)]
            let keys: Line = [Span("y", palette.softRed.bold()), Span(" Stop   ", palette.softRed), Span("n", palette.text1.bold()), Span(" Cancel", palette.text3)]
            block.add(padded(Line.split(question, keys, width: inner)))
            block.add([])
            return block
        }
        if let menu, let server = monitor.server(port: menu.port) {
            return menuFooter(server, index: menu.index)
        }
        if let toast {
            var block = Block()
            block.add(divider())
            block.add(padded([Span(toast.text, toast.isError ? palette.softRed : palette.text2)]))
            block.add([])
            return block
        }
        return nil
    }

    /// The Actions menu opens from the footer, like the app's ⋯ menu.
    private func menuFooter(_ server: Server, index: Int) -> Block {
        var block = Block()
        block.add(divider())
        block.add(padded([Span(server.project.name + " ", palette.text2),
                          Span(":\(server.port)", palette.port(monitor.colorIndex(for: server.port)).bold())]))
        for (itemIndex, item) in actions(for: server).enumerated() {
            let isSelected = itemIndex == index
            var labelStyle = item.isDestructive ? palette.softRed : palette.text1
            if !item.isEnabled { labelStyle = palette.faded(palette.text1, 0.35) }
            let key: Line = item.key.map { [Span($0, isSelected ? palette.text1.bold() : palette.text3)] } ?? []
            let content = Line.split([Span(item.label, isSelected ? labelStyle.bold() : labelStyle)], key, width: inner)
            let highlight = isSelected ? palette.highlight : nil
            let marker = isSelected && highlight == nil ? "›" : " "
            block.add([Span(" ")] + ([Span(marker, palette.text1.bold())] + content + [Span(" ")]).background(highlight) + [Span(" ")],
                      action: .menuItem(itemIndex))
        }
        let hints = hintsFooter([("↑ ↓", "Select"), ("⏎", "Run"), ("esc", "Close")])
        block.add(hints.lines[1])
        block.targets += hints.targets.map { (block.lines.count - 1, $0.columns, $0.action) }
        block.add([])
        return block
    }

    private func hintsFooter(_ hints: [(key: String, label: String)], destructive: String? = nil, disabled: String? = nil) -> Block {
        var block = Block()
        block.add(divider())
        let pieces: [Line] = hints.map { hint in
            var keyStyle = palette.text1.bold()
            var labelStyle = palette.text3
            if hint.key == destructive {
                keyStyle = palette.softRed.bold()
                labelStyle = palette.softRed
            } else if hint.key == disabled {
                keyStyle = palette.faded(palette.text1, 0.4)
                labelStyle = palette.faded(palette.text3, 0.6)
            }
            return [Span(hint.key, keyStyle), Span(" " + hint.label, labelStyle)]
        }
        // Drop hints that don't fit from the end, keeping Keys for as long as
        // possible and always the last (Quit or Back).
        var kept = Set(hints.indices)
        func total() -> Int { kept.map { pieces[$0].width }.reduce(0, +) + max(kept.count - 1, 0) * 3 }
        let optional = hints.indices.dropLast().reversed()
        for index in optional where hints[index].key != "?" && total() > inner { kept.remove(index) }
        for index in optional where total() > inner { kept.remove(index) }

        var line: Line = []
        var hitAreas: [(Range<Int>, String)] = []
        for index in hints.indices where kept.contains(index) {
            if !line.isEmpty { line.append(Span("   ")) }
            let start = 2 + line.width
            line += pieces[index]
            hitAreas.append((start..<(2 + line.width), hints[index].key))
        }
        block.add(padded(line))
        for (range, key) in hitAreas {
            let event: InputEvent?
            switch key {
            case "⏎": event = .enter
            case "esc": event = .escape
            case "space": event = .character(" ")
            default: event = key.count == 1 ? .character(Character(key)) : nil
            }
            if let event { block.targets.append((1, range, .key(event))) }
        }
        block.add([])
        return block
    }

    private func helpTop() -> Block {
        var block = Block()
        block.add(centered([Span("Keys", palette.text1.bold())]))
        block.add([])
        block.add(divider())
        return block
    }

    private func helpBody() -> Block {
        let groups: [(String, [(String, String)])] = [
            ("Servers", [("↑ ↓  j k", "Select"), ("⏎", "Details"), ("space", "Actions"), ("c", "Clean up"),
                         ("t", "CPU for servers or the whole Mac")]),
            ("Actions", [("o", "Open in browser"), ("v", "Vercel preview"), ("u", "Pull request"), ("a", "Resume agent session"),
                         ("r", "Restart"), ("s", "Stop"), ("e", "Open in editor"), ("f", "Reveal in Finder"),
                         ("y", "Copy URL"), ("Y", "Copy command")]),
            ("Clean up", [("space", "Select or deselect"), ("a", "Select all"), ("⏎", "Stop selected"), ("esc", "Cancel")]),
            ("Details", [("⏎", "Open in browser"), ("space", "Actions"), ("i", "More or less info"), ("p", "Show or hide processes"),
                         ("tab", "Next server"), ("↑ ↓", "Scroll"), ("esc", "Back")]),
            ("Anywhere", [("?", "Keys"), ("esc", "Back, or quit from the list"), ("ctrl-l", "Redraw"), ("q", "Quit")]),
        ]
        var block = Block()
        for (title, keys) in groups {
            block.add([])
            block.add(padded([Span(title, palette.text2)]))
            for (key, label) in keys {
                block.add(padded([Span(key.padding(toLength: 13, withPad: " ", startingAt: 0), palette.text1.bold()), Span(label, palette.text3)]))
            }
        }
        block.add([])
        return block
    }

    private func padLeft(_ text: String, _ width: Int) -> String {
        String(repeating: " ", count: max(width - TextWidth.of(text), 0)) + text
    }
}
