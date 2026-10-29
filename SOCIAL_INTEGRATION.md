# Baduy + social features

Open `Baduy.xcodeproj` and run the **Baduy** scheme. The existing bundle identifier `com.academy.IKN.Baduy`, signing team, app name, and asset catalog are retained.

## Included

- Username/password authentication and email confirmation/recovery.
- Home feed, photos/videos, votes, profile/report flows, uploads, and My Posts moderation status.
- Guides with development sample profiles and WhatsApp booking links.
- Photo-thumbnail map pins and clustered experiences.
- Upload location picker focused on Kanekes/Ciboleger.
- Map tab checks a fresh device location: inside the approximate Kanekes polygon opens the native Baduy 3D map; outside or unavailable location uses the social photo map.
- Current Baduy native features, including Ngahuma AR, characters, cultural objects, terrain, and dialogs.

The original native source remains under `Baduy/Model`, `Baduy/View`, and `Baduy/Reusable`. Social code is grouped under `Baduy/Social`. `BaduyApp` now hosts the authentication flow and the three main tabs. Native observable state uses Combine to match the host; debug simulated location defaults off. Bundled terrain avoids blocking map startup on elevation downloads.

## Backend and credentials

The app uses the same existing Supabase project (`ulkyjrblperugtbvpvye`). Existing users, posts, media, and moderation data are shared; no schema reset or duplicate deployment was performed.

`Config.xcconfig` includes local `Local.xcconfig`, which contains only public client backend configuration and is ignored by Git. Apple sign-in remains off. Never put a service-role key in the app.

Baduy registers its own `baduy` URL scheme and uses `baduy://auth/confirmation` and `baduy://auth/recovery`. Both exact destinations were saved to Supabase's redirect allowlist. The old sosmedPOC callbacks remain allowed, so both app builds can coexist. PKCE remains enabled and email links must open on the initiating device. The Keychain service names use Baduy's namespace; sign in again in this app. Email delivery restrictions of the current Supabase setup still apply.

## Verification

Debug and Release generic iOS-device builds passed. All 22 existing core checks and 14 map-area checks passed. Built app inspection confirms Baduy's identity, callback scheme, backend host, permission messages, and bundled AR/audio/terrain resources.

Run `Tests/run-core-tests.sh` and `Tests/run-map-area-tests.sh` for repeatable checks. One pre-existing Ngahuma texture API deprecation warning remains. Physical GPS, camera/AR, WhatsApp launch, and actual email-link delivery need an iPhone smoke test; they were not exercised by the command-line build.

On-device smoke test: sign in using the existing dummy account, check Home and Guide, open an upload and verify the Kanekes picker, then open Map. Test a simulated location at (-6.5944, 106.2255) for Baduy and (-6.2, 106.8) for the photo map; leave and reopen Map after changing locations. Test denied location access as well. In the local map open Ngahuma and an AR object, then return to the social tabs.

## Backups

Complete pre-merge copies of both projects were saved under this chat workspace at `work/baduy-main/backups/Baduy` and `work/baduy-main/backups/sosmedPOC`. The original `/Users/yebateo/Developer/sosmedPOC` was not modified by this integration.
