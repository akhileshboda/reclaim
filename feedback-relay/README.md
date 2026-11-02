# Feedback relay

A small Cloudflare Worker that receives **Report a Bug… › Send** from Reclaim and emails it to the maintainer. It exists so people can report a problem without a GitHub account, while the maintainer's address stays out of the app and this repository.

- The app posts JSON (`message`, `app_version`, `macos_version`, optional `email`) to the Worker's URL.
- The Worker validates it, then sends one email through [Resend](https://resend.com) to the address in its `TO_EMAIL` secret. A `to` address in the request is ignored, so it can only ever reach the maintainer.
- The destination address and the Resend API key are Worker secrets, never in the source.
- A rate limit (see `wrangler.toml`) caps how fast reports can arrive.

## Deploy

You need a free [Cloudflare](https://dash.cloudflare.com/sign-up) account and a free [Resend](https://resend.com) account. Sign up to Resend with the inbox that should receive reports: until you verify a domain, Resend only delivers mail from `onboarding@resend.dev` to the account owner's own address.

1. In Resend, create an API key with **Sending access**.
2. From this folder:

   ```sh
   npx wrangler login
   npx wrangler deploy
   npx wrangler secret put RESEND_API_KEY   # paste the key
   npx wrangler secret put TO_EMAIL         # the inbox that receives reports
   ```

3. `wrangler deploy` prints the Worker's URL (`https://reclaim-feedback.<your-subdomain>.workers.dev`). Give it to the release build as a repository secret:

   ```sh
   gh secret set RECLAIM_FEEDBACK_URL --repo akhileshboda/reclaim
   ```

The URL is readable by anyone who unpacks a release, but it doesn't reveal the destination address. The rate limit and the Resend plan's own limits bound how much anyone can send.

## Test

```sh
node --test test/index.test.mjs
```
