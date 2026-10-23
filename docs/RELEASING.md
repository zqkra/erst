# Releasing

Every version of Erst ships the same way: an `Erst.dmg` and an `appcast.xml` attached to a GitHub release, and the same two files in the `erst-releases` bucket on Cloudflare R2, which erstapp.com serves. The download buttons on erstapp.com and in the README go to `https://erstapp.com/download`, the newest archive, and every installed copy reads `https://erstapp.com/appcast.xml` once a day and installs what it names, so publishing the release is what updates everyone, whether the repository is public or not.

Versions are plain numbers: 0.1.0, then 0.1.1, 0.1.2, and so on. There is no beta channel.

## Signing

Releases are signed with `Developer ID Application: Santiago Gaviria (J5T6L3M274)` and notarized by Apple, so macOS opens Erst on the first launch without a warning. macOS ties Screen Recording and Accessibility to the team ID, so a renewed certificate of the same team keeps every user's permissions, and any other certificate makes every user grant them again. Back up the certificate and its private key:

1. Open Keychain Access, choose the login keychain, then My Certificates.
2. Control-click `Developer ID Application: Santiago Gaviria`, choose Export, save it as a `.p12` file, and give it a password.
3. Keep the file and its password in a password manager, then delete the file.

On another Mac, double-click the `.p12` to import it before you build.

`scripts/release.sh --unnotarized notes.txt` publishes a release signed with the self-signed `Erst Development` certificate and without notarization, for private builds only. Do not use it for a public release: macOS stops its first launch, and the certificate change takes the permissions away. The script refuses an ad hoc signature in either mode.

## Once per Mac

1. Join the Apple Developer Program and create a Developer ID Application certificate in Xcode or on developer.apple.com. Install it in the login keychain and check that `security find-identity -v -p codesigning` lists it.
2. Store notarization credentials under a profile name. The password is an app-specific password from appleid.apple.com:

   ```sh
   xcrun notarytool store-credentials erst-notary --apple-id you@example.com --team-id J5T6L3M274
   ```

3. Put the update signing key in the login keychain. It already is on the Mac that created it (account `erst`). On another Mac, import the exported file:

   ```sh
   app/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account erst -f erst-sparkle-key
   ```

The update signing key is the most important secret of the project. Every installed copy trusts only updates signed with it, through `SUPublicEDKey` in `app/Support/Info.plist`. If it is lost, no installed copy can be updated again; if it leaks, someone else could sign an update. Export it once and keep it in a password manager, never in the repository:

```sh
app/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account erst -x erst-sparkle-key
```

4. Install Wrangler (`brew install cloudflare-wrangler`) and run `wrangler login` with the Cloudflare account that owns erstapp.com. The release uploads the DMG with it.

## Every release

1. Raise `version` under `[workspace.package]` in `Cargo.toml`, run `scripts/check.sh`, and commit and push to `main`.
2. Write the notes in a text file, one sentence per line. Settings, About shows these lines under the new version, and the GitHub release uses the same file.
3. Run the release:

   ```sh
   ERST_SIGN_IDENTITY="Developer ID Application: Santiago Gaviria (J5T6L3M274)" \
   ERST_NOTARY_PROFILE=erst-notary \
   scripts/release.sh notes.txt
   ```

   The script builds the app and the DMG with the Developer ID and the hardened runtime, notarizes and staples the DMG, signs it with the update key, writes `appcast.xml`, creates the release `v<version>` with both files, and uploads to the bucket the DMG as `v<version>/Erst.dmg`, which the feed names, the DMG again as `Erst.dmg`, which the download buttons serve, and last the feed. New downloads and installed copies see the release within five minutes.

4. Open the release page, then check the update from an installed copy: Settings, About, Check Now.

## The website

`site/` is erstapp.com: a Cloudflare Worker named `erstapp` (`site/worker.js`, `site/wrangler.jsonc`) that answers the home page, `/download`, and `/appcast.xml`, the last two from the `erst-releases` bucket. Every other file is served directly, which is free and unlimited, with the headers in `site/_headers`. The home page's one inline script is allowed by its hash in the Content-Security-Policy, set in both files: change the script and the hash must change too. Publish a change to the site with:

```sh
cd site && wrangler deploy
```

A release never needs a deploy: the download follows the bucket. `www.erstapp.com` redirects to `erstapp.com`.

## Testing an update before it ships

`--local` builds the DMG and the feed without notarizing or publishing, and `ERST_UPDATE_FEED_URL` points an installed copy at that feed:

```sh
ERST_RELEASE_BASE_URL=http://127.0.0.1:8765 scripts/release.sh --local notes.txt
(cd dist/release && python3 -m http.server 8765 --bind 127.0.0.1) &
open -a /Applications/Erst.app --env ERST_UPDATE_FEED_URL=http://127.0.0.1:8765/appcast.xml
```

Build the feed from a higher version than the copy you test with. Sparkle waits a day between checks, so run `defaults delete app.erst.Erst SULastCheckTime` before opening Erst to make it check at once.

## The first public release

0.1.0 is published, notarized, and erstapp.com serves its download and feed. Making the repository public adds the source, the stars on the website, and the GitHub release page; downloads and updates already work without it.
