import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.musicAppPlaying { musicBanner }

            // The current song's controls stay put; choices and notices appear below them.
            if let c = model.nowPlaying { nowPlaying(c) }

            switch model.state {
            case .idle:
                if model.nowPlaying == nil { idle }
            case .choosing(let candidates):
                if model.nowPlaying != nil { Divider() }
                choosing(candidates)
            case .notice(let message, let action):
                notice(message, action)
            }

            if model.busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Finding it\u{2026}").font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - States

    private var idle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Drop a song title on the menu bar icon").font(.headline)
            Text("Select text in your browser, drag it onto the icon, let go. It plays, and the app gets out of the way.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func choosing(_ candidates: [Candidate]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.nowPlaying == nil ? "Which one?" : "Play instead?").font(.headline)
                Spacer()
                Button("Cancel") { model.dismissChoices() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(candidates) { c in
                Button { model.play(c) } label: {
                    HStack(spacing: 8) {
                        artwork(c.artworkURL, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.title).lineLimit(1)
                            Text([c.artist, c.album].compactMap { $0 }.joined(separator: " \u{00B7} "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func nowPlaying(_ c: Candidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                artwork(c.artworkURL, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.headline).lineLimit(2)
                    Text(c.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            ProgressView(value: model.duration > 0 ? min(model.position / model.duration, 1) : 0)
            HStack {
                Text(format(model.position))
                Spacer()
                Text(format(model.duration))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button { model.togglePause() } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                Button { model.stop() } label: { Image(systemName: "stop.fill") }
                Spacer()
            }
            .buttonStyle(.borderless)
        }
    }

    private func notice(_ message: String, _ action: PlayerModel.NoticeAction?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
            switch action {
            case .openPrivacySettings?: Button("Open Privacy Settings") { model.openPrivacySettings() }
            case nil: EmptyView()
            }
        }
    }

    private var musicBanner: some View {
        HStack {
            Image(systemName: "speaker.wave.2.fill").foregroundStyle(.orange)
            Text("Music.app is still playing").font(.callout)
            Spacer()
            Button("Pause it") { model.pauseMusicApp() }.controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private func artwork(_ url: URL?, size: CGFloat) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(max(seconds, 0))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
