-- ====================================================================
-- Ahmet Egemen'in Köşesi - Schema & Security Reconciliation Migration
-- Timestamp: 20260811000000
-- Target: Safely reconciles live Supabase database with schema contract
-- ====================================================================

-- --------------------------------------------------------------------
-- PHASE 1: EXTENSIONS & MISSING TABLES / COLUMNS
-- --------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Ensure profiles table exists
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  first_name TEXT,
  last_name TEXT,
  avatar_path TEXT,
  role TEXT NOT NULL DEFAULT 'child' CHECK (role IN ('child', 'parent', 'publisher', 'admin')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
UPDATE public.profiles SET role = 'child' WHERE role = 'MEMBER';
UPDATE public.profiles SET role = 'publisher' WHERE role = 'PUBLISHER';
UPDATE public.profiles SET role = 'admin' WHERE role = 'ADMIN';
UPDATE public.profiles SET role = 'child' WHERE role NOT IN ('child', 'parent', 'publisher', 'admin');
ALTER TABLE public.profiles ALTER COLUMN role SET DEFAULT 'child';
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK (role IN ('child', 'parent', 'publisher', 'admin'));

-- Ensure categories table exists
CREATE TABLE IF NOT EXISTS public.categories (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  icon_name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed / Sync Categories
INSERT INTO public.categories (id, title, slug, icon_name)
VALUES
  ('cat-egitim', 'Eğitici Videolar', 'egitici', 'GraduationCap'),
  ('cat-masal', 'Masallar', 'masallar', 'BookOpen'),
  ('cat-cizgifilm', 'Çizgi Filmler', 'cizgi-filmler', 'Tv'),
  ('cat-hayvan', 'Hayvan Videoları', 'hayvanlar', 'Dog'),
  ('cat-doga', 'Doğa Videoları', 'doga', 'Trees'),
  ('cat-muzik', 'Müzikler ve Şarkılar', 'muzik', 'Music'),
  ('cat-fotograf', 'Fotoğraf Anıları', 'fotograf-anilari', 'Camera')
ON CONFLICT (id) DO UPDATE SET
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  icon_name = EXCLUDED.icon_name;

-- Ensure videos table exists
CREATE TABLE IF NOT EXISTS public.videos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  video_url TEXT NOT NULL,
  thumbnail_url TEXT,
  category_id TEXT REFERENCES public.categories(id) ON DELETE SET NULL,
  duration INT NOT NULL DEFAULT 0,
  visibility TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'private', 'unlisted')),
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add missing view_count column to videos table if absent
ALTER TABLE public.videos ADD COLUMN IF NOT EXISTS view_count INT NOT NULL DEFAULT 0;

-- Ensure watch_history table exists
CREATE TABLE IF NOT EXISTS public.watch_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  video_id UUID NOT NULL REFERENCES public.videos(id) ON DELETE CASCADE,
  progress_seconds INT NOT NULL DEFAULT 0,
  completed BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT watch_history_user_video_unique UNIQUE (user_id, video_id)
);

