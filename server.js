/* ============================================================
   MONSIEUR — Express Server for Vercel / Render / Railway
============================================================ */
const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Read Supabase credentials (supports both SUPABASE_ANON_KEY and SUPABASE_KEY)
const SUPABASE_URL = process.env.SUPABASE_URL || '';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_KEY || '';

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.warn('⚠️ SUPABASE_URL or SUPABASE_ANON_KEY / SUPABASE_KEY environment variables are missing.');
}

// 1. Dynamic Config Route (Injects environment variables into frontend)
app.get('/js/config.js', (req, res) => {
  res.type('application/javascript').send(
    `window.MONSIEUR_CONFIG = ${JSON.stringify({
      SUPABASE_URL,
      SUPABASE_ANON_KEY
    })};`
  );
});

// 2. Serve static assets (includes your new js/ folder, images, CSS)
app.use(express.static(__dirname, { extensions: ['html'] }));

// 3. Page Routes
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

// 4. Fallback Route
app.use((req, res) => {
  res.status(404).sendFile(path.join(__dirname, 'monsieur_shop.html'));
});

app.listen(PORT, () => {
  console.log(`Monsieur running on port ${PORT}`);
});
