import Cocoa
import UserNotifications
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var remainingSeconds: Int = 0
    var isRunning: Bool = false
    var isWorkSession: Bool = true
    var selectedWorkMinutes: Int = 25
    var selectedBreakMinutes: Int = 10
    var autoRepeat: Bool = false

    var menu: NSMenu!
    var timerMenuItem: NSMenuItem!
    var startPauseMenuItem: NSMenuItem!
    var repeatMenuItem: NSMenuItem!
    var noiseMenuItem: NSMenuItem!

    var work15Item: NSMenuItem!
    var work30Item: NSMenuItem!
    var work45Item: NSMenuItem!
    var work60Item: NSMenuItem!

    // Audio
    var audioPlayer: AVAudioPlayer?
    var isNoisePlaying: Bool = false

    // Consistent button font
    let statusFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    let redColor   = NSColor(red: 1.0, green: 59/255.0, blue: 59/255.0, alpha: 1.0) // #FF3B3B

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if !granted {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Notification Permission Required"
                    alert.informativeText = "We'll notify you when your timer ends. Enable notifications in System Settings to get alerts."
                    alert.addButton(withTitle: "Open Settings")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                }
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setButtonTitle("🍋 00:00")
        buildMenu()
    }

    // MARK: - Status Bar Display

    /// Always use attributedTitle so vertical position never shifts.
    func setButtonTitle(_ text: String, red: Bool = false) {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: statusFont,
            .baselineOffset: NSNumber(value: 0)
        ]
        if red { attrs[.foregroundColor] = redColor }
        statusItem.button?.attributedTitle = NSAttributedString(string: text, attributes: attrs)
    }

    // MARK: - Audio

    func startNoise() {
        guard let url = Bundle.main.url(forResource: "cafe_loop", withExtension: "m4a") else {
            print("cafe_loop.m4a not found in bundle")
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1   // infinite seamless loop
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isNoisePlaying = true
            noiseMenuItem.title = "🎵 Cafe Noise: ON"
            updateDisplay()
        } catch {
            print("Audio error: \(error)")
        }
    }

    func stopNoise() {
        audioPlayer?.stop()
        audioPlayer = nil
        isNoisePlaying = false
        noiseMenuItem.title = "🎵 Cafe Noise: OFF"
        updateDisplay()
    }

    @objc func toggleNoise() {
        isNoisePlaying ? stopNoise() : startNoise()
    }

    // MARK: - Menu

    func buildMenu() {
        menu = NSMenu()

        timerMenuItem = NSMenuItem(title: "⏱ Flow Timer — Ready", action: nil, keyEquivalent: "")
        timerMenuItem.isEnabled = false
        menu.addItem(timerMenuItem)
        menu.addItem(NSMenuItem.separator())

        startPauseMenuItem = NSMenuItem(title: "▶ Start", action: #selector(toggleStartPause), keyEquivalent: "s")
        startPauseMenuItem.target = self
        menu.addItem(startPauseMenuItem)

        let resetItem = NSMenuItem(title: "↺ Reset", action: #selector(resetTimer), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        repeatMenuItem = NSMenuItem(title: "🔁 Auto Repeat: OFF", action: #selector(toggleRepeat), keyEquivalent: "")
        repeatMenuItem.target = self
        menu.addItem(repeatMenuItem)

        noiseMenuItem = NSMenuItem(title: "🎵 Cafe Noise: OFF", action: #selector(toggleNoise), keyEquivalent: "")
        noiseMenuItem.target = self
        menu.addItem(noiseMenuItem)

        menu.addItem(NSMenuItem.separator())

        let workHeader = NSMenuItem(title: "── Focus Duration ──", action: nil, keyEquivalent: "")
        workHeader.isEnabled = false
        menu.addItem(workHeader)

        work15Item = menuItem("  15 min", action: #selector(setWork15))
        work30Item = menuItem("  30 min", action: #selector(setWork30))
        work45Item = menuItem("  45 min", action: #selector(setWork45))
        work60Item = menuItem("  60 min", action: #selector(setWork60))
        [work15Item, work30Item, work45Item, work60Item].forEach { menu.addItem($0!) }

        menu.addItem(NSMenuItem.separator())

        let breakHeader = NSMenuItem(title: "── Break: 10 min ──", action: nil, keyEquivalent: "")
        breakHeader.isEnabled = false
        menu.addItem(breakHeader)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "✕ Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateWorkCheckmarks()
    }

    func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc func setWork15() { selectWork(15) }
    @objc func setWork30() { selectWork(30) }
    @objc func setWork45() { selectWork(45) }
    @objc func setWork60() { selectWork(60) }

    func selectWork(_ min: Int) {
        selectedWorkMinutes = min
        isWorkSession = true
        updateWorkCheckmarks()
        timer?.invalidate()
        timer = nil
        isRunning = false
        remainingSeconds = min * 60
        startTimer()
    }

    func updateWorkCheckmarks() {
        work15Item.state = selectedWorkMinutes == 15 ? .on : .off
        work30Item.state = selectedWorkMinutes == 30 ? .on : .off
        work45Item.state = selectedWorkMinutes == 45 ? .on : .off
        work60Item.state = selectedWorkMinutes == 60 ? .on : .off
    }

    @objc func toggleStartPause() {
        isRunning ? pauseTimer() : startTimer()
    }

    func startTimer() {
        if remainingSeconds == 0 {
            remainingSeconds = (isWorkSession ? selectedWorkMinutes : selectedBreakMinutes) * 60
        }
        isRunning = true
        startPauseMenuItem.title = "⏸ Pause"
        timerMenuItem.title = "\(isWorkSession ? "🔥 Focus" : "☕ Break") — Running"

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.current.add(timer!, forMode: .common)
        updateDisplay()
    }

    func pauseTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        startPauseMenuItem.title = "▶ Resume"
        timerMenuItem.title = "\(isWorkSession ? "🔥 Focus" : "☕ Break") — Paused"
    }

    @objc func resetTimer() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        remainingSeconds = 0
        isWorkSession = true
        startPauseMenuItem.title = "▶ Start"
        timerMenuItem.title = "⏱ Flow Timer — Ready"
        setButtonTitle(isNoisePlaying ? "🍋🎵 00:00" : "🍋 00:00")
    }

    @objc func toggleRepeat() {
        autoRepeat.toggle()
        repeatMenuItem.title = autoRepeat ? "🔁 Auto Repeat: ON" : "🔁 Auto Repeat: OFF"
    }

    func tick() {
        remainingSeconds -= 1
        updateDisplay()

        if remainingSeconds <= 0 {
            timer?.invalidate()
            timer = nil
            isRunning = false
            sendNotification()

            if autoRepeat {
                isWorkSession.toggle()
                remainingSeconds = (isWorkSession ? selectedWorkMinutes : selectedBreakMinutes) * 60
                startTimer()
            } else {
                let done = isWorkSession ? "Focus" : "Break"
                timerMenuItem.title = "✅ \(done) Complete!"
                startPauseMenuItem.title = "▶ Start"
                isWorkSession.toggle()
                setButtonTitle(isNoisePlaying ? "🍋🎵 00:00" : "🍋 00:00")
            }
        }
    }

    func updateDisplay() {
        guard remainingSeconds > 0 else { return }
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        let sessionIcon = isWorkSession ? "🔥" : "☕"
        let noiseIcon   = isNoisePlaying ? "🎵" : ""
        let text = String(format: "%@%@ %02d:%02d", sessionIcon, noiseIcon, m, s)
        setButtonTitle(text, red: remainingSeconds < 60)
    }

    func sendNotification() {
        let content = UNMutableNotificationContent()
        if isWorkSession {
            content.title = "🔥 Focus session complete!"
            content.body  = "Great work! Time to take a break."
        } else {
            content.title = "☕ Break is over!"
            content.body  = "Ready to focus again? Let's go."
        }
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }

    @objc func quitApp() {
        stopNoise()
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
