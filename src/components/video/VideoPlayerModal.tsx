import React, { useEffect, useRef, useState } from 'react';
import { Video } from '../../types';
import { getYouTubeEmbedUrl, extractYouTubeId } from '../../utils/youtube.utils';
import { useAuth } from '../../hooks/useAuth';
import { watchHistoryService } from '../../services/watchHistory.service';
import { videoService } from '../../services/video.service';
import { parentalControlService } from '../../services/parentalControl.service';
import { PlaybackAuthorizationReason } from '../../types/parentalControl.types';
import { X, Moon, Clock, ShieldAlert, AlertCircle, Loader2 } from 'lucide-react';

declare global {
  interface Window {
    YT: any;
    onYouTubeIframeAPIReady: (() => void) | undefined;
  }
}

interface VideoPlayerModalProps {
  video: Video | null;
  onClose: () => void;
}

type AuthState = 'checking' | 'authorized' | 'denied' | 'error';

export const VideoPlayerModal: React.FC<VideoPlayerModalProps> = ({ video, onClose }) => {
  const { user } = useAuth();
  const playerRef = useRef<any>(null);
  const iframeContainerRef = useRef<HTMLDivElement>(null);
  const activeIntervalRef = useRef<number | null>(null);
  
  // Watch session & tracking refs (CRIT-08)
  const activeSessionIdRef = useRef<string | null>(null);
  const hasIncrementedView = useRef<boolean>(false);
  const activePlayTimeSecondsRef = useRef<number>(0);
  const maxWatchedTimeSecondsRef = useRef<number>(0);
  const isCompletedRef = useRef<boolean>(false);

  // Fail-Closed Authorization state (CRIT-07, CRIT-16)
  const [authState, setAuthState] = useState<AuthState>('checking');
  const [authReason, setAuthReason] = useState<PlaybackAuthorizationReason>('OK');
  const [authMessage, setAuthMessage] = useState<string>('');

  const youtubeId = video ? extractYouTubeId(video.video_url) : null;
  const embedUrl = video ? getYouTubeEmbedUrl(video.video_url) : null;

  // Step 1: Server-Side Playback Authorization Check (FAIL-CLOSED)
  useEffect(() => {
    if (!video?.id) return;

    let isMounted = true;
    setAuthState('checking');
    setAuthMessage('');

    parentalControlService
      .authorizePlayback(video.id)
      .then((res) => {
        if (!isMounted) return;

        if (res.allowed) {
          setAuthState('authorized');
          setAuthReason('OK');
        } else {
          setAuthState(res.reason === 'AUTHORIZATION_ERROR' || res.reason === 'SETTINGS_UNAVAILABLE' ? 'error' : 'denied');
          setAuthReason(res.reason);
          setAuthMessage(res.message || 'Bu videoyu izleme izniniz bulunmuyor.');
        }
      })
      .catch((err) => {
        if (!isMounted) return;
        setAuthState('error');
        setAuthReason('AUTHORIZATION_ERROR');
        setAuthMessage('Ebeveyn denetimi yetkilendirmesi sırasında bir bağlantı sorunu oluştu.');
      });

    return () => {
      isMounted = false;
    };
  }, [video?.id]);

  // Step 2: Initialize YouTube Player and Session Tracking ONLY IF AUTHORIZED
  useEffect(() => {
    if (!video || !youtubeId || authState !== 'authorized') return;

    let isMounted = true;
    hasIncrementedView.current = false;
    activePlayTimeSecondsRef.current = 0;
    maxWatchedTimeSecondsRef.current = 0;
    isCompletedRef.current = false;
    activeSessionIdRef.current = null;

    const startPlayingTimer = () => {
      if (activeIntervalRef.current !== null) return;
      activeIntervalRef.current = window.setInterval(() => {
        activePlayTimeSecondsRef.current += 1;
        if (playerRef.current && typeof playerRef.current.getCurrentTime === 'function') {
          const curr = Math.floor(playerRef.current.getCurrentTime() || 0);
          if (curr > maxWatchedTimeSecondsRef.current) {
            maxWatchedTimeSecondsRef.current = curr;
          }
        }
      }, 1000);
    };

    const stopPlayingTimer = () => {
      if (activeIntervalRef.current !== null) {
        clearInterval(activeIntervalRef.current);
        activeIntervalRef.current = null;
      }
    };

    const handleStateChange = (event: any) => {
      // YT.PlayerState: PLAYING = 1, PAUSED = 2, ENDED = 0, BUFFERING = 3
      if (event.data === 1) { // PLAYING
        startPlayingTimer();

        // Increment view count ONLY when video actually starts playing
        if (!hasIncrementedView.current) {
          hasIncrementedView.current = true;
          videoService.incrementViewCount(video.id);
        }
      } else if (event.data === 0) { // ENDED
        stopPlayingTimer();
        isCompletedRef.current = true;
      } else { // PAUSED, BUFFERING, CUED, etc.
        stopPlayingTimer();
      }
    };

    const initPlayer = () => {
      if (!iframeContainerRef.current || !window.YT || !window.YT.Player || !isMounted) return;

      iframeContainerRef.current.innerHTML = '<div id="yt-player-element" class="w-full h-full"></div>';

      try {
        playerRef.current = new window.YT.Player('yt-player-element', {
          videoId: youtubeId,
          playerVars: {
            autoplay: 1,
            rel: 0,
            modestbranding: 1,
          },
          events: {
            onStateChange: handleStateChange,
          },
        });
      } catch (err) {
        console.error('Failed to initialize YouTube player:', err);
      }
    };

    const setupPlayerFlow = () => {
      // Load YouTube IFrame API if not already loaded
      if (!window.YT) {
        const existingScript = document.getElementById('youtube-iframe-api');
        if (!existingScript) {
          const script = document.createElement('script');
          script.id = 'youtube-iframe-api';
          script.src = 'https://www.youtube.com/iframe_api';
          document.body.appendChild(script);
        }

        const previousOnReady = window.onYouTubeIframeAPIReady;
        window.onYouTubeIframeAPIReady = () => {
          if (previousOnReady) previousOnReady();
          initPlayer();
        };
      } else {
        initPlayer();
      }
    };

    // If user is logged in, start session in DB first (CRIT-18 Server Check)
    if (user?.id) {
      watchHistoryService.startSession(video.id).then((res) => {
        if (!isMounted) return;

        if (res.success && res.sessionId) {
          activeSessionIdRef.current = res.sessionId;
          setupPlayerFlow();
        } else {
          // If startSession denied by server (e.g. daily limit/bedtime trigger)
          setAuthState('denied');
          setAuthReason((res.reason as PlaybackAuthorizationReason) || 'SESSION_AUTHORIZATION_FAILED');
          setAuthMessage(res.error || 'Video başlatılamadı, ebeveyn koruması nedeniyle işlem reddedildi.');
        }
      });
    } else {
      // Public / guest view
      setupPlayerFlow();
    }

    // Visibility change listener: pause timer/video when tab is backgrounded
    const handleVisibilityChange = () => {
      if (document.hidden) {
        stopPlayingTimer();
        if (playerRef.current && typeof playerRef.current.pauseVideo === 'function') {
          playerRef.current.pauseVideo();
        }
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      isMounted = false;
      stopPlayingTimer();
      document.removeEventListener('visibilitychange', handleVisibilityChange);

      // Finalize watch session and save progress on close
      const sessionId = activeSessionIdRef.current;
      const watchedSecs = activePlayTimeSecondsRef.current;
      let finalProgress = maxWatchedTimeSecondsRef.current;
      let totalDuration = video.duration > 0 ? video.duration : 60;

      if (playerRef.current) {
        if (typeof playerRef.current.getCurrentTime === 'function') {
          const curr = Math.floor(playerRef.current.getCurrentTime() || 0);
          if (curr > finalProgress) finalProgress = curr;
        }
        if (typeof playerRef.current.getDuration === 'function') {
          const dur = Math.floor(playerRef.current.getDuration() || 0);
          if (dur > 0) totalDuration = dur;
        }
        try {
          playerRef.current.destroy();
        } catch {}
      }

      const isCompleted =
        isCompletedRef.current ||
        (totalDuration > 0 && finalProgress / totalDuration >= 0.9) ||
        (totalDuration > 0 && watchedSecs / totalDuration >= 0.9);

      // Finalize DB session (CRIT-08)
      if (sessionId && watchedSecs > 0) {
        watchHistoryService.finalizeSession(sessionId, watchedSecs, isCompleted);
      }

      // Upsert current progress in watch_history
      if (user?.id && (finalProgress > 1 || watchedSecs > 1)) {
        watchHistoryService.saveProgress(user.id, {
          video_id: video.id,
          progress_seconds: finalProgress,
          completed: isCompleted,
        });
      }
    };
  }, [video, user?.id, youtubeId, authState]);

  if (!video) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-md animate-fade-in">
      <div className="relative w-full max-w-4xl bg-black rounded-3xl overflow-hidden shadow-2xl border border-slate-800">
        {/* Header Bar */}
        <div className="flex items-center justify-between p-4 bg-slate-900 border-b border-slate-800">
          <h3 className="font-bold text-white text-base truncate max-w-lg">{video.title}</h3>
          <button
            onClick={onClose}
            className="p-2 text-slate-400 hover:text-white rounded-xl hover:bg-slate-800 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Video Embed Frame or Fail-Closed Guard Message */}
        <div className="relative aspect-video w-full bg-black flex items-center justify-center">
          {authState === 'checking' ? (
            <div className="p-8 text-center space-y-3 bg-slate-900/90 rounded-3xl border border-slate-800 m-4">
              <Loader2 className="w-8 h-8 text-purple-400 animate-spin mx-auto" />
              <h4 className="text-sm font-bold text-white">Ebeveyn Yetkilendirmesi Doğrulanıyor...</h4>
              <p className="text-xs text-slate-400">Güvenli izleme kuralları sunucuda kontrol ediliyor.</p>
            </div>
          ) : authState === 'denied' || authState === 'error' ? (
            <div className="p-8 max-w-md text-center space-y-4 bg-slate-900/90 rounded-3xl border border-slate-800 m-4 animate-fade-in">
              <div className="w-16 h-16 rounded-2xl bg-amber-500/10 text-amber-400 flex items-center justify-center mx-auto shadow-inner">
                {authReason === 'BEDTIME' ? (
                  <Moon className="w-8 h-8 text-indigo-400" />
                ) : authReason === 'DAILY_LIMIT' ? (
                  <Clock className="w-8 h-8 text-amber-400" />
                ) : authReason === 'CATEGORY_RESTRICTED' ? (
                  <ShieldAlert className="w-8 h-8 text-rose-400" />
                ) : (
                  <AlertCircle className="w-8 h-8 text-amber-400" />
                )}
              </div>
              <h4 className="text-lg font-black text-white">
                {authReason === 'BEDTIME'
                  ? 'Uyku Vakti Devrede'
                  : authReason === 'DAILY_LIMIT'
                  ? 'Günlük Süre Limiti Doldu'
                  : authReason === 'CATEGORY_RESTRICTED'
                  ? 'Kategori Kısıtlaması'
                  : 'Oynatma Engellendi'}
              </h4>
              <p className="text-xs text-slate-300 leading-relaxed">{authMessage}</p>
              <button
                onClick={onClose}
                className="px-6 py-2.5 rounded-xl bg-purple-600 hover:bg-purple-700 text-white text-xs font-bold transition-all shadow-md"
              >
                Anladım, Kapat
              </button>
            </div>
          ) : youtubeId ? (
            <div ref={iframeContainerRef} className="w-full h-full">
              <div id="yt-player-element" className="w-full h-full" />
            </div>
          ) : embedUrl ? (
            <iframe
              src={embedUrl}
              title={video.title}
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
              allowFullScreen
              className="w-full h-full border-0"
            />
          ) : (
            <div className="flex items-center justify-center h-full text-slate-400">
              Video oynatılamıyor.
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

