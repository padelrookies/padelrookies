-- ============================================================
-- PADELROOKIES — Comunidad: publicar puntazos (enlaces de vídeo)
-- Ejecuta este SQL en: Supabase > SQL Editor > New query
-- Requiere: supabase_setup.sql + supabase_card.sql + supabase_hardening.sql
-- aplicados antes. Sigue el mismo patrón de endurecimiento: cero
-- escrituras directas del cliente; todo vía RPC SECURITY DEFINER
-- con search_path fijo; REVOKE de PUBLIC/anon + GRANT explícito.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- 1. TABLA
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS community_posts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  platform    TEXT NOT NULL CHECK (platform IN ('instagram','tiktok','youtube')),
  url         TEXT NOT NULL CHECK (char_length(url) <= 300),
  video_id    TEXT NOT NULL CHECK (char_length(video_id) <= 40),
  title       TEXT NOT NULL CHECK (char_length(title) BETWEEN 3 AND 80),
  is_hidden   BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Anti-duplicados: el mismo vídeo no se puede publicar dos veces
CREATE UNIQUE INDEX IF NOT EXISTS community_posts_platform_video_uq
  ON community_posts (platform, video_id);
-- Feed público (índice parcial: solo posts visibles)
CREATE INDEX IF NOT EXISTS community_posts_feed_idx
  ON community_posts (created_at DESC) WHERE NOT is_hidden;
-- Rate-limit por usuario + cubre la FK sin índice
CREATE INDEX IF NOT EXISTS community_posts_rate_idx
  ON community_posts (user_id, created_at DESC);

-- ──────────────────────────────────────────────────────────
-- 2. RLS + GRANTS MÍNIMOS
-- ──────────────────────────────────────────────────────────
ALTER TABLE community_posts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE community_posts FROM PUBLIC, anon, authenticated;

-- Única política: el autor puede leer sus propios posts (incluidos
-- los ocultos). El feed público real va por RPC, no por SELECT directo.
GRANT SELECT ON TABLE community_posts TO authenticated;
DROP POLICY IF EXISTS community_posts_select_own ON community_posts;
CREATE POLICY community_posts_select_own ON community_posts
  FOR SELECT USING (auth.uid() = user_id);

