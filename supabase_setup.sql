-- ============================================================
-- PADELROOKIES — Setup de base de datos en Supabase
-- Ejecuta este SQL en: Supabase > SQL Editor > New query
-- ============================================================

-- 1. Tabla de perfiles de miembros
CREATE TABLE IF NOT EXISTS profiles (
  id               UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre           TEXT NOT NULL,
  apellidos        TEXT NOT NULL,
  nivel            TEXT NOT NULL DEFAULT 'Rookie',
  member_number    INTEGER UNIQUE,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Secuencia que empieza en 101 (0001–0100 reservados para asignación manual)
CREATE SEQUENCE IF NOT EXISTS member_number_seq START WITH 101 INCREMENT BY 1;

-- 3. Función que asigna el siguiente número de miembro automáticamente
CREATE OR REPLACE FUNCTION assign_member_number()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.member_number IS NULL THEN
    NEW.member_number := nextval('member_number_seq');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Trigger que ejecuta la función al insertar un nuevo perfil
DROP TRIGGER IF EXISTS trg_assign_member_number ON profiles;
CREATE TRIGGER trg_assign_member_number
  BEFORE INSERT ON profiles
  FOR EACH ROW EXECUTE FUNCTION assign_member_number();

-- 5. Seguridad: Row Level Security (RLS)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Cada usuario solo puede leer/editar su propio perfil
CREATE POLICY "perfil_propio_select" ON profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "perfil_propio_insert" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "perfil_propio_update" ON profiles
  FOR UPDATE USING (auth.uid() = id);

-- ============================================================
-- MIEMBROS FUNDADORES (0001–0100)
-- Para asignarte el nº 0001, ejecuta esto después de crear
-- tu cuenta desde la web (sustituye TU_USER_ID por el UUID
-- que aparece en Supabase > Authentication > Users):
--
-- UPDATE profiles SET member_number = 1 WHERE id = 'TU_USER_ID';
-- ============================================================
