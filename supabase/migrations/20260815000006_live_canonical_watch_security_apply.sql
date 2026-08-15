-- ============================================================================
-- AHMET EGEMEN'İN KÖŞESİ
-- Migration: 20260815000006_live_canonical_watch_security_apply.sql
-- Purpose: Consolidated live reconciliation of canonical watch/security objects.
-- NOTE: 0005 is already applied live. This migration applies the effective
--       0001-0004 watch/security end-state without replaying historical data.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------------
-- 1. parent_children
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.parent_children (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  parent_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  child_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='parent_children_unique') THEN
    ALTER TABLE public.parent_children ADD CONSTRAINT parent_children_unique UNIQUE (parent_id, child_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='parent_children_no_self') THEN
    ALTER TABLE public.parent_children ADD CONSTRAINT parent_children_no_self CHECK (parent_id <> child_id);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_parent_children_parent_id ON public.parent_children(parent_id);
CREATE INDEX IF NOT EXISTS idx_parent_children_child_id ON public.parent_children(child_id);
ALTER TABLE public.parent_children ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parent_children FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.parent_children TO authenticated;
DROP POLICY IF EXISTS parent_children_select_parent ON public.parent_children;
CREATE POLICY parent_children_select_parent ON public.parent_children FOR SELECT USING ((select auth.uid()) = parent_id);
DROP POLICY IF EXISTS parent_children_select_child ON public.parent_children;
CREATE POLICY parent_children_select_child ON public.parent_children FOR SELECT USING ((select auth.uid()) = child_id);
DROP POLICY IF EXISTS parent_children_admin_all ON public.parent_children;
CREATE POLICY parent_children_admin_all ON public.parent_children FOR SELECT USING (EXISTS (SELECT 1 FROM public.profiles WHERE id=(select auth.uid()) AND role='admin'));

CREATE OR REPLACE FUNCTION public.validate_parent_child_roles_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF NEW.parent_id = NEW.child_id THEN RAISE EXCEPTION 'parent_id and child_id cannot be identical'; END IF;
  IF (SELECT role FROM public.profiles WHERE id=NEW.parent_id) NOT IN ('parent','admin') THEN
    RAISE EXCEPTION 'Parent must have role parent or admin';
  END IF;
  IF (SELECT role FROM public.profiles WHERE id=NEW.child_id) <> 'child' THEN
    RAISE EXCEPTION 'Child must have role child';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_validate_parent_child_roles ON public.parent_children;
