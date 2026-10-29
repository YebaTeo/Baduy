# Backend and deployment

[Back to README](../README.md)

## Services and configuration

The currently shared Supabase project is **Baduy**, reference `ulkyjrblperugtbvpvye`. Its base URL is `https://ulkyjrblperugtbvpvye.supabase.co`. Treat this as a shared environment containing existing users/content, not a disposable database. Configuration described here is the recorded setup as of 29 October 2026; check the dashboard before operational changes.

| Service | Base path | Purpose |
|---|---|---|
| Auth | `/auth/v1` | Signup, session tokens, recovery, logout |
| Database REST | `/rest/v1` | Table queries and database functions |
| Storage | `/storage/v1` | Private media objects and signed URLs |
| Edge Functions | `/functions/v1` | Username login and account deletion |

Client config lives in `Local.xcconfig`: `SUPABASE_HOST`, `SUPABASE_PUBLISHABLE_KEY`, and optional Apple feature settings. The host excludes the scheme. Get the publishable key from the maintainer or project dashboard; no privileged key is needed to run the app.

The shared server helper reads `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` from the function environment. Those names describe the server configuration, not additional iOS settings. Apple code additionally needs its configured Apple credentials before enablement.

## Request examples

In Postman or another private API client, define `BASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `ACCESS_TOKEN`. Do not commit populated token/password environments.

Login:

```http
POST {{BASE_URL}}/functions/v1/username-login
apikey: {{SUPABASE_PUBLISHABLE_KEY}}
Content-Type: application/json
```

```json
{"username":"your_username","password":"your_password"}
```

Use the returned `access_token` as `ACCESS_TOKEN`. Authenticated JSON calls use:

```http
apikey: {{SUPABASE_PUBLISHABLE_KEY}}
Authorization: Bearer {{ACCESS_TOKEN}}
Content-Type: application/json
```

For example, `POST /rest/v1/rpc/feed_page` with `{}` returns the first feed page. `POST /rest/v1/rpc/map_posts` takes `south`, `west`, `north`, and `east`. `GET /rest/v1/tour_guides?select=*&order=name` lists guides visible to that user. `rpc` means a database function, not an Edge Function. Media uploads use the media MIME type instead of JSON.

## Data and permissions

| Table | Purpose / access |
|---|---|
| `profiles` | Public-facing user profile; authenticated reads, owner-limited edits |
| `posts` | Caption, categories, approximate location, moderation status; approved or own posts readable |
| `post_media` | Storage paths and media type linked to posts |
| `votes` | One vote per user/post; owner-limited writes |
| `tour_guides` | Only verified guides visible to authenticated clients; trusted admin edits |
| `reports` | User-submitted reports; clients cannot read the moderation queue |
| `community_guidance` | Visitor guidance text readable after sign-in |

All seven public tables have RLS. The `feed` view runs under the caller's permissions. `auth.users` stores authentication identities; it is not the public profile table. Private tables hold login rate-limit counters and optional Apple tokens. The service-role credential bypasses client access rules and belongs only in trusted server administration.

`post-media` and `guide-images` are private Storage buckets. Post uploads are restricted to the caller's UUID folder; reads depend on ownership or approved content. Guide images depend on verified guide records. `publish_post` validates media ownership and creates metadata; `edit_post` returns edited captions to moderation; `my_posts_page` includes the owner's pending content.

## Functions and authentication settings

- `username-login`: deployed; accepts a username/password before sign-in, checks rate limits, privately resolves the email, then verifies the password with Auth.
- `delete-account`: deployed; validates the caller's bearer token with Auth, removes media, and deletes that user. Apple token revocation is conditional on a stored Apple token.
- `apple-login`: source exists, but Apple sign-in is disabled and the function has not been deployed in the recorded setup.

`supabase/config.toml` sets gateway `verify_jwt = false` for these function names. This is intentional: login happens before a token exists; deletion validates the token inside the function. Keep those explicit checks when changing code. A function's presence in config does not mean it is deployed.

Email signup/confirmation are enabled; anonymous login and Apple login are disabled. Baduy uses these exact allowlisted callbacks:

```text
baduy://auth/confirmation
baduy://auth/recovery
```

The corresponding `sosmedpoc://` destinations remain for the other app. Native requests explicitly send their redirect; they do not depend on the dashboard's localhost Site URL. Custom SMTP is not configured in the recorded setup. The default mail service limits recipients and sending volume; arrange test users with the maintainer and verify current [SMTP restrictions](https://supabase.com/docs/guides/auth/auth-smtp) before onboarding the public.

## Existing-project migration history

**Do not replay `001`, `002`, or `003` against the shared project.** They were already applied through SQL Editor, without populating the CLI migration ledger. Git files alone do not establish what the remote database has applied.

A backend maintainer must compare the deployed schema/functions/policies with these files and inspect remote migration history before the first CLI database push. After confirming equivalence, reconcile the already-applied versions:

```sh
supabase login
supabase link --project-ref ulkyjrblperugtbvpvye
supabase migration list
# Only after verifying that these versions are already fully present:
supabase migration repair --status applied 001 002 003
supabase migration list
```

Repair records migration status; it does not execute or validate the schema. If history was already repaired, do not repeat this as routine teammate setup. Keep the existing migration filenames/version identifiers; add new timestamped migrations for subsequent changes. See Supabase's [migration workflow](https://supabase.com/docs/guides/deployment/database-migrations) and [CLI migration reference](https://supabase.com/docs/reference/cli/supabase-migration-list).

For a new disposable environment, apply the three migrations in order and configure Auth, functions, and callbacks separately. The minimal `config.toml` is not a complete local-environment snapshot; local parity has not been validated. Never run a database reset against the shared project.

## Deployment responsibilities

App distribution and backend deployment are independent. Review new database changes in a disposable environment, reconcile history, back up as appropriate, and inspect pending migrations before a maintainer applies them. Deploy backward-compatible backend changes before an app version that requires them. Use forward corrective migrations for shared databases rather than editing old migration files.

The first function deployments were pasted through the dashboard with `_shared/server.ts` inlined. Repository source now keeps that helper separate. Future deployments must include imported helper code, whether using CLI bundling or preparing dashboard source. Deploy only the intended function; do not enable the Apple path accidentally. Confirm authentication checks and rate limits after changes.

Moderation currently happens in the dashboard/trusted administration, not an in-app admin screen. Inspect the post and media before changing status to `approved` or `removed`. See `supabase/admin-examples.sql`. Only publish guide records and contact details with the owner's consent.

`supabase/tests/security.sql` contains transaction-based assertions that roll back fixtures; review and run them in a test environment using a suitable PostgreSQL client. It includes psql commands and is not a drop-in Swift/Xcode test. Orphan-media cleanup and rate-limit-counter cleanup are still operational follow-ups.
