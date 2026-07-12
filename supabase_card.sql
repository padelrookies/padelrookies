-- ============================================================
-- PADELROOKIES — Tarjeta personalizable + créditos + social
-- Ejecuta este SQL en: Supabase > SQL Editor > New query
-- Requiere haber ejecutado antes supabase_setup.sql (tabla profiles).
-- Es idempotente: se puede volver a ejecutar sin romper nada.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- 1. AMPLIAR profiles
-- ──────────────────────────────────────────────────────────
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS credits      INTEGER NOT NULL DEFAULT 50;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS avatar_url   TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS instagram    TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS tiktok       TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS card_message TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS card_config  JSONB NOT NULL DEFAULT '{}'::jsonb;

-- ──────────────────────────────────────────────────────────
-- 2. TABLAS NUEVAS
-- ──────────────────────────────────────────────────────────

-- Catálogo de ítems de personalización (gratis o de pago)
CREATE TABLE IF NOT EXISTS customization_items (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  item_key    TEXT UNIQUE NOT NULL,
  name        TEXT NOT NULL,
  category    TEXT NOT NULL CHECK (category IN ('background','accent','effect','avatar_frame')),
  cost        INTEGER NOT NULL DEFAULT 0,
  is_premium  BOOLEAN NOT NULL DEFAULT false,
  sort        INTEGER NOT NULL DEFAULT 0,
  meta        JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- Inventario: qué ítems premium ha desbloqueado cada usuario
CREATE TABLE IF NOT EXISTS user_unlocks (
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  item_id     BIGINT NOT NULL REFERENCES customization_items(id) ON DELETE CASCADE,
  unlocked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, item_id)
);

-- Historial de movimientos de créditos
CREATE TABLE IF NOT EXISTS credit_ledger (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  delta       INTEGER NOT NULL,
  reason      TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_credit_ledger_user ON credit_ledger(user_id);

-- Catálogo de insignias / logros (se ganan, no se compran)
CREATE TABLE IF NOT EXISTS badges (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  badge_key   TEXT UNIQUE NOT NULL,
  name        TEXT NOT NULL,
  icon        TEXT NOT NULL DEFAULT '🏅',
  description TEXT
);

-- Insignias conseguidas por cada usuario
CREATE TABLE IF NOT EXISTS user_badges (
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  badge_id    BIGINT NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
  earned_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, badge_id)
);

-- Grafo social: follows (mutuo = existen ambas direcciones)
CREATE TABLE IF NOT EXISTS follows (
  follower_id  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  following_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (follower_id, following_id),
  CHECK (follower_id <> following_id)
);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id);

-- ──────────────────────────────────────────────────────────
-- 3. SEMILLA DEL CATÁLOGO
-- ──────────────────────────────────────────────────────────
INSERT INTO customization_items (item_key, name, category, cost, is_premium, sort, meta) VALUES
  -- Fondos
  ('bg-rookie',     'Negro Rookie',  'background',   0, false, 10, '{}'),
  ('bg-grafito',    'Grafito',       'background',   0, false, 20, '{}'),
  ('bg-verdenoche', 'Verde noche',   'background',   0, false, 30, '{}'),
  ('bg-carbono',    'Carbono',       'background',  60, true,  40, '{}'),
  ('bg-neon',       'Degradado neón','background',  80, true,  50, '{}'),
  ('bg-holo',       'Holo prism',    'background', 100, true,  60, '{}'),
  -- Acentos
  ('accent-lima',    'Lima',     'accent',  0, false, 10, '{"color":"#d4ff3f"}'),
  ('accent-blanco',  'Blanco',   'accent',  0, false, 20, '{"color":"#ffffff"}'),
  ('accent-gris',    'Acero',    'accent',  0, false, 30, '{"color":"#9aa0a6"}'),
  ('accent-cian',    'Cian',     'accent', 40, true,  40, '{"color":"#00e5ff"}'),
  ('accent-magenta', 'Magenta',  'accent', 40, true,  50, '{"color":"#ff2d9b"}'),
  ('accent-dorado',  'Dorado',   'accent', 70, true,  60, '{"color":"#f5c542"}'),
  -- Efectos
  ('fx-none',     'Ninguno',         'effect',  0, false, 10, '{}'),
  ('fx-metal',    'Metálico',        'effect', 70, true,  20, '{}'),
  ('fx-animated', 'Brillo animado',  'effect', 80, true,  30, '{}'),
  ('fx-holo',     'Holográfico',     'effect', 90, true,  40, '{}'),
  -- Marcos de avatar
  ('frame-simple', 'Simple',       'avatar_frame',  0, false, 10, '{}'),
  ('frame-lima',   'Anillo lima',  'avatar_frame', 30, true,  20, '{}'),
  ('frame-dorado', 'Anillo oro',   'avatar_frame', 50, true,  30, '{}'),
  ('frame-holo',   'Anillo holo',  'avatar_frame', 90, true,  40, '{}')
