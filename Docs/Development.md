# Development and known limits

[Back to README](../README.md)

## Test data

The Guide page uses four fictional profiles only in unoptimized development builds, and only after a successful server response with no guides. Backend errors still show an error. Release builds do not show the fallback samples. The samples live in `GuideView.swift`, not in Supabase.

Sample booking buttons use `GUIDE_DEMO_WHATSAPP_NUMBER` from ignored `Local.xcconfig`, embedded through `Info.plist`. With no number configured, sample booking buttons are hidden. **This is a real destination**, not a fake contact. Opening the link prefills a message marked as a demo; sending is manual. Do not send test messages unless coordinated with its owner. The local number is not committed. It is embedded in your built app, so use an approved destination when distributing builds.

A development account named `dummy` exists in the shared backend using a placeholder email, confirmed administratively. Obtain authorized testing access privately; never commit its password or tokens. That placeholder has no inbox, so email recovery cannot work for it. Use a real approved test mailbox for signup/recovery validation. Do not disable confirmation globally to make a test pass.

Both Baduy and sosmedPOC currently share backend data. Changes to users, posts, or moderation through either app affect the same project. Sessions are stored separately per app; sign in again when switching builds.

## Debug location switch

In an Xcode Debug build, open **Map → Location test** and choose **In Baduy** or **Outside Baduy**. In Baduy opens the native experience at a simulated Ciboleger position; drag the movement pad to approach characters, and use Reset position to return. Outside Baduy opens the social photo map. **Use real GPS** restores normal permission and location checks. The choice lasts while the map view remains alive, including tab switches; it is not saved between app launches. These controls are excluded from Release builds. They do not bypass login, moderation, or camera permissions, or change upload coordinates.

## Device smoke test

1. Run the **Baduy** scheme. Verify login, logout, username validation, and session restoration.
2. For a real permitted test email, test confirmation and recovery on the initiating device. For Simulator, open the link inside Simulator Safari, not Mac Safari.
3. Check Home, pagination, photo/video playback, and votes. Confirm a failed request leaves the UI usable.
4. Submit a photo and a short video. Verify upload progress, My Posts pending state, and moderator approval before visibility to other users.
5. Open the upload location picker. Confirm its Kanekes/Ciboleger view, pan/zoom limits, remembered selection, and optional consent.
6. Open Map with location denied: the photo map should remain usable. With an authorized device location at Ciboleger (-6.5944, 106.2255), the native map should open. Jakarta (-6.2, 106.8) should show photo pins. Use Xcode's location simulation where available; return to Map after changing the location.
7. Tap single/grouped photo pins, open posts, and return to the map.
8. In the local experience, open characters, cultural objects, and Ngahuma. Test camera denial, device support, backgrounding, returning to tabs, and closing sheets.
9. Check Guide search/details and the WhatsApp booking draft without sending an unsolicited message.
10. Test account deletion only with a disposable account and media. It is destructive and is not covered by the core unit checks.

## What has been checked

As of the 29 October 2026 integration, Debug and Release generic iOS-device builds passed, as did 22 core assertions and 14 map-policy assertions. Built-app inspection verified the bundle identity, callback scheme, backend configuration, permission descriptions, and required AR/audio/terrain assets. There is a pre-existing Ngahuma texture API deprecation warning.

These checks do not certify live email delivery, a successful on-device authentication flow, AR performance, or all media scenarios. No automated UI suite or CI deployment workflow is supplied. Repeat the relevant device checks before a release.

## Limits and follow-ups

- The map routing polygon is illustrative, not surveyed. Refine it with verified local information; do not present it as an official village boundary.
- Routing checks on entering Map/foreground return, not continuously during an AR session. Imprecise or stale fixes fall back to the photo map.
- Uploaded locations are approximate; media uploads are limited to 25 MB and videos to 60 seconds.
- Map queries return at most 150 recent approved posts per area; cluster counts describe loaded posts, not an all-time total.
- Guide content is not yet a production catalog. WhatsApp contact starts a conversation; it does not reserve a date or take payment.
- Apple sign-in is disabled pending Apple/Supabase setup. Do not turn it on solely by changing the UI flag.
- Public email onboarding needs mail-delivery setup. Scheduled orphan-media and rate-limit-table cleanup remain outstanding.
- Native bundled models/textures include development assets; review source/usage rights and cultural accuracy before public distribution. See [Ngahuma texture notes](NgahumaTextures.md).

## Troubleshooting

| Symptom | First check |
|---|---|
| “Add your Supabase configuration” | Populate `Local.xcconfig` and rebuild; values are embedded at build time |
| Device signing fails | Select an authorized team on the Baduy target; the stored team belongs to the original setup |
| Login fails | Username/password, confirmation state, connectivity, and the deployed username-login function; do not log passwords |
| No confirmation email | Recipient eligibility, rate limit, and SMTP settings; do not repeatedly request emails |
| Link opens the wrong app | Baduy build must register `baduy`, not `sosmedpoc`; open the link on the initiating device |
| Uploaded post absent from Home | Check My Posts; pending/removed content is not the approved feed |
| Empty guide API but samples in app | Samples are client-side development fallback; only verified server guides are readable |
| Local map does not open | Location permission, freshness/accuracy, polygon, and reopening Map after location changes |
| “PostGIS” or table-already-exists migration errors | Stop and reconcile migration history; do not rerun bootstrap SQL |

## Before a GitHub push

Check the intended diff and include app/backend changes together where needed. Keep `Local.xcconfig`, signing credentials, service-role keys, access tokens, database dumps, and passwords out of commits. Existing `.gitignore` covers local config and build output, but ignored files previously tracked would still require review. This documentation task does not constitute a Git-history secret or asset-license audit.

The app's Swift folder is synchronized in Xcode; source additions there join the app automatically. Keep scripts, docs, and SQL outside that folder. Backend deployments and app signing/distribution should remain explicit maintainer actions until a reviewed automation workflow is added.
