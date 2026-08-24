# Monsieur — deploy checklist

## 1. Supabase
1. Create a Supabase project.
2. SQL Editor → paste **monsieur_schema.sql** → Run. Creates every table, view, RLS policy.
3. Auth → Providers → make sure Email is enabled (it is by default).
4. Settings → API → copy **Project URL** and **anon public key**. You'll paste these into Railway, not into any file.

## 2. GitHub
```
git init
git add .
git commit -m "Monsieur v1"
git branch -M main
git remote add origin <your-repo-url>
git push -u origin main
```
`.gitignore` already excludes `node_modules/` and `.env*`. There is **no `config.js` file with real keys in this repo** — see below.

## 3. Railway
1. New Project → Deploy from GitHub repo → select this repo.
2. Variables tab → add:
   - `SUPABASE_URL` = your Project URL
   - `SUPABASE_ANON_KEY` = your anon public key
3. Deploy. Railway sets `PORT` itself; `server.js` already reads `process.env.PORT`.
4. Open the generated Railway URL — the storefront should load.

`server.js` generates `/js/config.js` on every request from `SUPABASE_URL` / `SUPABASE_ANON_KEY`, so the anon key lives only in Railway's Variables tab, never in git. (The anon key is designed to be public/client-exposed — Supabase's Row Level Security is what actually protects the data — but keeping it out of source control is still better hygiene and means you can rotate it without a commit.)

## 4. Become the first admin
1. On the live site, go to `/monsieur_login.html` → **Create account** with your own email.
2. Supabase dashboard → Authentication → Users → copy your new user's UUID.
3. Supabase SQL Editor:
   ```sql
   insert into store_admins (id, email, full_name, role)
   values ('<your-uuid>', 'you@example.com', 'Your Name', 'owner');
   ```
4. Go to `/monsieur_login.html` again and sign in → you'll land on `/monsieur_admin.html`.

## 5. Add products
Admin → Products → fill the form (image URLs — host images anywhere public: Supabase Storage, Cloudinary, imgur, etc. — this app takes URLs, it doesn't upload files) → Save. It appears on the storefront within a second via realtime, no redeploy needed.
