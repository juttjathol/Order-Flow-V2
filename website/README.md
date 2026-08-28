# Jathol Order Flow — public website

This folder is a **separate** Cloudflare Pages project from the license SaaS dashboard in `cloudflare_dashboard/`.

Do not deploy this over the existing `order-flow-v2` Pages project. Create a **new** Pages project (for example `jathol` or your custom domain).

## Deploy

```bash
cd website
npx wrangler pages deploy public --project-name=YOUR_NEW_PROJECT
```

Or connect this `website/` directory in the Cloudflare dashboard as its own site.

## APK download

`/download` is a Pages Function. It pulls the newest `.apk` from GitHub releases and streams it to the visitor. They never see GitHub.

If the GitHub repo is **private**, set a Pages secret on **this** new project:

- `GITHUB_TOKEN` — a token that can read releases

## WhatsApp

All contact buttons open `https://wa.me/Jathol_Jutt` with the license request template.

## Privacy URL in the Android app

After this site has a live URL (custom domain recommended), tell the agent that URL so `kPrivacyUrl` in the APK can point at `/privacy` here. The SaaS dashboard is not edited.
