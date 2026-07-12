-- ============================================================
-- PADELROOKIES — Endurecimiento de seguridad (APLICADO el 2026-07-07
-- como migración "security_hardening_community" vía MCP).
-- Este archivo documenta lo que ya está en producción; es idempotente
-- salvo los ADD CONSTRAINT (fallarían si ya existen).
-- Requiere: supabase_setup.sql + supabase_card.sql aplicados antes.
-- ============================================================

-- 1. Revocar privilegios de escritura sobrantes (defensa en profundidad;
--    RLS ya bloquea estas operaciones, pero los grants por defecto sobran)
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE
  public.badges, public.credit_ledger, public.customization_items,
  public.follows, public.user_badges, public.user_unlocks
FROM anon, authenticated;

REVOKE DELETE, TRUNCATE ON TABLE public.profiles FROM anon, authenticated;

-- 2. El cliente ya no puede fijar `nivel` al crear el perfil:
--    se recorta el grant de INSERT (el DEFAULT 'Rookie' se aplica solo).
--    Los INSERT del cliente (unete.html / perfil.html) ya no envían nivel.
REVOKE INSERT ON TABLE public.profiles FROM authenticated;
GRANT INSERT (id, nombre, apellidos) ON TABLE public.profiles TO authenticated;

-- 3. Límites de longitud y valores válidos (anti-abuso vía API directa)
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_nombre_len    CHECK (char_length(nombre) BETWEEN 1 AND 60),
  ADD CONSTRAINT profiles_apellidos_len CHECK (char_length(apellidos) <= 80),
  ADD CONSTRAINT profiles_message_len   CHECK (card_message IS NULL OR char_length(card_message) <= 200),
  ADD CONSTRAINT profiles_instagram_len CHECK (instagram IS NULL OR char_length(instagram) <= 40),
  ADD CONSTRAINT profiles_tiktok_len    CHECK (tiktok IS NULL OR char_length(tiktok) <= 40),
  ADD CONSTRAINT profiles_avatar_len    CHECK (avatar_url IS NULL OR char_length(avatar_url) <= 500),
  ADD CONSTRAINT profiles_nivel_valid   CHECK (nivel IN ('Rookie','Advanced Rookie','Rookie Pro'));

-- 4. RPC fuera del rol anónimo (get_public_card_by_number se mantiene
--    pública a propósito: el carnet compartido funciona sin sesión).
--    OJO: hay que revocar de PUBLIC, no solo de anon — el grant por
--    defecto de Postgres llega a través de PUBLIC.
REVOKE EXECUTE ON FUNCTION public.purchase_item(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.save_card_config(jsonb, text, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.toggle_follow(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_item(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_card_config(jsonb, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_follow(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.on_profile_after() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.assign_member_number() FROM PUBLIC, anon, authenticated;

-- 5. search_path fijo en la función de trigger que lo tenía mutable
ALTER FUNCTION public.assign_member_number() SET search_path = public;

-- 6. Storage de avatares: sin listado público (las URLs públicas directas
--    siguen funcionando) + solo imágenes de máximo 2MB
DROP POLICY IF EXISTS avatars_read ON storage.objects;
UPDATE storage.buckets
  SET file_size_limit = 2097152,
      allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','image/gif']
  WHERE id = 'avatars';

-- ============================================================
-- PENDIENTE EN EL PANEL DE SUPABASE (no se puede hacer por SQL):
--  · Authentication > Attack Protection: activar CAPTCHA (Cloudflare
--    Turnstile) para el registro — recomendado antes de abrir la
--    comunidad a mucha gente.
--  · Authentication > Passwords: activar "Leaked password protection"
--    (puede requerir plan Pro).
--  · Mantener la confirmación por email ACTIVADA.
-- ============================================================
