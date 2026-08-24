// /* ============================================================
//    MONSIEUR — SHARED CLIENT
//    Loaded on every page after js/config.js. Provides:
//      sb                    - the Supabase client
//      getSession()          - current auth session or null
//      isStoreAdmin(userId)  - checks the store_admins table
//      requireAdmin()        - guards admin pages, redirects if not staff
//      signOutAndRedirect()  - signs out and sends the shopper somewhere
//      subscribeTable()      - realtime: run a callback on any change
// ============================================================ */
// const sb = window.supabase.createClient(
//   window.MONSIEUR_CONFIG.SUPABASE_URL,
//   window.MONSIEUR_CONFIG.SUPABASE_ANON_KEY
// );

// async function getSession() {
//   const { data, error } = await sb.auth.getSession();
//   if (error) { console.warn('getSession error', error); return null; }
//   return data.session || null;
// }

// async function isStoreAdmin(userId) {
//   if (!userId) return false;
//   const { data, error } = await sb
//     .from('store_admins')
//     .select('id')
//     .eq('id', userId)
//     .maybeSingle();
//   if (error) { console.warn('isStoreAdmin error', error); return false; }
//   return !!data;
// }

// /** Call at the top of monsieur_admin.html. Redirects to login if there's
//  *  no session, or back to the shop if the signed-in user isn't staff.
//  *  Returns the session on success so the caller can use it. */
// async function requireAdmin() {
//   const session = await getSession();
//   if (!session) {
//     window.location.href = 'monsieur_login.html?next=admin';
//     return null;
//   }
//   const admin = await isStoreAdmin(session.user.id);
//   if (!admin) {
//     alert("This account isn't a store admin yet. Ask an existing admin to add you in store_admins.");
//     window.location.href = 'monsieur_shop.html';
//     return null;
//   }
//   return session;
// }

// async function signOutAndRedirect(destination) {
//   await sb.auth.signOut();
//   window.location.href = destination || 'monsieur_shop.html';
// }

// /** Subscribe to every INSERT/UPDATE/DELETE on a table and re-run `onChange`.
//  *  Callers just reload their query — cheap, and always exactly consistent
//  *  with the DB, no manual patching of local state. */
// function subscribeTable(table, onChange) {
//   return sb
//     .channel(`realtime:${table}:${Math.random().toString(36).slice(2)}`)
//     .on('postgres_changes', { event: '*', schema: 'public', table }, onChange)
//     .subscribe();
// }

// /* ---------- shared cart (localStorage) ----------
//    Real browser storage, not a Claude artifact preview — this is a
//    deployed static site, so localStorage is the right tool to keep
//    the bag in sync between monsieur_shop.html and monsieur_pdp.html. */
// const CART_KEY = 'monsieur_cart_v1';

// function cartGet() {
//   try { return JSON.parse(localStorage.getItem(CART_KEY) || '[]'); }
//   catch (e) { return []; }
// }
// function cartSave(items) {
//   localStorage.setItem(CART_KEY, JSON.stringify(items));
// }
// function cartAdd(product, qty) {
//   const items = cartGet();
//   const existing = items.find(i => i.id === product.id);
//   if (existing) existing.qty += (qty || 1);
//   else items.push({
//     id: product.id, name: product.name, price: product.effective_price ?? product.price,
//     image: product.main_image_url, qty: qty || 1
//   });
//   cartSave(items);
//   return items;
// }
// function cartRemove(id) {
//   const items = cartGet().filter(i => i.id !== id);
//   cartSave(items);
//   return items;
// }
// function cartCount(items) {
//   return (items || cartGet()).reduce((s, i) => s + i.qty, 0);
// }
// function cartTotal(items) {
//   return (items || cartGet()).reduce((s, i) => s + i.qty * i.price, 0);
// }

/* ============================================================
   MONSIEUR — SHARED CLIENT
   Loaded on every page after js/config.js. Provides:
     sb                    - the Supabase client
     getSession()          - current auth session or null
     isStoreAdmin(userId)  - checks the store_admins table
     requireAdmin()        - guards admin pages, redirects if not staff
     signOutAndRedirect()  - signs out and sends the shopper somewhere
     subscribeTable()      - realtime: run a callback on any change
============================================================ */
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

/** Call at the top of monsieur_admin.html. Redirects to login if there's
 *  no session, or back to the shop if the signed-in user isn't staff.
 *  Returns the session on success so the caller can use it. */
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

/** Subscribe to every INSERT/UPDATE/DELETE on a table and re-run `onChange`.
 *  Callers just reload their query — cheap, and always exactly consistent
 *  with the DB, no manual patching of local state. */
function subscribeTable(table, onChange) {
  return sb
    .channel(`realtime:${table}:${Math.random().toString(36).slice(2)}`)
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
