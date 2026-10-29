# Deployment status

Recorded state as of **29 October 2026**. For team setup use the [README](README.md); for deployment procedure use the [backend guide](Docs/Backend.md).

- App: `Baduy.xcodeproj`, **Baduy** scheme, bundle ID `com.academy.IKN.Baduy`, minimum iOS 18.0.
- Shared Supabase project: **Baduy**, reference `ulkyjrblperugtbvpvye`; originally configured in Singapore on the Free plan.
- `001_foundation.sql`, `002_apple_tokens.sql`, and `003_editing_and_hardening.sql` were applied through SQL Editor. The CLI ledger was not populated in that deployment. **Verify and reconcile history before the first CLI database push. Do not replay bootstrap SQL.**
- Seven public tables have RLS; private media buckets and PostGIS queries are configured. SQL security assertions were previously run successfully with rolled-back fixtures.
- `username-login` and `delete-account` were deployed through the dashboard with shared helpers inlined. Gateway legacy JWT checks are off; password/rate-limit and token checks run inside the respective functions. `apple-login` is not deployed.
- Email signup and confirmation are enabled; anonymous login and Apple are disabled. The saved minimum password length is 12. Custom SMTP is not configured.
- Exact callbacks saved: `baduy://auth/confirmation`, `baduy://auth/recovery`, `sosmedpoc://auth/confirmation`, and `sosmedpoc://auth/recovery`. Native flows use explicit redirects and PKCE. Site URL remains localhost.
- The `dummy` development account was created and its placeholder email confirmed administratively. No password is recorded in these docs. Its mailbox cannot receive recovery email.
- Existing users/data are shared between Baduy and sosmedPOC. The integration did not reset the database or redeploy the schema.
- Debug/Release builds and 36 Swift assertions passed during the Baduy integration. These are not substitutes for the [device smoke test](Docs/Development.md#device-smoke-test).

Outstanding work includes device verification, real guide data, production email delivery, cleanup scheduling, and Apple sign-in setup if required. See [development notes](Docs/Development.md) for test-data behavior and limits.

[SOCIAL_INTEGRATION.md](SOCIAL_INTEGRATION.md) retains the integration handoff and backup context; it is not the current deployment runbook.
