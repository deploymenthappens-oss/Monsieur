// /* ============================================================
//    MONSIEUR — static server for Railway.
//    Railway runs a persistent process, not static hosting, so this
//    is a tiny Express server that serves the HTML/JS files as-is.
//    All real data (products, orders, accounts) lives in Supabase —
//    this process never touches a database directly.

//    The one exception: /js/config.js is generated on the fly from
//    Railway environment variables (SUPABASE_URL, SUPABASE_ANON_KEY)
//    instead of being a static file. That way the anon key never has
//    to be committed to GitHub — it's injected at request time from
//    whatever you set in Railway's Variables tab.
// ============================================================ */
// const express = require('express');
// const path = require('path');

// const app = express();
// const PORT = process.env.PORT || 3000;

// const SUPABASE_URL = process.env.SUPABASE_URL || '';
// const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || '';

// if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
//   console.warn(
//     '⚠️  SUPABASE_URL and/or SUPABASE_ANON_KEY are not set. ' +
//     'The site will load but auth/data calls will fail until these ' +
//     'are set as environment variables (Railway: Variables tab).'
//   );
// }

// // Generated in place of a static js/config.js file — keeps secrets
// // out of the git repo and lets Railway env vars drive them.
// app.get('/js/config.js', (req, res) => {
//   res.type('application/javascript').send(
//     `window.MONSIEUR_CONFIG = ${JSON.stringify({
//       SUPABASE_URL,
//       SUPABASE_ANON_KEY
//     })};`
//   );
// });

// app.use(express.static(__dirname, { extensions: ['html'] }));

// // Friendly root -> storefront
// app.get('/', (req, res) => {
//   res.sendFile(path.join(__dirname, 'monsieur_shop.html'));
// });

// app.listen(PORT, () => {
//   console.log(`Monsieur running on port ${PORT}`);
// });






/* ============================================================
   MONSIEUR — static server for Railway / Vercel / Render.
   Railway runs a persistent process, not static hosting, so this
   is a tiny Express server that serves the HTML/JS files as-is.
   All real data (products, orders, accounts) lives in Supabase —
   this process never touches a database directly.

   The one exception: /js/config.js is generated on the fly from
   environment variables (SUPABASE_URL, SUPABASE_ANON_KEY)
   instead of being a static file. That way the anon key never has
   to be committed to GitHub — it's injected at request time from
   whatever you set in your platform's Environment Variables tab.
============================================================ */
const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

const SUPABASE_URL = process.env.SUPABASE_URL || '';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || '';

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.warn(
    '⚠️  SUPABASE_URL and/or SUPABASE_ANON_KEY are not set. ' +
    'The site will load but auth/data calls will fail until these ' +
    'are set as environment variables.'
  );
}

// Generated in place of a static js/config.js file — keeps secrets
// out of the git repo and lets environment variables drive them.
app.get('/js/config.js', (req, res) => {
  res.type('application/javascript').send(
    `window.MONSIEUR_CONFIG = ${JSON.stringify({
      SUPABASE_URL,
      SUPABASE_ANON_KEY
    })};`
  );
});

// Serve static assets (CSS, images, JS files) from root
app.use(express.static(__dirname, { extensions: ['html'] }));

// Explicit HTML Page Routes to prevent 404 errors
app.get(['/', '/monsieur_shop.html', '/shop'], (req, res) => {
  res.sendFile(path.join(__dirname, 'monsieur_shop.html'));
});

app.get(['/monsieur_login.html', '/login'], (req, res) => {
  res.sendFile(path.join(__dirname, 'monsieur_login.html'));
});

app.get(['/monsieur_admin.html', '/admin'], (req, res) => {
  res.sendFile(path.join(__dirname, 'monsieur_admin.html'));
});

app.get(['/monsieur_pdp.html', '/pdp'], (req, res) => {
  res.sendFile(path.join(__dirname, 'monsieur_pdp.html'));
});

// Fallback: If route isn't found, load main shop
app.use((req, res) => {
  res.status(404).sendFile(path.join(__dirname, 'monsieur_shop.html'));
});

app.listen(PORT, () => {
  console.log(`Monsieur running on port ${PORT}`);
});
