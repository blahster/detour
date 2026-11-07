# Detour

A tiny macOS menu bar player. Drag a song title from anywhere (a web page, Reddit, a chat) onto a small drop pad under the menu bar icon and it plays from your Apple Music subscription, on its own queue, without touching whatever Music.app is playing.

- Menu bar only: no Dock icon, no main window.
- Plays with MusicKit, so no web view and no screen scraping.
- Idle cost is close to nothing: no timers or polling unless the popup is open.
- Understands real-world titles such as `"Missing" (Todd Terry Club Mix) by Everything But The Girl`,
  and picks the right mix over the original.

Requires macOS 14 or later, an Apple Music subscription, and (to build it yourself) a paid
Apple Developer Program membership.

## Contents

- [Installing](#installing)
- [Using Detour](#using-detour)
- [Building from source](#building-from-source)
- [Sharing a build with friends](#sharing-a-build-with-friends)
- [How it works](#how-it-works)
- [Project layout](#project-layout)
- [Tests](#tests)
- [Secrets and what not to commit](#secrets-and-what-not-to-commit)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)

## Installing

If you just want to use Detour, you do not need Xcode or a developer account.

1. Download `Detour.zip` from the repository's **Releases** page.
2. Double-click the zip to unzip it. You get `Detour.app`.
3. Drag `Detour.app` into your **Applications** folder.
4. Open it from Applications (or Spotlight). The first time, macOS asks whether you want to open
   an app downloaded from the Internet; click **Open**.
5. A music-note icon appears in the menu bar. There is no Dock icon and no window.
6. Drop a song title on it (see [Using Detour](#using-detour)). macOS asks for Apple Music access
   on the first drop; click **Allow**.

Run it from Applications, not from Downloads, so that **Launch at login** works.

You need macOS 14 or later and your own Apple Music subscription.

**Updating:** quit Detour (click the icon, then **Quit**), download the new zip, and drag the new
`Detour.app` over the old one in Applications, choosing Replace.

**Uninstalling:** quit Detour, untick **Launch at login** first if you turned it on, then drag
`Detour.app` from Applications to the Trash. To revoke its permissions, remove Detour under
System Settings > Privacy & Security > Media & Apple Music.

## Using Detour

1. Start dragging selected text. A small **Drop** pad appears just under the menu bar icon.
2. Drop the text on it. If the match is clear, the song plays and the icon turns into a waveform
   (hover for the title).
3. If the match is unclear, the popup opens with up to three candidates. Click one.
4. Click the icon any time for progress, pause and stop. Esc or a click elsewhere closes it.

Supported input:

| Dropped text          | Example                                                      |
| --------------------- | ------------------------------------------------------------ |
| Title and artist      | `Missing by Everything But The Girl`                         |
| Artist - Title        | `Everything But The Girl - Missing`                          |
| With a mix or version | `"Missing" (Todd Terry Club Mix) by Everything But The Girl` |
| Apple Music song link | `https://music.apple.com/.../album/...?i=123456`             |

Dropping onto the menu bar icon itself also works, but macOS opens Mission Control when a drag
reaches the top screen edge, which is why the pad sits below the menu bar.

Tick **Launch at login** in the popup to start Detour automatically. Do this from the copy in
`/Applications`, since macOS ties the login item to the app's location.

On first use macOS asks for Apple Music access (allow it). If Music.app is open, it may also ask
to let Detour control it; that is only used to show a "Music.app is still playing, pause it?"
banner.

## Building from source

### One-time setup

1. Install Xcode (the full app, not only the Command Line Tools). Open it once, accept the
   license, and sign in to your developer account under Xcode > Settings > Accounts.
   
   ```
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

2. Install XcodeGen: `brew install xcodegen`

3. **Register an App ID with MusicKit.** At developer.apple.com > Certificates, Identifiers &
   Profiles > Identifiers, click **+**, choose **App IDs** > **App**, pick **Explicit**, and enter
   a bundle ID that is unique to you (for example `com.yourname.detour`). On the **App Services**
   tab tick **MusicKit**, then save. (MusicKit is an App Service on the App ID, not an
   entitlement, so you will not find it in a provisioning profile.)

4. Create your local config and fill it in:
   
   ```
   cp Config.example Config.local
   ```
   
   | Key                | Meaning                                                                        |
   | ------------------ | ------------------------------------------------------------------------------ |
   | `DEVELOPMENT_TEAM` | Your 10-character Team ID (developer.apple.com > Account > Membership details) |
   | `BUNDLE_ID`        | The exact bundle ID you registered in step 3                                   |
   | `NOTARY_PROFILE`   | Only for `dist`: the keychain profile name from the sharing section            |
   
   `Config.local` is git-ignored. Neither value is a secret, but they are personal to you.

### Commands

```
./build.sh test      # parser and ranker tests (no signing needed)
./build.sh build     # generate the Xcode project, build a dev-signed Detour.app
./build.sh run       # build, then (re)launch
./build.sh install   # build, copy to /Applications, launch
./build.sh dist      # Developer ID sign, notarize, staple -> dist/Detour.zip
```

`Detour.xcodeproj` and `Config/Info.plist` are generated from `project.yml` on every build, so
change settings in `project.yml`, not in Xcode.

## Sharing a build with friends

A normal build only runs on your own Mac. To hand out a copy, make a signed and notarized one.
Friends need only macOS 14+ and their own Apple Music subscription: no Xcode, no developer
account. Your MusicKit App ID covers every user.

### One-time setup

1. **Developer ID Application certificate.** In Xcode: Settings > Accounts > your team > Manage
   Certificates > **+** > **Developer ID Application**. If Xcode refuses (it sometimes says only
   the Account Holder can do this, even to the Account Holder), create it from the command line:
   
   ```
   mkdir -p ~/detour-signing && cd ~/detour-signing
   openssl req -new -newkey rsa:2048 -nodes -keyout detour.key -out detour.csr \
     -subj "/emailAddress=you@example.com/CN=Your Name"
   ```
   
   Upload `detour.csr` at developer.apple.com/account/resources/certificates/add (choose
   **Developer ID Application**, **G2 Sub-CA** if offered), download the `.cer`, then:
   
   ```
   security import detour.key -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
   security import developerID_application.cer -k ~/Library/Keychains/login.keychain-db
   security find-identity -v -p codesigning     # should list "Developer ID Application: ..."
   ```
   
   If the identity shows as untrusted, import the **Developer ID - G2** intermediate certificate
   from apple.com/certificateauthority the same way. Keep `~/detour-signing` outside this repo.
2. **Notarization credentials.** Create an app-specific password at account.apple.com >
   Sign-In and Security > App-Specific Passwords, then store it in your keychain (not in a file):
   
   ```
   xcrun notarytool store-credentials "detour-notary" \
     --apple-id "you@example.com" --team-id "YOURTEAMID" --password "xxxx-xxxx-xxxx-xxxx"
   ```
3. Put `NOTARY_PROFILE=detour-notary` in `Config.local`.

### Each release

```
./build.sh dist
```

This builds a universal (Apple silicon and Intel) app with Developer ID signing, the hardened
runtime and a secure timestamp; checks the signature; submits it to Apple and waits; staples the
ticket; and writes `dist/Detour.zip`. Notarization usually takes a few minutes.

Friends unzip it, drag `Detour.app` to `/Applications`, and open it. macOS shows the normal
"downloaded from the Internet" confirmation once; there is no other security warning.

Host the zip as a **GitHub Release** asset rather than committing it to the repo.

## How it works

1. **Parse** (`QueryParser`): strips quotes, pulls out `(version)` and `[version]` tags and
   `feat.` credits, then reads the text as `Title by Artist` (splitting on the last " by ", so
   "Stand by Me by Ben E. King" works) and as `Artist - Title`, keeping several readings.
2. **Search** (`CatalogResolver`): a MusicKit catalog search for the cleanest reading, plus the
   raw text as a backstop; results are merged and de-duplicated.
3. **Rank** (`Ranker`): scores each result on title, artist and version. If you named a mix it
   must match; if you did not, the original is preferred. Karaoke, tribute and cover versions are
   penalised unless asked for. A clear winner plays immediately, a close call shows up to three
   choices, and nothing plausible shows "no match".
4. **Play** (`PlayerModel`): queues the one song on `ApplicationMusicPlayer`, which has its own
   queue separate from Music.app. State changes come from player events, so nothing polls. The
   one-second progress timer exists only while the popup is open.
5. **UI**: `DropPad` listens for text drags with two lightweight global mouse monitors and shows
   the pad under the icon; `PopupPanel` is a custom borderless panel placed exactly under the
   icon (instead of `NSPopover`) and resized in place.

## Project layout

| Path                                                                                      | Purpose                                                                                                                                              |
| ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Sources/DetourCore/`                                                                     | Pure Foundation: `TextUtil`, `QueryParser`, `Ranker`. No UI, fully tested.                                                                           |
| `Sources/Detour/CatalogResolver.swift`                                                    | MusicKit catalog search                                                                                                                              |
| `Sources/Detour/PlayerModel.swift`                                                        | Playback, state, authorization, login item, Music.app check                                                                                          |
| `Sources/Detour/AppDelegate.swift`, `DropPad.swift`, `PopupPanel.swift`, `DropView.swift` | Status item, drop pad, popup                                                                                                                         |
| `Sources/Detour/PopoverView.swift`                                                        | SwiftUI popup content                                                                                                                                |
| `Sources/Detour/Assets.xcassets/`                                                         | App icon set (all macOS sizes)                                                                                                                       |
| `Design/`                                                                                 | `AppIcon-1024.png` is the icon master (transparent corners); `make_icon_set.sh` regenerates every size from it into the asset catalog (uses the built-in sips tool) |
| `Tests/main.swift`                                                                        | Plain-assertion test runner (no XCTest needed)                                                                                                       |
| `project.yml`                                                                             | XcodeGen project definition                                                                                                                          |
| `Config/Detour.entitlements`                                                              | Entitlements used only for distribution builds                                                                                                       |
| `Config.example`                                                                          | Template for your local `Config.local`                                                                                                               |
| `build.sh`                                                                                | Build, run, install, dist, test                                                                                                                      |

## Tests

```
./build.sh test
```

Covers title/artist/mix parsing and the ranking and auto-play decision rules. The UI and
MusicKit playback are not covered by automated tests.

## Secrets and what not to commit

Nothing in this repo is a secret. Keep it that way:

| Item                                                                            | Where it lives                                                                            | Commit?             |
| ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------- |
| Developer ID private key and certificate                                        | Your login keychain (back up an exported `.p12` in a password manager or encrypted drive) | Never               |
| Notarization app-specific password                                              | Your keychain, via `notarytool store-credentials`                                         | Never               |
| Apple ID password                                                               | Apple / your password manager                                                             | Never               |
| `Config.local` (Team ID, bundle ID)                                             | Your machine                                                                              | No (git-ignored)    |
| Signing files (`*.key`, `*.csr`, `*.cer`, `*.p12`, `*.p8`, `*.mobileprovision`) | Outside the repo, for example `~/detour-signing`                                          | Never (git-ignored) |
| Built apps and zips (`build/`, `build-dist/`, `dist/`)                          | Local; publish zips as GitHub Releases                                                    | No (git-ignored)    |
| `Detour.xcodeproj`, `Config/Info.plist`                                         | Generated by XcodeGen                                                                     | No (git-ignored)    |

MusicKit needs no key or token in the code: Apple issues the developer token from the app's
signed identity.

If a secret is ever committed, deleting the file is not enough, because it stays in git history.
Treat it as exposed: revoke the app-specific password at account.apple.com, or revoke the
certificate at developer.apple.com and create a new one.

If you later automate releases in CI, store the base64-encoded `.p12`, its password and the
notarization credentials as encrypted repository secrets, never in the repo.

## Troubleshooting

| Symptom                                                                 | Likely cause and fix                                                                                                    |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `xcodebuild requires Xcode ... Command Line Tools`                      | Install Xcode and run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.                                |
| Build log says "failed with exit code 0 but produced no further output" | Harmless Xcode quirk. Check for the `Built ...` line.                                                                   |
| Popup says Apple refused the developer token                            | MusicKit is not ticked on the App ID, or `BUNDLE_ID` does not match it exactly. Check both, rebuild.                    |
| App ID not listed in the developer portal after building                | A plain build does not create one. Register it by hand (setup step 3).                                                  |
| Mission Control opens while dragging                                    | You dragged to the top screen edge. Drop on the pad below the menu bar.                                                 |
| "Only the Account Holder..." when creating a certificate in Xcode       | Use the command-line route in the sharing section.                                                                      |
| `get-task-allow` notarization error                                     | Already handled in `build.sh dist` (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`). The script also checks before submitting. |
| Notarization rejected                                                   | Run the `notarytool log` command that `build.sh` prints; the log says exactly why.                                      |
| Popup still shows a song after it ended | End-of-song detection depends on what MusicKit reports. Please open an issue with your macOS version. |
| Drop pad never appears                                                  | The source app may not put plain text on the drag pasteboard. Dragging files is ignored on purpose.                     |

## Known limitations

- Apple Music only (no YouTube Music or Spotify playback).
- Plays one song at a time; dropping a new title replaces the current one.
- Song links work; album, playlist and non-Apple links do not.
- Not sandboxed and not on the App Store. The Music.app "is it playing" check uses Apple Events
  and would have to be removed for a sandboxed build.
- Catalog results follow your Apple ID's storefront.

## License

MIT. See [LICENSE](LICENSE).
