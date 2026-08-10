import React, { useEffect, useRef } from 'react';
import { Video } from '../../types';
import { getYouTubeEmbedUrl, extractYouTubeId } from '../../utils/youtube.utils';
import { useAuth } from '../../hooks/useAuth';
import { watchHistoryService } from '../../services/watchHistory.service';
import { videoService } from '../../services/video.service';
import { X } from 'lucide-react';

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

export const VideoPlayerModal: React.FC<VideoPlayerModalProps> = ({ video, onClose }) => {
  const { user } = useAuth();
  const playerRef = useRef<any>(null);
  const iframeContainerRef = useRef<HTMLDivElement>(null);
  const activeIntervalRef = useRef<number | null>(null);
  
  const hasIncrementedView = useRef<boolean>(false);
  const activePlayTimeSecondsRef = useRef<number>(0);
  const maxWatchedTimeSecondsRef = useRef<number>(0);
  const isCompletedRef = useRef<boolean>(false);

  const youtubeId = video ? extractYouTubeId(video.video_url) : null;
  const embedUrl = video ? getYouTubeEmbedUrl(video.video_url) : null;

  useEffect(() => {
    if (!video || !youtubeId) return;

    hasIncrementedView.current = false;
    activePlayTimeSecondsRef.current = 0;
    maxWatchedTimeSecondsRef.current = 0;
    isCompletedRef.current = false;

    // Save initial history entry (progress = 0)
    if (user?.id) {
      watchHistoryService.saveProgress(user.id, {
        video_id: video.id,
        progress_seconds: 0,
        completed: false,
      });
    }

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
      if (!iframeContainerRef.current || !window.YT || !window.YT.Player) return;

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
      stopPlayingTimer();
      document.removeEventListener('visibilitychange', handleVisibilityChange);

      // Save watch history on close if logged in
      if (video && user?.id) {
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
          (totalDuration > 0 && activePlayTimeSecondsRef.current / totalDuration >= 0.9);

        if (finalProgress > 1 || activePlayTimeSecondsRef.current > 1) {
          watchHistoryService.saveProgress(user.id, {
            video_id: video.id,
            progress_seconds: finalProgress,
            completed: isCompleted,
          });
        }
      }
    };
  }, [video, user?.id, youtubeId]);

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

        {/* Video Embed Frame */}
        <div className="relative aspect-video w-full bg-black">
          {youtubeId ? (
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
