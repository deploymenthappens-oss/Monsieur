/* ============================================================
   MONSIEUR — Express Server for Vercel
============================================================ */
const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Read Supabase credentials
const SUPABASE_URL = process.env.SUPABASE_URL || '';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_KEY || '';

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.warn('⚠️ SUPABASE_URL or SUPABASE_ANON_KEY / SUPABASE_KEY environment variables are missing.');
}

// 1. Dynamic Config Route
app.get('/js/config.js', (req, res) => {
  res.type('application/javascript').send(
    `window.MONSIEUR_CONFIG = ${JSON.stringify({
      SUPABASE_URL,
      SUPABASE_ANON_KEY
    })};`
  );
});

// 2. Dynamic Shared Client Route (Bypasses Vercel static file bundling issues)
app.get('/js/supabase-client.js', (req, res) => {
  res.type('application/javascript').send(`
    const sb = window.supabase.createClient(
      window.MONSIEUR_CONFIG.SUPABASE_URL,
      window.MONSIEUR_CONFIG.SUPABASE_ANON_KEY
    );

    async function getSession() {
      const { data, error } = await sb.auth.getSession();
      if (error) { console.warn('getSession error', error); return null; }
      return data.session || null;
    }

    async function isStoreAdmin(userId) {
      if (!userId) return false;
      const { data, error } = await sb
        .from('store_admins')
        .select('id')
        .eq('id', userId)
        .maybeSingle();
      if (error) { console.warn('isStoreAdmin error', error); return false; }
      return !!data;
    }

    async function requireAdmin() {
      const session = await getSession();
      if (!session) {
        window.location.href = 'monsieur_login.html?next=admin';
        return null;
      }
      const admin = await isStoreAdmin(session.user.id);
      if (!admin) {
        alert("This account isn't a store admin yet. Ask an existing admin to add you in store_admins.");
        window.location.href = 'monsieur_shop.html';
        return null;
      }
      return session;
    }

    async function signOutAndRedirect(destination) {
      await sb.auth.signOut();
      window.location.href = destination || 'monsieur_shop.html';
    }

    function subscribeTable(table, onChange) {
      return sb
        .channel(\`realtime:\${table}:\${Math.random().toString(36).slice(2)}\`)
        .on('postgres_changes', { event: '*', schema: 'public', table }, onChange)
        .subscribe();
    }

    /* ---------- shared cart (localStorage) ---------- */
    const CART_KEY = 'monsieur_cart_v1';

    function cartGet() {
      try { return JSON.parse(localStorage.getItem(CART_KEY) || '[]'); }
      catch (e) { return []; }
    }
    function cartSave(items) {
      localStorage.setItem(CART_KEY, JSON.stringify(items));
    }
    function cartAdd(product, qty) {
      const items = cartGet();
      const existing = items.find(i => i.id === product.id);
      if (existing) existing.qty += (qty || 1);
      else items.push({
        id: product.id, name: product.name, price: product.effective_price ?? product.price,
        image: product.main_image_url, qty: qty || 1
      });
      cartSave(items);
      return items;
    }
    function cartRemove(id) {
      const items = cartGet().filter(i => i.id !== id);
      cartSave(items);
      return items;
    }
    function cartCount(items) {
      return (items || cartGet()).reduce((s, i) => s + i.qty, 0);
    }
    function cartTotal(items) {
      return (items || cartGet()).reduce((s, i) => s + i.qty * i.price, 0);
    }
  `);
});

// 3. Serve static root assets
app.use(express.static(__dirname, { extensions: ['html'] }));

// 4. Page Routes
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

// 5. Fallback Route
app.use((req, res) => {
  res.status(404).sendFile(path.join(__dirname, 'monsieur_shop.html'));
});

app.listen(PORT, () => {
  console.log(`Monsieur running on port ${PORT}`);
});
