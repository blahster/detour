import AppKit
import Combine
import MusicKit
import ServiceManagement
import SwiftUI

@MainActor
final class PlayerModel: ObservableObject {
    enum NoticeAction { case openPrivacySettings }

    enum State {
        case idle
        case choosing([Candidate])
        case playing(Candidate)
        case notice(String, NoticeAction?)
    }

    @Published var state: State = .idle
    @Published var busy = false                 // searching
    @Published var isPaused = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var musicAppPlaying = false
    @Published var hasActivePlayback = false
    @Published var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    /// Set by the AppDelegate.
    var onNeedsAttention: (() -> Void)?
    var onIconChange: ((_ playing: Bool, _ tooltip: String?) -> Void)?

    private let resolver = CatalogResolver()
    private let player = ApplicationMusicPlayer.shared
    private var current: Candidate?
    private var searchTask: Task<Void, Never>?
    private var playTask: Task<Void, Never>?
    private var ticker: Timer?
    private var popoverVisible = false
    private var hasStartedPlaying = false
    private var stateSink: AnyCancellable?

    init() {
        // Event-driven: no polling. objectWillChange fires before the change lands, so hop a turn.
        stateSink = player.state.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.syncState() }
        }
    }

    // MARK: - Drop handling

    func handleDrop(_ text: String) {
        searchTask?.cancel()
        let q = QueryParser.parse(text)
        busy = true
        searchTask = Task { [weak self] in
            guard let self else { return }
            guard await self.ensureReady() else { self.busy = false; return }
            do {
                let found = try await self.resolver.candidates(for: q)
                if Task.isCancelled { return }
                self.busy = false

                if q.url != nil {
                    if let c = found.first { self.play(c) }
                    else { self.fail("Couldn't find that song in the catalog.") }
                    return
                }
                switch Ranker.decide(Ranker.rank(q, found)) {
                case .play(let c):
                    self.play(c)
                case .choose(let cs):
                    self.state = .choosing(cs)
                    self.onNeedsAttention?()
                case .none:
                    self.fail("No match for \u{201C}\(q.cleaned)\u{201D}.")
                }
            } catch {
                if Task.isCancelled { return }
                self.busy = false
                self.fail(Self.describe(error))
            }
        }
    }

    private func ensureReady() async -> Bool {
        var status = MusicAuthorization.currentStatus
        if status == .notDetermined { status = await MusicAuthorization.request() }
        guard status == .authorized else {
            state = .notice("Detour needs permission to use Apple Music.", .openPrivacySettings)
            onNeedsAttention?()
            return false
        }
        if let sub = try? await MusicSubscription.current, !sub.canPlayCatalogContent {
            fail("This Apple ID has no active Apple Music subscription.")
            return false
        }
        return true
    }

    private func fail(_ message: String) {
        state = .notice(message, nil)
        onNeedsAttention?()
    }

    private static func describe(_ error: Error) -> String {
        let s = String(describing: error).lowercased()
        if s.contains("token") {
            return "Apple refused the developer token. Enable MusicKit for this app's App ID (see README), then rebuild."
        }
        return error.localizedDescription
    }

    // MARK: - Playback (ApplicationMusicPlayer has its own queue, separate from Music.app)

    func play(_ c: Candidate) {
        guard let song = resolver.song(for: c) else {
            fail("That result has expired. Drop the title again.")
            return
        }
        playTask?.cancel()
        current = c
        state = .playing(c)
        isPaused = false
        position = 0
        duration = Double(c.durationMs ?? 0) / 1000
        hasActivePlayback = true
        hasStartedPlaying = false
        onIconChange?(true, "\(c.title) \u{2014} \(c.artist)")

        refreshMusicApp()
        if musicAppPlaying { onNeedsAttention?() }
        updateTicker()

        playTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.player.queue = ApplicationMusicPlayer.Queue(for: [song])
                try await self.player.play()
            } catch {
                if Task.isCancelled { return }
                self.finish()
                self.fail(Self.describe(error))
            }
        }
    }

    func togglePause() {
        if player.state.playbackStatus == .playing {
            player.pause()
        } else {
            Task { try? await player.play() }
        }
    }

    func stop() {
        playTask?.cancel()
        player.stop()
        finish()
    }

    private func finish() {
        current = nil
        hasActivePlayback = false
        hasStartedPlaying = false
        isPaused = false
        state = .idle
        onIconChange?(false, nil)
        updateTicker()
    }

    private func syncState() {
        guard hasActivePlayback else { return }
        switch player.state.playbackStatus {
        case .playing:
            hasStartedPlaying = true
            isPaused = false
        case .paused, .interrupted:
            isPaused = true
            if hasStartedPlaying, duration > 0, player.playbackTime >= duration - 1 { stop() }
        case .stopped:
            if hasStartedPlaying { finish() }      // reached the end of the one-song queue
        default:
            break
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            fail("Couldn't change the login item: \(error.localizedDescription)")
        }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Progress (only while the popup is open)

    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
        if visible { refreshMusicApp() }
        updateTicker()
    }

    private func updateTicker() {
        ticker?.invalidate()
        ticker = nil
        guard popoverVisible, hasActivePlayback else { return }
        tick()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard hasActivePlayback else { return }
        position = player.playbackTime
        syncState()
    }

    // MARK: - Music.app awareness

    /// Only asks if Music.app is already running, so it never launches it.
    func refreshMusicApp() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            musicAppPlaying = false
            return
        }
        var err: NSDictionary?
        let script = NSAppleScript(source: "tell application \"Music\" to return (player state is playing)")
        let result = script?.executeAndReturnError(&err)
        musicAppPlaying = (err == nil) && (result?.booleanValue ?? false)
    }

    func pauseMusicApp() {
        var err: NSDictionary?
        _ = NSAppleScript(source: "tell application \"Music\" to pause")?.executeAndReturnError(&err)
        musicAppPlaying = false
    }
}
