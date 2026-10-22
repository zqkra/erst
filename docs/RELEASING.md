# Releasing

Every version of Erst ships the same way: a notarized `Erst.dmg` and an `appcast.xml` attached to a GitHub release. The download button in the README points at the latest `Erst.dmg`, and every installed copy reads the latest `appcast.xml` once a day, so publishing the release is what updates everyone.

Versions are plain numbers: 0.1.0, then 0.1.1, 0.1.2, and so on. There is no beta channel.

## Once per Mac

1. Join the Apple Developer Program and create a Developer ID Application certificate in Xcode or on developer.apple.com. Install it in the login keychain and check that `security find-identity -v -p codesigning` lists it.
2. Store notarization credentials under a profile name. The password is an app-specific password from appleid.apple.com:

   ```sh
   xcrun notarytool store-credentials erst-notary --apple-id you@example.com --team-id TEAMID
   ```

3. Put the update signing key in the login keychain. It already is on the Mac that created it (account `erst`). On another Mac, import the exported file:

   ```sh
   app/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account erst -f erst-sparkle-key
   ```

The update signing key is the most important secret of the project. Every installed copy trusts only updates signed with it, through `SUPublicEDKey` in `app/Support/Info.plist`. If it is lost, no installed copy can be updated again; if it leaks, someone else could sign an update. Export it once and keep it in a password manager, never in the repository:

```sh
app/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account erst -x erst-sparkle-key
```

## Every release

1. Raise `version` under `[workspace.package]` in `Cargo.toml`, run `scripts/check.sh`, and commit and push to `main`.
2. Write the notes in a text file, one sentence per line. Settings, About shows these lines under the new version, and the GitHub release uses the same file.
3. Run the release:

   ```sh
   ERST_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
   ERST_NOTARY_PROFILE=erst-notary \
   scripts/release.sh notes.txt
   ```

   The script builds the app and the DMG with the Developer ID and the hardened runtime, notarizes and staples the DMG, signs it with the update key, writes `appcast.xml`, and creates the release `v<version>` with both files.

4. Open the release page, then check the update from an installed copy: Settings, About, Check Now.

## Testing an update before it ships

`--local` builds the DMG and the feed without notarizing or publishing, and `ERST_UPDATE_FEED_URL` points an installed copy at that feed:

```sh
ERST_RELEASE_BASE_URL=http://127.0.0.1:8765 scripts/release.sh --local notes.txt
(cd dist/release && python3 -m http.server 8765 --bind 127.0.0.1) &
open -a /Applications/Erst.app --env ERST_UPDATE_FEED_URL=http://127.0.0.1:8765/appcast.xml
```

Build the feed from a higher version than the copy you test with. Sparkle waits a day between checks, so run `defaults delete app.erst.Erst SULastCheckTime` before opening Erst to make it check at once.

## The first public release

The repository stays private until 0.1.0 is notarized. Publish 0.1.0 with the steps above, then make the repository public. The feed URL and the download link only resolve once the repository is public and has a release.
