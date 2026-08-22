CREATE OR REPLACE FUNCTION public.create_video(p_title text, p_description text DEFAULT '', p_category_id text DEFAULT NULL, p_video_url text DEFAULT '', p_thumbnail_url text DEFAULT '', p_duration integer DEFAULT 0, p_visibility text DEFAULT 'public')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid(); v_user_role TEXT; v_new_video_id UUID := gen_random_uuid();
  v_trimmed_title TEXT := TRIM(COALESCE(p_title, '')); v_trimmed_url TEXT := TRIM(COALESCE(p_video_url, ''));
  v_visibility TEXT := LOWER(TRIM(COALESCE(p_visibility, 'public')));
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması gereklidir.'); END IF;
  SELECT role INTO v_user_role FROM public.profiles WHERE id = v_user_id;
  IF v_user_role IS NULL OR v_user_role NOT IN ('parent', 'publisher', 'admin') THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Video oluşturma yetkiniz bulunmamaktadır.'); END IF;
  IF LENGTH(v_trimmed_title) = 0 OR LENGTH(v_trimmed_title) > 255 THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Video başlığı 1-255 karakter olmalıdır.'); END IF;
  IF v_trimmed_url !~* '^https?://(www\.)?(youtube\.com/(watch\?v=|shorts/|embed/)|youtu\.be/)[A-Za-z0-9_-]{11}([?&].*)?$' THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Yalnızca geçerli YouTube video bağlantıları kabul edilir.'); END IF;
  IF p_category_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.categories WHERE id = p_category_id) THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Geçerli bir kategori seçilmelidir.'); END IF;
  IF COALESCE(p_duration, 0) < 0 THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Süre negatif olamaz.'); END IF;
  IF v_visibility NOT IN ('public', 'unlisted', 'private') THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Geçersiz görünürlük değeri.'); END IF;
  INSERT INTO public.videos (id, owner_id, title, description, category_id, video_url, thumbnail_url, duration, visibility, is_deleted, created_at, updated_at)
  VALUES (v_new_video_id, v_user_id, v_trimmed_title, COALESCE(p_description, ''), p_category_id, v_trimmed_url, NULLIF(TRIM(COALESCE(p_thumbnail_url, '')), ''), COALESCE(p_duration, 0), v_visibility, FALSE, NOW(), NOW());
  RETURN jsonb_build_object('success', TRUE, 'video_id', v_new_video_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_video(p_video_id UUID, p_title text DEFAULT NULL, p_description text DEFAULT NULL, p_category_id text DEFAULT NULL, p_video_url text DEFAULT NULL, p_thumbnail_url text DEFAULT NULL, p_duration integer DEFAULT NULL, p_visibility text DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid(); v_user_role TEXT; v_existing public.videos%ROWTYPE;
  v_trimmed_title TEXT; v_trimmed_url TEXT; v_visibility TEXT;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması gereklidir.'); END IF;
  SELECT * INTO v_existing FROM public.videos WHERE id = p_video_id;
  IF v_existing.id IS NULL OR v_existing.is_deleted IS TRUE THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Video bulunamadı veya silinmiş.'); END IF;
  SELECT role INTO v_user_role FROM public.profiles WHERE id = v_user_id;
  IF v_user_role IS NULL OR v_user_role NOT IN ('parent', 'publisher', 'admin') THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Video düzenleme yetkiniz bulunmamaktadır.'); END IF;
  IF v_user_role <> 'admin' AND v_existing.owner_id <> v_user_id THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Yalnızca kendi videolarınızı düzenleyebilirsiniz.'); END IF;
  IF p_title IS NOT NULL THEN
    v_trimmed_title := TRIM(p_title);
    IF LENGTH(v_trimmed_title) = 0 OR LENGTH(v_trimmed_title) > 255 THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Video başlığı 1-255 karakter olmalıdır.'); END IF;
  ELSE v_trimmed_title := v_existing.title; END IF;
  IF p_video_url IS NOT NULL THEN
    v_trimmed_url := TRIM(p_video_url);
    IF v_trimmed_url !~* '^https?://(www\.)?(youtube\.com/(watch\?v=|shorts/|embed/)|youtu\.be/)[A-Za-z0-9_-]{11}([?&].*)?$' THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Yalnızca geçerli YouTube video bağlantıları kabul edilir.'); END IF;
  ELSE v_trimmed_url := v_existing.video_url; END IF;
  IF p_category_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.categories WHERE id = p_category_id) THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Geçerli bir kategori seçilmelidir.'); END IF;
  IF p_duration IS NOT NULL AND p_duration < 0 THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Süre negatif olamaz.'); END IF;
  IF p_visibility IS NOT NULL THEN
    v_visibility := LOWER(TRIM(p_visibility));
    IF v_visibility NOT IN ('public', 'unlisted', 'private') THEN RETURN jsonb_build_object('success', FALSE, 'error', 'Geçersiz görünürlük değeri.'); END IF;
  ELSE v_visibility := v_existing.visibility; END IF;
  UPDATE public.videos SET title=v_trimmed_title,description=COALESCE(p_description,v_existing.description),category_id=COALESCE(p_category_id,v_existing.category_id),video_url=v_trimmed_url,thumbnail_url=CASE WHEN p_thumbnail_url IS NULL THEN v_existing.thumbnail_url ELSE NULLIF(TRIM(p_thumbnail_url),'') END,duration=COALESCE(p_duration,v_existing.duration),visibility=v_visibility,updated_at=NOW() WHERE id=p_video_id;
  RETURN jsonb_build_object('success', TRUE);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_video(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_video(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.update_video(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_video(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT) TO authenticated;
