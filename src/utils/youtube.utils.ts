/**
 * Extracts YouTube video ID from various YouTube URL formats (watch, youtu.be, embed, shorts, etc.)
 */
export function extractYouTubeId(url: string): string | null {
  if (!url) return null;
  const trimmed = url.trim();

  // If already an 11-char YouTube ID
  if (/^[a-zA-Z0-9_-]{11}$/.test(trimmed)) {
    return trimmed;
  }

  const regExp = /(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=|shorts\/)|youtu\.be\/)([^"&?\/\s]{11})/i;
  const match = trimmed.match(regExp);

  return match && match[1] && match[1].length === 11 ? match[1] : null;
}

/**
 * Returns clean embed URL for YouTube videos with child-safe parameters
 */
export function getYouTubeEmbedUrl(urlOrId: string): string | null {
  const videoId = extractYouTubeId(urlOrId) || urlOrId;
  if (!videoId || videoId.length !== 11) return null;

  return `https://www.youtube-nocookie.com/embed/${videoId}?rel=0&modestbranding=1&autoplay=1`;
}

/**
 * Generates thumbnail URL from YouTube video ID
 */
export function getYouTubeThumbnail(urlOrId: string): string {
  const videoId = extractYouTubeId(urlOrId) || urlOrId;
  if (!videoId) return '/placeholder-thumbnail.jpg';
  return `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
}