CREATE TRIGGER trg_validate_parent_child_roles BEFORE INSERT OR UPDATE ON public.parent_children FOR EACH ROW EXECUTE FUNCTION public.validate_parent_child_roles_trigger();
REVOKE EXECUTE ON FUNCTION public.validate_parent_child_roles_trigger() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. watch_history_sessions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.watch_history_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  video_id UUID NOT NULL REFERENCES public.videos(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_heartbeat_at TIMESTAMPTZ DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  watched_seconds INTEGER NOT NULL DEFAULT 0 CHECK (watched_seconds >= 0),
  completed BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.watch_history_sessions ADD COLUMN IF NOT EXISTS last_heartbeat_at TIMESTAMPTZ DEFAULT NOW();
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_wh_sessions_ended_after_start') THEN
    ALTER TABLE public.watch_history_sessions ADD CONSTRAINT chk_wh_sessions_ended_after_start CHECK (ended_at IS NULL OR ended_at >= started_at);
  END IF;
END;
$$;
CREATE INDEX IF NOT EXISTS idx_wh_sessions_user_started ON public.watch_history_sessions(user_id, started_at);
CREATE INDEX IF NOT EXISTS idx_wh_sessions_video_started ON public.watch_history_sessions(video_id, started_at);
CREATE INDEX IF NOT EXISTS idx_wh_sessions_user_video_active ON public.watch_history_sessions(user_id, video_id, started_at) WHERE ended_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_wh_sessions_user_active ON public.watch_history_sessions(user_id, started_at) WHERE ended_at IS NULL;
ALTER TABLE public.watch_history_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.watch_history_sessions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.watch_history_sessions TO authenticated;
DROP POLICY IF EXISTS watch_history_sessions_select_own ON public.watch_history_sessions;
CREATE POLICY watch_history_sessions_select_own ON public.watch_history_sessions FOR SELECT USING ((select auth.uid()) = user_id);
DROP POLICY IF EXISTS watch_history_sessions_admin_select ON public.watch_history_sessions;
CREATE POLICY watch_history_sessions_admin_select ON public.watch_history_sessions FOR SELECT USING (EXISTS (SELECT 1 FROM public.profiles WHERE id=(select auth.uid()) AND role='admin'));

-- ---------------------------------------------------------------------------
-- 3. temporal event ledger
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.watch_history_session_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID NOT NULL REFERENCES public.watch_history_sessions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  video_id UUID NOT NULL REFERENCES public.videos(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ NOT NULL,
  watched_seconds INTEGER NOT NULL CHECK (watched_seconds >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_watch_event_chronology CHECK (ended_at >= started_at)
);
CREATE INDEX IF NOT EXISTS idx_session_events_session_started ON public.watch_history_session_events(session_id, started_at);
CREATE INDEX IF NOT EXISTS idx_session_events_user_started ON public.watch_history_session_events(user_id, started_at);
CREATE INDEX IF NOT EXISTS idx_session_events_user_ended ON public.watch_history_session_events(user_id, ended_at);
CREATE INDEX IF NOT EXISTS idx_session_events_video_started ON public.watch_history_session_events(video_id, started_at);
ALTER TABLE public.watch_history_session_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.watch_history_session_events FROM PUBLIC, anon;
GRANT SELECT ON public.watch_history_session_events TO authenticated;
DROP POLICY IF EXISTS "Session events viewable by owner" ON public.watch_history_session_events;
CREATE POLICY "Session events viewable by owner" ON public.watch_history_session_events FOR SELECT TO authenticated USING ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- 4. timezone helper
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_istanbul_day_start()
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
SELECT (date_trunc('day', now() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul');
$$;
REVOKE EXECUTE ON FUNCTION public.get_istanbul_day_start() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. parent-child RPCs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_parent_child_link(p_child_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_caller uuid := auth.uid(); v_parent_role text; v_child_role text; v_link uuid;
BEGIN
  IF v_caller IS NULL OR p_child_id IS NULL OR v_caller=p_child_id THEN RETURN jsonb_build_object('success',false,'error','Geçersiz hesap'); END IF;
  SELECT role INTO v_parent_role FROM public.profiles WHERE id=v_caller;
  IF v_parent_role NOT IN ('parent','admin') THEN RETURN jsonb_build_object('success',false,'error','Yalnızca ebeveyn/admin bağlayabilir.'); END IF;
  SELECT role INTO v_child_role FROM public.profiles WHERE id=p_child_id;
  IF v_child_role <> 'child' THEN RETURN jsonb_build_object('success',false,'error','Yalnızca child rolü bağlanabilir.'); END IF;
  INSERT INTO public.parent_children(parent_id,child_id) VALUES(v_caller,p_child_id) ON CONFLICT DO NOTHING RETURNING id INTO v_link;
  IF v_link IS NULL THEN SELECT id INTO v_link FROM public.parent_children WHERE parent_id=v_caller AND child_id=p_child_id; END IF;
  RETURN jsonb_build_object('success',true,'link_id',v_link);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.create_parent_child_link(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_parent_child_link(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_children()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_caller uuid:=auth.uid(); v_role text; v_result jsonb;
BEGIN
  IF v_caller IS NULL THEN RETURN '[]'::jsonb; END IF;
  SELECT role INTO v_role FROM public.profiles WHERE id=v_caller;
  IF v_role NOT IN ('parent','admin') THEN RETURN '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',pc.id,'child_id',p.id,'child_name',COALESCE(NULLIF(trim(concat_ws(' ',p.first_name,p.last_name)),''),'Çocuk Hesabı'),'created_at',pc.created_at) ORDER BY pc.created_at),'[]'::jsonb) INTO v_result
  FROM public.parent_children pc JOIN public.profiles p ON p.id=pc.child_id
  WHERE pc.parent_id=v_caller AND p.role='child';
  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_my_children() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_children() TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. canonical daily accounting
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_effective_child_daily_watch_seconds(p_user_id uuid)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_start timestamptz; v_total bigint:=0;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;
  v_start:=public.get_istanbul_day_start();
  SELECT COALESCE(SUM(LEAST(e.watched_seconds::bigint,GREATEST(0,extract(epoch FROM (least(e.ended_at,now())-greatest(e.started_at,v_start)))::bigint),43200)),0)
  INTO v_total
  FROM public.watch_history_session_events e
  WHERE e.user_id=p_user_id AND e.ended_at>=v_start AND e.started_at<=now();
  RETURN v_total;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_effective_child_daily_watch_seconds(uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. server playback authorization
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_child_video_play_policy(p_user_id uuid,p_video_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_role text:='guest'; v_video record; v_settings record; v_has boolean:=false; v_now_time text; v_daily bigint:=0;
BEGIN
  IF p_video_id IS NULL THEN RETURN jsonb_build_object('allowed',false,'reason','VIDEO_NOT_FOUND'); END IF;
  SELECT id,title,category_id,is_deleted,visibility INTO v_video FROM public.videos WHERE id=p_video_id;
  IF NOT FOUND OR v_video.is_deleted THEN RETURN jsonb_build_object('allowed',false,'reason','VIDEO_NOT_FOUND'); END IF;
  IF p_user_id IS NULL THEN RETURN jsonb_build_object('allowed',v_video.visibility='public','reason',CASE WHEN v_video.visibility='public' THEN 'OK' ELSE 'VIDEO_NOT_PUBLIC' END); END IF;
  SELECT role INTO v_role FROM public.profiles WHERE id=p_user_id;
  IF v_role IS NULL THEN RETURN jsonb_build_object('allowed',false,'reason','NOT_AUTHENTICATED'); END IF;
  IF v_role IN ('parent','admin') THEN RETURN jsonb_build_object('allowed',true,'reason','OK'); END IF;
  IF v_role='publisher' THEN RETURN jsonb_build_object('allowed',v_video.visibility='public','reason',CASE WHEN v_video.visibility='public' THEN 'OK' ELSE 'VIDEO_NOT_PUBLIC' END);
  END IF;
  IF v_role <> 'child' OR v_video.visibility <> 'public' THEN RETURN jsonb_build_object('allowed',false,'reason','VIDEO_NOT_PUBLIC'); END IF;
  SELECT ps.* INTO v_settings FROM public.parent_settings ps JOIN public.parent_children pc ON pc.parent_id=ps.user_id WHERE pc.child_id=p_user_id ORDER BY ps.updated_at DESC LIMIT 1;
  IF FOUND THEN v_has:=true; ELSE SELECT * INTO v_settings FROM public.parent_settings WHERE user_id=p_user_id; IF FOUND THEN v_has:=true; END IF; END IF;
  IF v_has THEN
    IF v_settings.allowed_categories IS NOT NULL AND array_length(v_settings.allowed_categories,1)>0 AND (v_video.category_id IS NULL OR NOT(v_video.category_id=ANY(v_settings.allowed_categories))) THEN RETURN jsonb_build_object('allowed',false,'reason','CATEGORY_RESTRICTED'); END IF;
    IF v_settings.bedtime_start IS NOT NULL AND v_settings.bedtime_end IS NOT NULL THEN
      v_now_time:=to_char(now() AT TIME ZONE 'Europe/Istanbul','HH24:MI');
      IF (v_settings.bedtime_start<=v_settings.bedtime_end AND v_now_time>=v_settings.bedtime_start AND v_now_time<v_settings.bedtime_end) OR (v_settings.bedtime_start>v_settings.bedtime_end AND (v_now_time>=v_settings.bedtime_start OR v_now_time<v_settings.bedtime_end)) THEN RETURN jsonb_build_object('allowed',false,'reason','BEDTIME'); END IF;
    END IF;
    IF v_settings.daily_time_limit_minutes IS NOT NULL AND v_settings.daily_time_limit_minutes>0 THEN
      v_daily:=public.get_effective_child_daily_watch_seconds(p_user_id);
      IF v_daily >= v_settings.daily_time_limit_minutes*60 THEN RETURN jsonb_build_object('allowed',false,'reason','DAILY_LIMIT'); END IF;
    END IF;
  END IF;
  RETURN jsonb_build_object('allowed',true,'reason','OK');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.check_child_video_play_policy(uuid,uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.authorize_child_video_play(p_video_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN RETURN public.check_child_video_play_policy(auth.uid(),p_video_id); END; $$;
REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.authorize_child_video_play(uuid) TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.start_watch_session(p_video_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_user uuid:=auth.uid(); v_auth jsonb; v_session uuid;
BEGIN
  IF v_user IS NULL THEN RETURN jsonb_build_object('success',false,'allowed',false,'reason','NOT_AUTHENTICATED'); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('child_watch_session_'||v_user::text));
  v_auth:=public.check_child_video_play_policy(v_user,p_video_id);
  IF COALESCE((v_auth->>'allowed')::boolean,false) IS NOT TRUE THEN RETURN jsonb_build_object('success',false,'allowed',false,'reason',COALESCE(v_auth->>'reason','AUTHORIZATION_ERROR')); END IF;
  INSERT INTO public.watch_history_sessions(user_id,video_id,started_at) VALUES(v_user,p_video_id,now()) RETURNING id INTO v_session;
  RETURN jsonb_build_object('success',true,'allowed',true,'session_id',v_session,'reused',false);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.start_watch_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_watch_session(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 8. heartbeat / finalize: effective 0004 implementations
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.heartbeat_watch_session(p_session_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_user uuid:=auth.uid(); v_s record; v_now timestamptz:=now(); v_start timestamptz; v_raw bigint; v_accept bigint; v_duration int; v_vremain bigint; v_sremain bigint; v_new int;
BEGIN
  IF v_user IS NULL OR p_session_id IS NULL THEN RETURN jsonb_build_object('success',false,'error','Geçersiz oturum'); END IF;
  SELECT id,user_id,video_id,started_at,last_heartbeat_at,watched_seconds INTO v_s FROM public.watch_history_sessions WHERE id=p_session_id AND user_id=v_user AND ended_at IS NULL FOR UPDATE;
  IF v_s.id IS NULL THEN RETURN jsonb_build_object('success',false,'error','Oturum bulunamadı veya sonlandırılmış.'); END IF;
  IF v_s.started_at>v_now THEN RETURN jsonb_build_object('success',false,'error','Geçersiz oturum başlangıç zamanı.'); END IF;
  v_start:=coalesce(v_s.last_heartbeat_at,v_s.started_at); v_raw:=greatest(0,extract(epoch FROM (v_now-v_start))::bigint); v_accept:=least(v_raw,10);
  v_sremain:=greatest(0,43200::bigint-v_s.watched_seconds::bigint); v_accept:=least(v_accept,v_sremain);
  SELECT duration INTO v_duration FROM public.videos WHERE id=v_s.video_id;
  IF v_duration IS NOT NULL AND v_duration>0 THEN v_vremain:=greatest(0,v_duration::bigint-v_s.watched_seconds::bigint); v_accept:=least(v_accept,v_vremain); END IF;
  IF v_accept>0 THEN
    INSERT INTO public.watch_history_session_events(session_id,user_id,video_id,started_at,ended_at,watched_seconds)
    VALUES(v_s.id,v_s.user_id,v_s.video_id,v_start,v_start+(v_accept||' seconds')::interval,v_accept::int);
  END IF;
  v_new:=(v_s.watched_seconds+v_accept)::int;
  UPDATE public.watch_history_sessions SET watched_seconds=v_new,last_heartbeat_at=v_now WHERE id=p_session_id AND user_id=v_user;
  RETURN jsonb_build_object('success',true,'watched_seconds',v_new);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.heartbeat_watch_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.heartbeat_watch_session(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.finalize_watch_session(p_session_id uuid,p_watched_seconds integer DEFAULT NULL,p_completed boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_user uuid:=auth.uid(); v_video uuid; v_started timestamptz; v_last timestamptz; v_total int; v_duration int; v_elapsed bigint; v_start timestamptz; v_raw bigint; v_accept bigint; v_vremain bigint; v_sremain bigint; v_eremain bigint; v_final int; v_completed boolean:=false; v_now timestamptz:=now();
BEGIN
  IF v_user IS NULL OR p_session_id IS NULL THEN RETURN jsonb_build_object('success',false,'error','Geçersiz oturum'); END IF;
  SELECT video_id,started_at,last_heartbeat_at,watched_seconds INTO v_video,v_started,v_last,v_total FROM public.watch_history_sessions WHERE id=p_session_id AND user_id=v_user AND ended_at IS NULL FOR UPDATE;
  IF v_video IS NULL THEN RETURN jsonb_build_object('success',false,'error','Geçersiz veya daha önce sonlandırılmış oturum.'); END IF;
  v_elapsed:=greatest(0,extract(epoch FROM (v_now-v_started))::bigint); v_start:=coalesce(v_last,v_started); v_raw:=greatest(0,extract(epoch FROM (v_now-v_start))::bigint); v_accept:=least(v_raw,10);
  v_eremain:=greatest(0,v_elapsed-v_total::bigint); v_accept:=least(v_accept,v_eremain); v_sremain:=greatest(0,43200::bigint-v_total::bigint); v_accept:=least(v_accept,v_sremain);
  SELECT duration INTO v_duration FROM public.videos WHERE id=v_video;
  IF v_duration IS NOT NULL AND v_duration>0 THEN v_vremain:=greatest(0,v_duration::bigint-v_total::bigint); v_accept:=least(v_accept,v_vremain); END IF;
  IF v_accept>0 THEN INSERT INTO public.watch_history_session_events(session_id,user_id,video_id,started_at,ended_at,watched_seconds) VALUES(p_session_id,v_user,v_video,v_start,v_start+(v_accept||' seconds')::interval,v_accept::int); END IF;
  v_final:=(v_total+v_accept)::int;
  IF v_duration IS NOT NULL AND v_duration>0 THEN v_completed:=p_completed IS TRUE AND v_final >= (v_duration*0.9); ELSE v_completed:=coalesce(p_completed,false) AND v_final>0; END IF;
  UPDATE public.watch_history_sessions SET ended_at=v_now,watched_seconds=v_final,completed=v_completed WHERE id=p_session_id AND user_id=v_user;
  INSERT INTO public.watch_history(user_id,video_id,progress_seconds,completed,updated_at) VALUES(v_user,v_video,0,v_completed,v_now)
  ON CONFLICT(user_id,video_id) DO UPDATE SET completed=CASE WHEN watch_history.completed THEN TRUE ELSE EXCLUDED.completed END,updated_at=v_now;
  RETURN jsonb_build_object('success',true,'watched_seconds',v_final);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.finalize_watch_session(uuid,integer,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_watch_session(uuid,integer,boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- 9. event-based parent report
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_parent_child_usage_report(p_child_id uuid,p_period text DEFAULT 'weekly')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_caller uuid:=auth.uid(); v_role text; v_authorized boolean:=false; v_start timestamptz; v_total bigint:=0; v_watched int:=0; v_completed int:=0; v_categories jsonb:='[]'::jsonb; v_top jsonb:='[]'::jsonb;
BEGIN
  IF v_caller IS NULL THEN RETURN NULL; END IF;
  SELECT role INTO v_role FROM public.profiles WHERE id=v_caller;
  IF v_role='admin' THEN v_authorized:=true; ELSIF v_role='parent' THEN SELECT EXISTS(SELECT 1 FROM public.parent_children WHERE parent_id=v_caller AND child_id=p_child_id) INTO v_authorized; END IF;
  IF NOT v_authorized THEN RETURN jsonb_build_object('error','Yetkisiz erişim: Bu çocuğun verilerine erişim izniniz yok.','period',p_period,'totalWatchTimeSeconds',0,'watchedVideosCount',0,'completedVideosCount',0,'categoryStats','[]'::jsonb,'topWatchedVideos','[]'::jsonb); END IF;
  CASE lower(p_period)
    WHEN 'daily' THEN v_start:=public.get_istanbul_day_start();
    WHEN 'weekly' THEN v_start:=now()-interval '7 days';
    WHEN 'monthly' THEN v_start:=now()-interval '30 days';
    WHEN '3months' THEN v_start:=now()-interval '90 days';
    WHEN '6months' THEN v_start:=now()-interval '180 days';
    WHEN '9months' THEN v_start:=now()-interval '270 days';
    WHEN '12months' THEN v_start:=now()-interval '365 days';
    ELSE v_start:=now()-interval '7 days';
  END CASE;
  WITH pe AS (
    SELECT e.session_id,e.video_id,v.category_id,s.completed,
      least(e.watched_seconds::bigint,greatest(0,extract(epoch FROM (least(e.ended_at,now())-greatest(e.started_at,v_start)))::bigint)) AS sec
    FROM public.watch_history_session_events e JOIN public.watch_history_sessions s ON s.id=e.session_id JOIN public.videos v ON v.id=e.video_id
    WHERE e.user_id=p_child_id AND e.ended_at>=v_start AND e.started_at<=now() AND v.is_deleted=false
  )
  SELECT coalesce(sum(sec),0),count(distinct video_id) filter(where sec>0),count(distinct video_id) filter(where completed=true) INTO v_total,v_watched,v_completed FROM pe;
  WITH pe AS (
    SELECT e.video_id,v.category_id,least(e.watched_seconds::bigint,greatest(0,extract(epoch FROM (least(e.ended_at,now())-greatest(e.started_at,v_start)))::bigint)) AS sec
    FROM public.watch_history_session_events e JOIN public.videos v ON v.id=e.video_id WHERE e.user_id=p_child_id AND e.ended_at>=v_start AND e.started_at<=now() AND v.is_deleted=false
  ), cs AS (SELECT category_id,sum(sec) total_sec,count(distinct video_id) video_count FROM pe GROUP BY category_id)
  SELECT coalesce(jsonb_agg(jsonb_build_object('categoryId',c.id,'categoryTitle',c.title,'categoryName',c.title,'categoryIcon',c.icon_name,'watchTimeSeconds',cs.total_sec,'percentage',case when v_total>0 then round(cs.total_sec::numeric/v_total::numeric*100,1) else 0 end,'videoCount',cs.video_count) ORDER BY cs.total_sec DESC),'[]'::jsonb) INTO v_categories FROM cs JOIN public.categories c ON c.id=cs.category_id;
  WITH pe AS (
    SELECT e.video_id,least(e.watched_seconds::bigint,greatest(0,extract(epoch FROM (least(e.ended_at,now())-greatest(e.started_at,v_start)))::bigint)) AS sec
    FROM public.watch_history_session_events e JOIN public.videos v ON v.id=e.video_id WHERE e.user_id=p_child_id AND e.ended_at>=v_start AND e.started_at<=now() AND v.is_deleted=false
  ), tv AS (SELECT video_id,sum(sec) total_sec,count(*) session_count FROM pe GROUP BY video_id ORDER BY total_sec DESC LIMIT 5)
  SELECT coalesce(jsonb_agg(jsonb_build_object('videoId',v.id,'title',v.title,'watchCount',tv.session_count,'totalSeconds',tv.total_sec) ORDER BY tv.total_sec DESC),'[]'::jsonb) INTO v_top FROM tv JOIN public.videos v ON v.id=tv.video_id;
  RETURN jsonb_build_object('period',p_period,'totalWatchTimeSeconds',v_total,'watchedVideosCount',v_watched,'completedVideosCount',v_completed,'categoryStats',v_categories,'topWatchedVideos',v_top);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_parent_child_usage_report(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_parent_child_usage_report(uuid,text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 10. FINAL grants for canonical RPC set
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.validate_parent_child_roles_trigger() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_istanbul_day_start() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_effective_child_daily_watch_seconds(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.check_child_video_play_policy(uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_my_children() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_children() TO authenticated;

-- No direct client mutation on sensitive tables.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.parent_children FROM PUBLIC, anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.watch_history_sessions FROM PUBLIC, anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.watch_history_session_events FROM PUBLIC, anon, authenticated;