ON CONFLICT (item_key) DO UPDATE
  SET name = EXCLUDED.name, category = EXCLUDED.category, cost = EXCLUDED.cost,
      is_premium = EXCLUDED.is_premium, sort = EXCLUDED.sort, meta = EXCLUDED.meta;

INSERT INTO badges (badge_key, name, icon, description) VALUES
  ('founder', 'Fundador', '👑', 'Uno de los 100 miembros fundadores de PadelRookies.'),
  ('pionero', 'Pionero',  '🚀', 'De los primeros en unirse a la comunidad.')
ON CONFLICT (badge_key) DO UPDATE
  SET name = EXCLUDED.name, icon = EXCLUDED.icon, description = EXCLUDED.description;

-- ──────────────────────────────────────────────────────────
-- 4. FUNCIONES DE SERVIDOR (SECURITY DEFINER)
--    El cliente nunca toca créditos ni decide qué premium posee.
-- ──────────────────────────────────────────────────────────

-- Comprar / desbloquear un ítem del catálogo
CREATE OR REPLACE FUNCTION purchase_item(p_item_key TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_item    customization_items%ROWTYPE;
  v_balance INTEGER;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

  SELECT * INTO v_item FROM customization_items WHERE item_key = p_item_key;
  IF NOT FOUND THEN RAISE EXCEPTION 'El ítem no existe: %', p_item_key; END IF;

  -- ¿ya lo tiene?
  IF EXISTS (SELECT 1 FROM user_unlocks WHERE user_id = v_uid AND item_id = v_item.id) THEN
    SELECT credits INTO v_balance FROM profiles WHERE id = v_uid;
    RETURN jsonb_build_object('ok', true, 'already_owned', true, 'credits', v_balance);
  END IF;

  -- gratis: desbloquear sin coste
  IF v_item.cost <= 0 THEN
    INSERT INTO user_unlocks(user_id, item_id) VALUES (v_uid, v_item.id) ON CONFLICT DO NOTHING;
    SELECT credits INTO v_balance FROM profiles WHERE id = v_uid;
    RETURN jsonb_build_object('ok', true, 'credits', v_balance);
  END IF;

  -- de pago: comprobar saldo bloqueando la fila
  SELECT credits INTO v_balance FROM profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < v_item.cost THEN
    RAISE EXCEPTION 'Créditos insuficientes (tienes %, cuesta %)', v_balance, v_item.cost;
  END IF;

  UPDATE profiles SET credits = credits - v_item.cost WHERE id = v_uid;
  INSERT INTO user_unlocks(user_id, item_id) VALUES (v_uid, v_item.id);
  INSERT INTO credit_ledger(user_id, delta, reason) VALUES (v_uid, -v_item.cost, 'compra:' || p_item_key);

  SELECT credits INTO v_balance FROM profiles WHERE id = v_uid;
  RETURN jsonb_build_object('ok', true, 'credits', v_balance);
END;
$$;

-- Guardar la configuración de la tarjeta validando lo premium
CREATE OR REPLACE FUNCTION save_card_config(
  p_config    JSONB,
  p_message   TEXT DEFAULT NULL,
  p_instagram TEXT DEFAULT NULL,
  p_tiktok    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid   UUID := auth.uid();
  v_key   TEXT;
  v_item  customization_items%ROWTYPE;
  v_badge TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

  -- Validar ítems elegidos (fondo, acento, efecto, marco): si son premium, deben estar desbloqueados
  FOR v_key IN
    SELECT value FROM jsonb_each_text(p_config)
    WHERE key IN ('bg','accent','effect','avatarFrame') AND value IS NOT NULL AND value <> ''
  LOOP
    SELECT * INTO v_item FROM customization_items WHERE item_key = v_key;
    IF FOUND AND v_item.is_premium THEN
      IF NOT EXISTS (SELECT 1 FROM user_unlocks WHERE user_id = v_uid AND item_id = v_item.id) THEN
        RAISE EXCEPTION 'Ítem premium no desbloqueado: %', v_key;
      END IF;
    END IF;
  END LOOP;

  -- Validar insignias mostradas: deben estar conseguidas
  IF p_config ? 'badges' THEN
    FOR v_badge IN SELECT jsonb_array_elements_text(p_config->'badges')
    LOOP
      IF NOT EXISTS (
        SELECT 1 FROM user_badges ub JOIN badges b ON b.id = ub.badge_id
        WHERE ub.user_id = v_uid AND b.badge_key = v_badge
      ) THEN
        RAISE EXCEPTION 'Insignia no conseguida: %', v_badge;
      END IF;
    END LOOP;
  END IF;

  UPDATE profiles SET
    card_config  = p_config,
    card_message = COALESCE(p_message,   card_message),
    instagram    = COALESCE(p_instagram, instagram),
    tiktok       = COALESCE(p_tiktok,    tiktok)
  WHERE id = v_uid;

  RETURN jsonb_build_object('ok', true);
END;
$$;

-- Conceder créditos manualmente (solo admin / service role; ver REVOKE más abajo)
CREATE OR REPLACE FUNCTION grant_credits(p_user UUID, p_amount INTEGER, p_reason TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_balance INTEGER;
BEGIN
  UPDATE profiles SET credits = credits + p_amount WHERE id = p_user RETURNING credits INTO v_balance;
  IF NOT FOUND THEN RAISE EXCEPTION 'El perfil no existe'; END IF;
  INSERT INTO credit_ledger(user_id, delta, reason) VALUES (p_user, p_amount, COALESCE(p_reason, 'grant'));
  RETURN jsonb_build_object('ok', true, 'credits', v_balance);
END;
$$;

-- Seguir / dejar de seguir a un miembro
CREATE OR REPLACE FUNCTION toggle_follow(p_target UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid       UUID := auth.uid();
  v_following BOOLEAN;
  v_mutual    BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
  IF v_uid = p_target THEN RAISE EXCEPTION 'No puedes seguirte a ti mismo'; END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_target) THEN RAISE EXCEPTION 'El miembro no existe'; END IF;

  IF EXISTS (SELECT 1 FROM follows WHERE follower_id = v_uid AND following_id = p_target) THEN
    DELETE FROM follows WHERE follower_id = v_uid AND following_id = p_target;
    v_following := false;
  ELSE
    INSERT INTO follows(follower_id, following_id) VALUES (v_uid, p_target) ON CONFLICT DO NOTHING;
    v_following := true;
  END IF;

  v_mutual := v_following AND EXISTS (SELECT 1 FROM follows WHERE follower_id = p_target AND following_id = v_uid);
  RETURN jsonb_build_object('ok', true, 'following', v_following, 'is_mutual', v_mutual);
END;
$$;

-- Obtener la tarjeta pública de un miembro por su nº.
-- Frente: siempre. Reverso: solo si eres tú o si os seguís mutuamente.
CREATE OR REPLACE FUNCTION get_public_card_by_number(p_member_number INTEGER)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_p       profiles%ROWTYPE;
  v_self    BOOLEAN := false;
  v_follow  BOOLEAN := false;
  v_mutual  BOOLEAN := false;
  v_badges  JSONB;
  v_result  JSONB;
BEGIN
  SELECT * INTO v_p FROM profiles WHERE member_number = p_member_number;
  IF NOT FOUND THEN RETURN NULL; END IF;

  v_self := (v_uid = v_p.id);
  IF v_uid IS NOT NULL AND NOT v_self THEN
    v_follow := EXISTS (SELECT 1 FROM follows WHERE follower_id = v_uid AND following_id = v_p.id);
    v_mutual := v_follow AND EXISTS (SELECT 1 FROM follows WHERE follower_id = v_p.id AND following_id = v_uid);
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('key', b.badge_key, 'name', b.name, 'icon', b.icon)
                            ORDER BY ub.earned_at), '[]'::jsonb)
    INTO v_badges
    FROM user_badges ub JOIN badges b ON b.id = ub.badge_id
    WHERE ub.user_id = v_p.id;

  -- FRENTE (público)
  v_result := jsonb_build_object(
    'id',            v_p.id,
    'member_number', v_p.member_number,
    'nombre',        v_p.nombre,
    'apellidos',     v_p.apellidos,
    'nivel',         v_p.nivel,
    'since',         EXTRACT(YEAR FROM v_p.created_at)::int,
    'avatar_url',    v_p.avatar_url,
    'card_config',   v_p.card_config,
    'is_self',       v_self,
    'following',     v_follow,
    'is_mutual',     v_mutual,
    'back_unlocked', (v_self OR v_mutual)
  );

  -- REVERSO (solo si self o mutuo)
  IF v_self OR v_mutual THEN
    v_result := v_result || jsonb_build_object('back', jsonb_build_object(
      'message',   v_p.card_message,
      'instagram', v_p.instagram,
      'tiktok',    v_p.tiktok,
      'badges',    v_badges,
      'credits',   CASE WHEN v_self THEN v_p.credits ELSE NULL END
    ));
  END IF;

  RETURN v_result;
END;
$$;

-- grant_credits NO debe ser llamable por usuarios normales
REVOKE EXECUTE ON FUNCTION grant_credits(UUID, INTEGER, TEXT) FROM PUBLIC, anon, authenticated;

-- ──────────────────────────────────────────────────────────
-- 5. TRIGGER: bonus inicial + insignia Fundador
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION on_profile_after()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_founder BIGINT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO credit_ledger(user_id, delta, reason)
      VALUES (NEW.id, COALESCE(NEW.credits, 0), 'bonus_inicial');
  END IF;

  IF NEW.member_number IS NOT NULL AND NEW.member_number <= 100 THEN
    SELECT id INTO v_founder FROM badges WHERE badge_key = 'founder';
    IF v_founder IS NOT NULL THEN
      INSERT INTO user_badges(user_id, badge_id) VALUES (NEW.id, v_founder) ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profile_after ON profiles;
CREATE TRIGGER trg_profile_after
  AFTER INSERT OR UPDATE OF member_number ON profiles
  FOR EACH ROW EXECUTE FUNCTION on_profile_after();

-- ──────────────────────────────────────────────────────────
-- 6. SEGURIDAD: RLS + permisos a nivel de columna
-- ──────────────────────────────────────────────────────────

-- IMPORTANTE: impedir que un usuario modifique directamente credits / card_config /
-- member_number. Solo puede tocar columnas "inofensivas" por UPDATE/INSERT directo;
-- el resto se cambia exclusivamente vía las funciones SECURITY DEFINER de arriba.
REVOKE INSERT, UPDATE ON profiles FROM anon, authenticated;
GRANT  INSERT (id, nombre, apellidos, nivel)      ON profiles TO authenticated;
GRANT  UPDATE (nombre, apellidos, avatar_url)     ON profiles TO authenticated;

-- Catálogos: lectura pública
ALTER TABLE customization_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS items_select_all ON customization_items;
CREATE POLICY items_select_all ON customization_items FOR SELECT USING (true);

ALTER TABLE badges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS badges_select_all ON badges;
CREATE POLICY badges_select_all ON badges FOR SELECT USING (true);

-- Inventario / ledger / insignias del usuario: solo lectura de lo propio
ALTER TABLE user_unlocks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS unlocks_select_own ON user_unlocks;
CREATE POLICY unlocks_select_own ON user_unlocks FOR SELECT USING (auth.uid() = user_id);

ALTER TABLE credit_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ledger_select_own ON credit_ledger;
CREATE POLICY ledger_select_own ON credit_ledger FOR SELECT USING (auth.uid() = user_id);

ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_badges_select_own ON user_badges;
CREATE POLICY user_badges_select_own ON user_badges FOR SELECT USING (auth.uid() = user_id);

-- Follows: el usuario ve las relaciones en las que participa (gestión vía toggle_follow)
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS follows_select_involved ON follows;
CREATE POLICY follows_select_involved ON follows FOR SELECT
  USING (auth.uid() = follower_id OR auth.uid() = following_id);

-- ──────────────────────────────────────────────────────────
-- 7. STORAGE: bucket de avatares (lectura pública, escritura del dueño)
-- ──────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS avatars_read        ON storage.objects;
DROP POLICY IF EXISTS avatars_insert_own  ON storage.objects;
DROP POLICY IF EXISTS avatars_update_own  ON storage.objects;
DROP POLICY IF EXISTS avatars_delete_own  ON storage.objects;

CREATE POLICY avatars_read ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');
CREATE POLICY avatars_insert_own ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY avatars_update_own ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY avatars_delete_own ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

-- ============================================================
-- CONCEDER CRÉDITOS A MANO (ejemplo, ejecútalo cuando quieras):
--   SELECT grant_credits('UUID_DEL_USUARIO', 200, 'regalo_fundador');
-- VER EL CATÁLOGO:
--   SELECT item_key, name, category, cost, is_premium FROM customization_items ORDER BY category, sort;
-- ============================================================
