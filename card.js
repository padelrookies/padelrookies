// ============================================================
// PADELROOKIES — Lógica compartida de la tarjeta personalizable
// Inclúyelo DESPUÉS de auth.js (usa el cliente global `sb`):
//   <script src="auth.js"></script>
//   <script src="card.js"></script>
//
// Expone: CARD_VISUALS, DEFAULT_CARD_CONFIG, applyCardConfig(),
//         renderCardBadges(), y wrappers de RPC (purchaseItem,
//         saveCardConfig, toggleFollow, getPublicCard) + fetchers.
// ============================================================

// Mapa visual cliente: traduce cada item_key del catálogo a su clase
// CSS / color / muestra. El catálogo de la BD manda en coste y "premium";
// esto solo decide cómo se ve.
const CARD_VISUALS = {
  backgrounds: {
    'bg-rookie':     { cls: 'card-bg-rookie',     swatch: 'linear-gradient(135deg,#1a1a1a,#0a0a0a)' },
    'bg-grafito':    { cls: 'card-bg-grafito',    swatch: 'linear-gradient(135deg,#34373b,#16181b)' },
    'bg-verdenoche': { cls: 'card-bg-verdenoche', swatch: 'linear-gradient(135deg,#11261a,#06120c)' },
    'bg-carbono':    { cls: 'card-bg-carbono',    swatch: 'repeating-linear-gradient(45deg,#262626 0 3px,#111 3px 6px)' },
    'bg-neon':       { cls: 'card-bg-neon',       swatch: 'linear-gradient(135deg,#2a0a3a,#06121f)' },
    'bg-holo':       { cls: 'card-bg-holo',       swatch: 'conic-gradient(from 0deg,#ff2d9b,#00e5ff,#d4ff3f,#ff2d9b)' }
  },
  accents: {
    'accent-lima':    '#d4ff3f',
    'accent-blanco':  '#ffffff',
    'accent-gris':    '#9aa0a6',
    'accent-cian':    '#00e5ff',
    'accent-magenta': '#ff2d9b',
    'accent-dorado':  '#f5c542'
  },
  effects: {
    'fx-none':     '',
    'fx-metal':    'card-fx-metal',
    'fx-animated': 'card-fx-animated',
    'fx-holo':     'card-fx-holo'
  },
  frames: {
    'frame-simple': 'card-avatar-frame--simple',
    'frame-lima':   'card-avatar-frame--lima',
    'frame-dorado': 'card-avatar-frame--dorado',
    'frame-holo':   'card-avatar-frame--holo'
  }
};

const DEFAULT_CARD_CONFIG = {
  bg:          'bg-rookie',
  accent:      'accent-lima',
  effect:      'fx-none',
  avatarFrame: 'frame-simple',
  badges:      []
};

// Quita de un elemento todas las clases que empiecen por un prefijo dado
function stripClasses(el, prefix) {
  if (!el) return;
  Array.from(el.classList).forEach((c) => {
    if (c.indexOf(prefix) === 0) el.classList.remove(c);
  });
}

// Aplica una card_config a una tarjeta. `wrapEl` debe contener la cara
// frontal (.member-card-face--front) o, en su defecto, un .member-card.
function applyCardConfig(wrapEl, config) {
  if (!wrapEl) return;
  const cfg = Object.assign({}, DEFAULT_CARD_CONFIG, config || {});

  // Acento → variable CSS que heredan ambas caras
  const accent = CARD_VISUALS.accents[cfg.accent] || CARD_VISUALS.accents['accent-lima'];
  wrapEl.style.setProperty('--card-accent', accent);

  const front = wrapEl.querySelector('.member-card-face--front') ||
                (wrapEl.classList && wrapEl.classList.contains('member-card') ? wrapEl : wrapEl.querySelector('.member-card'));
  if (!front) return;

  // Fondo
  stripClasses(front, 'card-bg-');
  const bg = CARD_VISUALS.backgrounds[cfg.bg];
  front.classList.add(bg ? bg.cls : 'card-bg-rookie');

  // Efecto
  stripClasses(front, 'card-fx-');
  const fx = CARD_VISUALS.effects[cfg.effect];
  if (fx) front.classList.add(fx);

  // Marco de avatar
  const avatar = front.querySelector('.card-avatar');
  if (avatar) {
    stripClasses(avatar, 'card-avatar-frame--');
    avatar.classList.add(CARD_VISUALS.frames[cfg.avatarFrame] || 'card-avatar-frame--simple');
  }
}

// Pinta las insignias en un contenedor (.card-badges o lista del reverso).
// `badges` es un array de objetos { key, name, icon }.
function renderCardBadges(containerEl, badges) {
  if (!containerEl) return;
  containerEl.innerHTML = '';
  (badges || []).forEach((b) => {
    const span = document.createElement('span');
    span.className = 'card-badge';
    span.title = b.name || b.key || '';
    span.textContent = b.icon || '🏅';
    containerEl.appendChild(span);
  });
}

// ── Wrappers de RPC (servidor) ─────────────────────────────────────
async function purchaseItem(itemKey) {
  const { data, error } = await sb.rpc('purchase_item', { p_item_key: itemKey });
  if (error) throw error;
  return data; // { ok, credits, already_owned? }
}

async function saveCardConfig(config, message, instagram, tiktok) {
  const { data, error } = await sb.rpc('save_card_config', {
    p_config:    config,
    p_message:   message ?? null,
    p_instagram: instagram ?? null,
    p_tiktok:    tiktok ?? null
  });
  if (error) throw error;
  return data;
}

async function toggleFollow(targetId) {
  const { data, error } = await sb.rpc('toggle_follow', { p_target: targetId });
  if (error) throw error;
  return data; // { ok, following, is_mutual }
}

async function getPublicCard(memberNumber) {
  const { data, error } = await sb.rpc('get_public_card_by_number', { p_member_number: memberNumber });
  if (error) throw error;
  return data; // objeto tarjeta o null
}

// ── Fetchers directos (lectura) ────────────────────────────────────
async function fetchCatalog() {
  const { data, error } = await sb
    .from('customization_items')
    .select('item_key,name,category,cost,is_premium,sort')
    .order('category')
    .order('sort');
  if (error) throw error;
  return data || [];
}

async function fetchMyUnlocks() {
  // Devuelve un Set de item_key desbloqueados por el usuario actual
  const { data, error } = await sb
    .from('user_unlocks')
    .select('customization_items(item_key)');
  if (error) throw error;
  const set = new Set();
  (data || []).forEach((row) => {
    const k = row.customization_items?.item_key;
    if (k) set.add(k);
  });
  return set;
}

async function fetchMyBadges() {
  const { data, error } = await sb
    .from('user_badges')
    .select('badges(badge_key,name,icon)')
    .order('earned_at');
  if (error) throw error;
  return (data || []).map((r) => ({
    key:  r.badges?.badge_key,
    name: r.badges?.name,
    icon: r.badges?.icon
  })).filter((b) => b.key);
}
