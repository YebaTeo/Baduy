# Baduy

An iOS app for sharing experiences around Kanekes, finding local guides, and exploring the Baduy map and AR experiences. The repository contains both the SwiftUI app and its Supabase backend source. They are deployed separately.

## Start here

- [Architecture and code map](Docs/Architecture.md)
- [Backend, API, and deployment](Docs/Backend.md)
- [Development, test data, and known limits](Docs/Development.md)
- [Deployment status](DEPLOYMENT.md)
- [Ngahuma texture notes](Docs/NgahumaTextures.md)

## Run the app

1. Clone the repository and open its root directory.
2. Use full Xcode, not only Command Line Tools. This project was built with Xcode 27.0; its iOS deployment target is 18.0. Older Xcode versions have not been validated.
3. Create local configuration without overwriting an existing file:

   ```sh
   cp -n Local.example.xcconfig Local.xcconfig
   ```

4. Set `SUPABASE_HOST` and `SUPABASE_PUBLISHABLE_KEY` using values supplied by the project maintainer. The host has no `https://` prefix. Leave Apple sign-in disabled.

   ```ini
   SUPABASE_HOST = your-project.supabase.co
   SUPABASE_PUBLISHABLE_KEY = your-publishable-key
   APPLE_SIGN_IN_ENABLED = NO
   GUIDE_DEMO_WHATSAPP_NUMBER =
   ```

5. Open `Baduy.xcodeproj`, select the **Baduy** scheme, and select an iPhone or Simulator. For a physical device, select an authorized team in **Signing & Capabilities**. The target currently sets the signing team directly; changing only the example config's `DEVELOPMENT_TEAM` may not override it. Avoid committing personal signing changes.
6. Run. Sign in with an assigned test account, or follow the maintainer's account setup instructions. Existing users in the shared Supabase project also work in Baduy. Passwords do not belong in this repository.

`Local.xcconfig` is ignored by Git. `Config.xcconfig` loads it, and `Info.plist` exposes its public settings to the app. A publishable key is client configuration; a service-role key is a server secret and must never go in the iOS app.

You do **not** need to deploy migrations or functions to run against the configured shared backend. Do not run `supabase db push` on first setup: [the deployed migrations need their history reconciled first](Docs/Backend.md#existing-project-migration-history).

## Main flows

- **Home:** approved posts, photo/video playback, votes, reports, and uploads. New posts wait for moderator approval.
- **Guide:** verified guide profiles. Development builds show clearly labeled samples when the server returns an empty guide list.
- **Map:** a fresh location inside the approximate Kanekes/Ciboleger area opens Baduy's local 3D/AR experience, including Ngahuma. Outside the area, or when location cannot be confirmed, the social photo map opens.
- **Upload location:** a separate picker constrained to the Kanekes/Ciboleger browsing area. Shared coordinates are rounded to two decimals.

## Repository layout

```text
Baduy/App/                 App entry, auth routing, and tabs
Baduy/Social/Core/         HTTP API, session storage, repository
Baduy/Social/Models/       Codable social data models
Baduy/Social/Features/     Feed, guides, uploads, auth, map routing
Baduy/Model/               Native map, terrain, and AR models
Baduy/View/                Native map and AR screens
Baduy/Reusable/            Native shared UI
Baduy/Asset/               Terrain, models, textures, and audio
supabase/migrations/       Database schema, RPCs, grants, and RLS
supabase/functions/        Server-side TypeScript functions
supabase/tests/            SQL security assertions and admin examples
Tests/                    Swift command-line checks
Docs/                     Team documentation
```

## Checks

From the repository root on macOS:

```sh
./Tests/run-core-tests.sh
./Tests/run-map-area-tests.sh
```

These run 22 core checks and 14 location-policy checks. They do not test live login, email delivery, rendering, or AR hardware. See the [device smoke-test checklist](Docs/Development.md#device-smoke-test).

The app target can also be compiled without device signing:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Baduy.xcodeproj -scheme Baduy -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/BaduyBuild \
  CODE_SIGNING_ALLOWED=NO build
```

## Working together

Keep a feature's UI, API changes, migration, and relevant tests in the same pull request. Add new migrations instead of rewriting deployed ones. Describe which changes require a backend deployment. A Git push alone does not deploy the app or backend in the documented workflow; no deployment pipeline is supplied here.
