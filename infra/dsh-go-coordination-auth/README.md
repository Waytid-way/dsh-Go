# DSH Go Development Worker OAuth Consent

This isolated static frontend serves the OAuth consent page for the private DSH Go Coordination MCP connector.

- Branch: `waytid/coordination-oauth-consent-20261120`
- Render Workspace: `tea-d5j957be5dus739mucug` (My Workspace)
- Render Site: `dsh-go-worker-auth-dev`
- Host: static only; no privileged secrets or Supabase service role key.
- Tested path for direct Render service: `/oauth/consent.html`. Authorization Path should match exactly if OAuth Server is enabled.
- The `render.yaml` alongside this README is an optional Blueprint specification, NOT automatically applied by Render's direct create_static_site endpoint. Its routing and HTTP security headers need separate verification/application if the direct endpoint was used.

## Render direct site configuration

- Repository `https://github.com/Waytid-way/dsh-Go`
- Branch `waytid/coordination-oauth-consent-20261120`
- Build: `cd infra/dsh-go-coordination-auth && node tests/static-check.mjs`
- Publish: `infra/dsh-go-coordination-auth/public`
- Auto deploy: off

## OAuth setup

1. Verify the public Render static URL and `/oauth/consent.html` with a valid HTML content type, JS, CSS and security policy.
2. In Supabase development project's Authentication → URL Configuration, review current Site URL and allowed redirects before changing any defaults.
3. In Authentication → OAuth Server, enable OAuth 2.1 and use Authorization Path `/oauth/consent.html` if static direct hosting is used.
4. Configure OAuth client registration (prefer explicitly registered client; DCR requires deliberate approval), authenticate through the worker account in browser, and approve only known client/scopes.
5. Only after real user-session verification: test fixture claim, conflict, evidence idempotency, lease release. Real program and Engineering Automation stay disabled until separately authorized.

## Security boundaries

The public site uses only a Supabase publishable key. Worker UUID is deliberately **not shipped** in public JS. Account-to-worker authorization is enforced by `coordination.worker_identities` and Supabase RPCs; a browser UX restriction is never an authorization control. A CSP meta tag provides defense in depth; check actual HTTP response headers (X-Frame-Options, CSP, nosniff, Referrer-Policy) before live OAuth consent. No tokens, passwords, or OTPs may be placed in GitHub or chat.
