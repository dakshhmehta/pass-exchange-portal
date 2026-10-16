# Pass Exchange Portal

Minimal pass limit-order exchange. **Framework7 (MD theme, auto dark/light) + Vue 3 + Supabase**, client-only SPA, PWA-ready, deploys to Cloudflare Pages.

## Features

- Google login (Supabase Auth), Name + Mobile onboarding
- BUY / SELL **limit** orders with qty; price-time priority matching at maker price
- Market list: LTP, Prev Close, % change, Volume (today)
- Detail: order book (today's bids/asks), recent trades, order form
- Match notification: counterpart name + mobile appears under **Orders › Matches** so you settle payment + pass offline
- Daily expiry: book resets at 12am (cron marks stale orders `EXPIRED`, rolls `prev_close` to last trade)

## 1. Supabase setup

1. Create a project at https://supabase.com/dashboard
2. **SQL Editor →** paste & run [`supabase/schema.sql`](supabase/schema.sql)
3. **Auth → Providers → Google →** enable, add your Google OAuth Client ID/Secret
4. **Auth → URL Configuration →** Site URL = your Pages domain; add Redirect URLs:
   - `http://localhost:5173/**`
   - `https://<your>.pages.dev/**`
5. **Admin — add pass codes manually** (Table Editor → `instruments`):
   ```sql
   insert into public.instruments (pass_code, name, prev_close)
   values ('VIP2026', 'VIP Season Pass', 500);
   ```
6. **Daily expiry cron** — SQL Editor (needs `pg_cron` extension enabled):
   ```sql
   create extension if not exists pg_cron;
   select cron.schedule('passx-midnight-expiry', '30 18 * * *',
     $$select public.expire_orders_daily()$$);
   ```
   (`18:30 UTC` = `00:00 Asia/Kolkata`.)

## 2. Local dev

```bash
cp .env.example .env   # fill VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY
npm install
npm run dev            # http://localhost:5173
```

## 3. Deploy — Cloudflare Pages

- Build: `npm run build` → output `dist/`
- Connect repo in Cloudflare dashboard, or:
  ```bash
  npx wrangler pages deploy dist --project-name pass-exchange-portal
  ```
- Env vars in Pages → Settings: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`
- SPA fallback included via `public/_redirects` (`/* /index.html 200`)

## Notes

- Supabase Realtime + REST are `NetworkOnly` in the service worker — trading data never served stale.
- `prev_close` auto-rolls at midnight; admin can override manually in Table Editor.
- Replace `public/icons/icon-*.png` with real artwork when available.
