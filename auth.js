// ============================================================
// PADELROOKIES — Cliente Supabase y estado de sesión compartido
// Inclúyelo en TODAS las páginas, justo después del script CDN de
// supabase-js y antes de cualquier script propio de la página:
//
//   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
//   <script src="auth.js"></script>
//
// Expone globalmente: SUPABASE_URL, SUPABASE_KEY, sb (el cliente).
// ============================================================

const SUPABASE_URL = 'https://bkjqnrmpnkvmvbrrdowy.supabase.co';
const SUPABASE_KEY = 'sb_publishable_rkV5qXS3t8AvqT8BKstzMQ_ucr4eMCm';

const STORAGE_KEY = 'padelrookies-auth-session';
let lastHeaderState = null;

function getBrowserStorage() {
  try {
    if (typeof window !== 'undefined' && window.sessionStorage) return window.sessionStorage;
    if (typeof window !== 'undefined' && window.localStorage) return window.localStorage;
  } catch (err) {
    console.warn('Storage unavailable:', err);
  }
  return null;
}

const browserStorage = getBrowserStorage();

function savePersistedSession(session) {
  if (!browserStorage) return;
  try {
    if (session) {
      browserStorage.setItem(STORAGE_KEY, JSON.stringify(session));
    } else {
      browserStorage.removeItem(STORAGE_KEY);
    }
  } catch (err) {
    console.warn('Could not persist auth session:', err);
  }
}

function readPersistedSession() {
  if (!browserStorage) return null;
  try {
    const raw = browserStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (err) {
    console.warn('Could not read persisted auth session:', err);
    return null;
  }
}

const sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    storage: browserStorage || undefined,
    storageKey: 'sb-padelrookies-auth'
  }
});

async function restorePersistedSession() {
  const persisted = readPersistedSession();
  if (!persisted?.access_token || !persisted?.refresh_token) return null;

  try {
    const { data, error } = await sb.auth.setSession({
      access_token: persisted.access_token,
      refresh_token: persisted.refresh_token
    });
    if (error) throw error;
    if (data?.session) {
      savePersistedSession(data.session);
      return data.session;
    }
  } catch (err) {
    console.warn('Failed to restore session:', err);
  }
  return null;
}

// ── Cierra sesión y vuelve al inicio ───────────────────────────────
async function prLogout(e) {
  if (e) e.preventDefault();
  try {
    await sb.auth.signOut();
  } catch (err) {
    console.warn('Logout error:', err);
  }
  savePersistedSession(null);
  window.location.href = 'index.html';
}

// ── Pinta el botón del header según haya o no sesión ───────────────
// Una página puede gestionar su propio header-right marcándolo con
// data-auth-managed="self" (p. ej. perfil.html).
async function renderAuthHeader() {
  const right = document.querySelector('.header-right');
  if (!right || right.dataset.authManaged === 'self') return;

  try {
    let session = await restorePersistedSession();

    if (!session) {
      const { data: { session: currentSession } = {}, error } = await sb.auth.getSession();
      if (error) throw error;
      session = currentSession;
    }

    const nextHeaderState = session ? 'logged-in' : 'logged-out';
    if (lastHeaderState === nextHeaderState) {
      return;
    }

    lastHeaderState = nextHeaderState;

    if (session) {
      savePersistedSession(session);
      right.innerHTML =
        '<a href="perfil.html" class="btn-login">Mi perfil</a>' +
        '<a href="#" class="btn-logout" id="prLogoutBtn">Salir</a>';
      const btn = document.getElementById('prLogoutBtn');
      if (btn) btn.addEventListener('click', prLogout);
    } else {
      savePersistedSession(null);
      right.innerHTML = '<a href="login.html" class="btn-login">Entrar</a>';
    }
  } catch (err) {
    console.warn('Auth header render failed:', err);
    if (lastHeaderState !== 'logged-out') {
      lastHeaderState = 'logged-out';
      right.innerHTML = '<a href="login.html" class="btn-login">Entrar</a>';
    }
  }
}

// Pinta al cargar y cada vez que cambie el estado de autenticación
// (login, logout, refresco de token) en cualquier pestaña.
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => renderAuthHeader());
} else {
  renderAuthHeader();
}
sb.auth.onAuthStateChange((event, session) => {
  if (event === 'TOKEN_REFRESHED' || event === 'INITIAL_SESSION') {
    return;
  }

  savePersistedSession(session);
  renderAuthHeader();
});