-- Ensure favorites table exists
CREATE TABLE IF NOT EXISTS public.favorites (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  video_id UUID NOT NULL REFERENCES public.videos(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT favorites_user_video_unique UNIQUE (user_id, video_id)
);

-- Ensure parent_settings table exists
CREATE TABLE IF NOT EXISTS public.parent_settings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
  pin_hash TEXT,
  failed_attempts INT NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ,
  daily_time_limit_minutes INT,
  allowed_categories TEXT[],
  bedtime_start TEXT,
  bedtime_end TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create missing video_view_cooldowns table
CREATE TABLE IF NOT EXISTS public.video_view_cooldowns (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  video_id UUID NOT NULL REFERENCES public.videos(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  last_counted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT video_view_cooldowns_video_user_unique UNIQUE (video_id, user_id)
);

-- --------------------------------------------------------------------
-- PHASE 2: INDEXES
-- --------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_videos_category_id ON public.videos(category_id);
CREATE INDEX IF NOT EXISTS idx_videos_owner_id ON public.videos(owner_id);
CREATE INDEX IF NOT EXISTS idx_videos_is_deleted ON public.videos(is_deleted);
CREATE INDEX IF NOT EXISTS idx_watch_history_user_id ON public.watch_history(user_id);
CREATE INDEX IF NOT EXISTS idx_favorites_user_id ON public.favorites(user_id);
CREATE INDEX IF NOT EXISTS idx_video_view_cooldowns_user_video ON public.video_view_cooldowns(user_id, video_id);

-- --------------------------------------------------------------------
-- PHASE 3: ROW LEVEL SECURITY (RLS) POLICIES
-- --------------------------------------------------------------------

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.videos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.watch_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parent_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_view_cooldowns ENABLE ROW LEVEL SECURITY;

-- profiles policies
DROP POLICY IF EXISTS "Public profiles are viewable by authenticated users" ON public.profiles;
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
CREATE POLICY "Users can view their own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
CREATE POLICY "Users can insert their own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- categories policy
DROP POLICY IF EXISTS "Categories are readable by everyone" ON public.categories;
CREATE POLICY "Categories are readable by everyone"
  ON public.categories FOR SELECT
  USING (true);

-- videos policies
DROP POLICY IF EXISTS "Public non-deleted videos readable by everyone" ON public.videos;
DROP POLICY IF EXISTS "Videos viewable by public or owner or admin" ON public.videos;
CREATE POLICY "Videos viewable by public or owner or admin"
  ON public.videos FOR SELECT
  USING (
    (is_deleted = false AND visibility = 'public') OR
    (auth.uid() = owner_id) OR
    (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'))
  );

DROP POLICY IF EXISTS "Publishers and Admins can insert videos" ON public.videos;
CREATE POLICY "Publishers and Admins can insert videos"
  ON public.videos FOR INSERT
  WITH CHECK (
    auth.uid() = owner_id AND
    EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role IN ('publisher', 'admin'))
  );

DROP POLICY IF EXISTS "Owners and Admins can update videos" ON public.videos;
DROP POLICY IF EXISTS "Publishers and Admins can update their own videos" ON public.videos;
CREATE POLICY "Publishers and Admins can update their own videos"
  ON public.videos FOR UPDATE
  USING (
    (auth.uid() = owner_id AND EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role IN ('publisher', 'admin'))) OR
    EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
  );

-- watch_history policies
DROP POLICY IF EXISTS "Users can view their own watch history" ON public.watch_history;
CREATE POLICY "Users can view their own watch history"
  ON public.watch_history FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own watch history" ON public.watch_history;
CREATE POLICY "Users can insert their own watch history"
  ON public.watch_history FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own watch history" ON public.watch_history;
CREATE POLICY "Users can update their own watch history"
  ON public.watch_history FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- favorites policies
DROP POLICY IF EXISTS "Users can view their own favorites" ON public.favorites;
CREATE POLICY "Users can view their own favorites"
  ON public.favorites FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can manage their own favorites" ON public.favorites;
CREATE POLICY "Users can manage their own favorites"
  ON public.favorites FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Note: parent_settings and video_view_cooldowns have RLS enabled with NO DIRECT CLIENT POLICIES.
-- Access to parent_settings and cooldowns is restricted exclusively to SECURITY DEFINER RPC functions.

-- --------------------------------------------------------------------
-- PHASE 4: SECURITY DEFINER RPC FUNCTIONS
-- --------------------------------------------------------------------

-- 4.1 get_my_role()
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN 'guest';
  END IF;

  SELECT role INTO v_role
  FROM public.profiles
  WHERE id = auth.uid();

  RETURN COALESCE(v_role, 'guest');
END;
$$;

-- 4.2 get_my_parent_settings_status()
CREATE OR REPLACE FUNCTION public.get_my_parent_settings_status()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_user_role TEXT;
  v_rec RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Oturum açılmadı.';
  END IF;

  -- Authorization check: ONLY parent or admin can access parent settings
  SELECT role INTO v_user_role FROM public.profiles WHERE id = v_user_id;
  IF v_user_role NOT IN ('parent', 'admin') THEN
    RAISE EXCEPTION 'Ebeveyn paneline erişim yetkiniz bulunmamaktadır.';
  END IF;

  SELECT id, user_id, failed_attempts, locked_until, daily_time_limit_minutes, allowed_categories, bedtime_start, bedtime_end, created_at, updated_at
  INTO v_rec
  FROM public.parent_settings
  WHERE user_id = v_user_id;

  IF NOT FOUND THEN
    INSERT INTO public.parent_settings (user_id)
    VALUES (v_user_id)
    RETURNING id, user_id, failed_attempts, locked_until, daily_time_limit_minutes, allowed_categories, bedtime_start, bedtime_end, created_at, updated_at
    INTO v_rec;
  END IF;

  RETURN jsonb_build_object(
    'id', v_rec.id,
    'user_id', v_rec.user_id,
    'failed_attempts', v_rec.failed_attempts,
    'locked_until', v_rec.locked_until,
    'is_locked', (v_rec.locked_until IS NOT NULL AND v_rec.locked_until > NOW()),
    'daily_time_limit_minutes', v_rec.daily_time_limit_minutes,
    'allowed_categories', v_rec.allowed_categories,
    'bedtime_start', v_rec.bedtime_start,
    'bedtime_end', v_rec.bedtime_end,
    'created_at', v_rec.created_at,
    'updated_at', v_rec.updated_at
  );
END;
$$;

-- 4.3 verify_parent_pin(p_pin TEXT)
CREATE OR REPLACE FUNCTION public.verify_parent_pin(p_pin TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_pin_hash TEXT;
  v_failed INT;
  v_locked_until TIMESTAMPTZ;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT pin_hash, failed_attempts, locked_until
  INTO v_pin_hash, v_failed, v_locked_until
  FROM public.parent_settings
  WHERE user_id = v_user_id;

  -- Check lockout
  IF v_locked_until IS NOT NULL AND v_locked_until > NOW() THEN
    RAISE EXCEPTION 'Ebeveyn kilidi geçici olarak kilitlendi. Lütfen bekleyin.';
  END IF;

  -- If PIN unset or empty
  IF v_pin_hash IS NULL OR v_pin_hash = '' THEN
    RETURN TRUE;
  END IF;

  -- Verify PIN
  IF v_pin_hash = crypt(p_pin, v_pin_hash) THEN
    -- Correct PIN: reset counters
    UPDATE public.parent_settings
    SET failed_attempts = 0, locked_until = NULL, updated_at = NOW()
    WHERE user_id = v_user_id;
    RETURN TRUE;
  ELSE
    -- Incorrect PIN: increment counter
    v_failed := COALESCE(v_failed, 0) + 1;
    IF v_failed >= 5 THEN
      v_locked_until := NOW() + INTERVAL '15 minutes';
      UPDATE public.parent_settings
      SET failed_attempts = v_failed, locked_until = v_locked_until, updated_at = NOW()
      WHERE user_id = v_user_id;
      RETURN FALSE;
    ELSE
      UPDATE public.parent_settings
      SET failed_attempts = v_failed, updated_at = NOW()
      WHERE user_id = v_user_id;
      RETURN FALSE;
    END IF;
  END IF;
END;
$$;

-- 4.4 update_parent_pin(p_new_pin TEXT, p_old_pin TEXT DEFAULT NULL)
CREATE OR REPLACE FUNCTION public.update_parent_pin(p_new_pin TEXT, p_old_pin TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_user_role TEXT;
  v_current_hash TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Authorization check
  SELECT role INTO v_user_role FROM public.profiles WHERE id = v_user_id;
  IF v_user_role NOT IN ('parent', 'admin') THEN
    RAISE EXCEPTION 'Sadece ebeveyn veya admin PIN değiştirebilir.';
  END IF;

  SELECT pin_hash INTO v_current_hash
  FROM public.parent_settings
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_current_hash IS NOT NULL AND v_current_hash != '' THEN
    IF p_old_pin IS NULL OR crypt(p_old_pin, v_current_hash) != v_current_hash THEN
      RAISE EXCEPTION 'Mevcut PIN doğrulaması başarısız.';
    END IF;
  END IF;

  UPDATE public.parent_settings
  SET pin_hash = crypt(p_new_pin, gen_salt('bf')),
      failed_attempts = 0,
      locked_until = NULL,
      updated_at = NOW()
  WHERE user_id = v_user_id;

  IF NOT FOUND THEN
    INSERT INTO public.parent_settings (user_id, pin_hash)
    VALUES (v_user_id, crypt(p_new_pin, gen_salt('bf')));
  END IF;

  RETURN TRUE;
END;
$$;

-- 4.5 update_parent_settings(...)
CREATE OR REPLACE FUNCTION public.update_parent_settings(
  p_daily_time_limit_minutes INT DEFAULT NULL,
  p_allowed_categories TEXT[] DEFAULT NULL,
  p_bedtime_start TEXT DEFAULT NULL,
  p_bedtime_end TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_user_role TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Authorization check
  SELECT role INTO v_user_role FROM public.profiles WHERE id = v_user_id;
  IF v_user_role NOT IN ('parent', 'admin') THEN
    RAISE EXCEPTION 'Sadece ebeveyn veya admin ayarları değiştirebilir.';
  END IF;

  UPDATE public.parent_settings
  SET daily_time_limit_minutes = p_daily_time_limit_minutes,
      allowed_categories = p_allowed_categories,
      bedtime_start = p_bedtime_start,
      bedtime_end = p_bedtime_end,
      updated_at = NOW()
  WHERE user_id = v_user_id;

  IF NOT FOUND THEN
    INSERT INTO public.parent_settings (
      user_id,
      daily_time_limit_minutes,
      allowed_categories,
      bedtime_start,
      bedtime_end
    ) VALUES (
      v_user_id,
      p_daily_time_limit_minutes,
      p_allowed_categories,
      p_bedtime_start,
      p_bedtime_end
    );
  END IF;

  RETURN TRUE;
END;
$$;

-- 4.6 increment_video_view_count(p_video_id UUID)
CREATE OR REPLACE FUNCTION public.increment_video_view_count(p_video_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_video_exists BOOLEAN;
  v_should_increment BOOLEAN := FALSE;
BEGIN
  -- DENY unauthenticated (anon) users completely
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  -- Verify video exists and is not soft-deleted
  SELECT EXISTS (
    SELECT 1 FROM public.videos WHERE id = p_video_id AND is_deleted = false
  ) INTO v_video_exists;

  IF NOT v_video_exists THEN
    RETURN;
  END IF;

  -- Concurrency-safe cooldown logic using video_view_cooldowns (30 minutes window)
  WITH upsert AS (
    INSERT INTO public.video_view_cooldowns (video_id, user_id, last_counted_at, created_at)
    VALUES (p_video_id, v_user_id, NOW(), NOW())
    ON CONFLICT (video_id, user_id)
    DO UPDATE SET last_counted_at = NOW()
    WHERE video_view_cooldowns.last_counted_at <= (NOW() - INTERVAL '30 minutes')
    RETURNING 1
  )
  SELECT EXISTS (SELECT 1 FROM upsert) INTO v_should_increment;

  -- Increment view count ONLY if cooldown allowed it
  IF v_should_increment THEN
    PERFORM set_config('app.allow_view_count_update', 'true', true);
    UPDATE public.videos
    SET view_count = view_count + 1
    WHERE id = p_video_id AND is_deleted = false;
  END IF;
END;
$$;

-- --------------------------------------------------------------------
-- PHASE 5: SECURITY TRIGGERS & TRIGGER FUNCTIONS
-- --------------------------------------------------------------------

-- Prevent direct manipulation of videos.view_count from client queries
CREATE OR REPLACE FUNCTION public.prevent_direct_video_view_count_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.view_count IS DISTINCT FROM OLD.view_count THEN
    IF current_setting('app.allow_view_count_update', true) IS DISTINCT FROM 'true' THEN
      NEW.view_count := OLD.view_count; -- Silently revert unauthorized direct updates to view_count
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_prevent_direct_video_view_count_update ON public.videos;
CREATE TRIGGER tr_prevent_direct_video_view_count_update
  BEFORE UPDATE ON public.videos
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_direct_video_view_count_update();

-- Role escalation prevention trigger
CREATE OR REPLACE FUNCTION public.prevent_profile_role_escalation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.role IN ('publisher', 'admin') THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
      ) THEN
        NEW.role := 'child'; -- Default unprivileged
      END IF;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
      ) THEN
        NEW.role := OLD.role; -- Revert escalation
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_prevent_profile_role_escalation ON public.profiles;
CREATE TRIGGER tr_prevent_profile_role_escalation
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_profile_role_escalation();

-- Soft-delete protection trigger
CREATE OR REPLACE FUNCTION public.prevent_video_undelete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.is_deleted = TRUE AND NEW.is_deleted = FALSE THEN
    RAISE EXCEPTION 'Silinmiş bir video tekrar aktif hale getirilemez.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_prevent_video_undelete ON public.videos;
CREATE TRIGGER tr_prevent_video_undelete
  BEFORE UPDATE ON public.videos
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_video_undelete();

-- --------------------------------------------------------------------
-- PHASE 6: GRANTS & PERMISSIONS
-- --------------------------------------------------------------------

GRANT USAGE ON SCHEMA public TO anon, authenticated;

GRANT SELECT ON public.categories TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.videos TO authenticated;
GRANT SELECT ON public.videos TO anon;
GRANT SELECT, INSERT, UPDATE ON public.watch_history TO authenticated;
GRANT ALL ON public.favorites TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_my_role TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_my_parent_settings_status TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_parent_pin TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_parent_pin TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_parent_settings TO authenticated;

REVOKE EXECUTE ON FUNCTION public.increment_video_view_count(UUID) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_video_view_count(UUID) TO authenticated;