-- ──────────────────────────────────────────────────────────
-- 3. RPC: publicar (solo usuarios autenticados)
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION submit_community_post(p_url TEXT, p_title TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid      UUID := auth.uid();
  v_url      TEXT;
  v_title    TEXT;
  v_platform TEXT;
  v_video_id TEXT;
  v_ig_type  TEXT;
  v_count    INTEGER;
  v_post     community_posts%ROWTYPE;
  m          TEXT[];
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Necesitas iniciar sesión para publicar.';
  END IF;

  v_title := trim(coalesce(p_title, ''));
  IF char_length(v_title) < 3 OR char_length(v_title) > 80 THEN
    RAISE EXCEPTION 'El título debe tener entre 3 y 80 caracteres.';
  END IF;

  v_url := trim(coalesce(p_url, ''));
  IF v_url = '' OR char_length(v_url) > 300 THEN
    RAISE EXCEPTION 'URL no válida.';
  END IF;
  IF v_url !~* '^https?://' THEN
    v_url := 'https://' || v_url;
  END IF;

  -- YouTube: watch?v=
  m := regexp_match(v_url,
    '^https?://(?:www\.|m\.)?youtube\.com/watch\?(?:[^#]*&)?v=([A-Za-z0-9_-]{11})(?:[&#].*)?$', 'i');
  IF m IS NOT NULL THEN
    v_platform := 'youtube'; v_video_id := m[1];
    v_url := 'https://www.youtube.com/watch?v=' || v_video_id;
  END IF;

  -- YouTube: youtu.be/
  IF v_platform IS NULL THEN
    m := regexp_match(v_url,
      '^https?://youtu\.be/([A-Za-z0-9_-]{11})(?:[?#].*)?$', 'i');
    IF m IS NOT NULL THEN
      v_platform := 'youtube'; v_video_id := m[1];
      v_url := 'https://www.youtube.com/watch?v=' || v_video_id;
    END IF;
  END IF;

  -- YouTube: shorts/
  IF v_platform IS NULL THEN
    m := regexp_match(v_url,
      '^https?://(?:www\.|m\.)?youtube\.com/shorts/([A-Za-z0-9_-]{11})(?:[?/#].*)?$', 'i');
    IF m IS NOT NULL THEN
      v_platform := 'youtube'; v_video_id := m[1];
      v_url := 'https://www.youtube.com/shorts/' || v_video_id;
    END IF;
  END IF;

  -- Instagram: /reel/, /reels/ o /p/
  IF v_platform IS NULL THEN
    m := regexp_match(v_url,
      '^https?://(?:www\.)?instagram\.com/(reel|reels|p)/([A-Za-z0-9_-]{5,20})/?(?:[?#].*)?$', 'i');
    IF m IS NOT NULL THEN
      v_platform := 'instagram';
      v_ig_type  := CASE WHEN lower(m[1]) = 'p' THEN 'p' ELSE 'reel' END;
      v_video_id := m[2];
      v_url := 'https://www.instagram.com/' || v_ig_type || '/' || v_video_id || '/';
    END IF;
  END IF;

  -- TikTok: /@usuario/video/ID (los enlaces cortos vm.tiktok.com se rechazan)
  IF v_platform IS NULL THEN
    m := regexp_match(v_url,
      '^https?://(?:www\.)?tiktok\.com/(@[A-Za-z0-9_.]{1,30})/video/([0-9]{5,25})(?:[?#].*)?$', 'i');
    IF m IS NOT NULL THEN
      v_platform := 'tiktok'; v_video_id := m[2];
      v_url := 'https://www.tiktok.com/' || m[1] || '/video/' || v_video_id;
    END IF;
  END IF;

  IF v_platform IS NULL THEN
    RAISE EXCEPTION 'Solo se admiten enlaces de vídeo de YouTube, Instagram (reel o post) o TikTok.';
  END IF;

  -- Rate limit: máximo 3 posts por ventana móvil de 24h
  SELECT count(*) INTO v_count FROM community_posts
   WHERE user_id = v_uid AND created_at > now() - interval '24 hours';
  IF v_count >= 3 THEN
    RAISE EXCEPTION 'Has alcanzado el límite de 3 publicaciones por día. Vuelve mañana.';
  END IF;

  BEGIN
    INSERT INTO community_posts (user_id, platform, url, video_id, title)
    VALUES (v_uid, v_platform, v_url, v_video_id, v_title)
    RETURNING * INTO v_post;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Ese vídeo ya está publicado en la comunidad.';
  END;

  RETURN jsonb_build_object(
    'id', v_post.id, 'platform', v_post.platform, 'url', v_post.url,
    'video_id', v_post.video_id, 'title', v_post.title,
    'created_at', v_post.created_at, 'is_own', true
  );
END;
$$;

-- ──────────────────────────────────────────────────────────
-- 4. RPC: feed público (lectura, anon + authenticated)
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_community_feed(
  p_limit INTEGER DEFAULT 12, p_offset INTEGER DEFAULT 0)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_limit  INTEGER := LEAST(GREATEST(coalesce(p_limit, 12), 1), 24);
  v_offset INTEGER := LEAST(GREATEST(coalesce(p_offset, 0), 0), 5000);
  v_posts  JSONB;
BEGIN
  SELECT coalesce(jsonb_agg(post), '[]'::jsonb) INTO v_posts
  FROM (
    SELECT jsonb_build_object(
      'id', p.id, 'platform', p.platform, 'url', p.url,
      'video_id', p.video_id, 'title', p.title, 'created_at', p.created_at,
      'author_name', pr.nombre,
      'member_number', pr.member_number,
      'avatar_url', pr.avatar_url,
      'is_own', (auth.uid() IS NOT NULL AND p.user_id = auth.uid())
    ) AS post
    FROM community_posts p
    JOIN profiles pr ON pr.id = p.user_id
    WHERE NOT p.is_hidden
    ORDER BY p.created_at DESC
    LIMIT v_limit OFFSET v_offset
  ) t;
  RETURN v_posts;
END;
$$;

-- ──────────────────────────────────────────────────────────
-- 5. RPC: borrar post propio (solo autenticados, solo lo suyo)
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION delete_community_post(p_post_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Necesitas iniciar sesión.';
  END IF;
  DELETE FROM community_posts WHERE id = p_post_id AND user_id = v_uid;
  RETURN FOUND;
END;
$$;

-- ──────────────────────────────────────────────────────────
-- 6. GRANTS / REVOKES (PUBLIC recibe EXECUTE por defecto al crear
--    una función — hay que revocarlo siempre explícitamente)
-- ──────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION submit_community_post(TEXT, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION submit_community_post(TEXT, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION delete_community_post(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION delete_community_post(UUID) TO authenticated;

-- El feed es público A PROPÓSITO (igual que get_public_card_by_number)
REVOKE EXECUTE ON FUNCTION get_community_feed(INTEGER, INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION get_community_feed(INTEGER, INTEGER) TO anon, authenticated;

-- ============================================================
-- MODERACIÓN (sin panel de admin en esta fase):
-- el founder oculta/borra manualmente desde el SQL editor
-- (service role, ignora RLS):
--   UPDATE community_posts SET is_hidden = true WHERE id = '...';
--   DELETE FROM community_posts WHERE id = '...';
-- Fase futura: RPC admin_hide_post gated por member_number = 1.
-- ============================================================
