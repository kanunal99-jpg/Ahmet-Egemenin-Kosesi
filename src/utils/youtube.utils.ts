/**
 * Extracts YouTube video ID from various YouTube URL formats
 */
export function extractYouTubeId(url: string): string | null {
  if (!url) return null;

  const regExp = /^.*(youtu.be\/|v\/|u\/\w\/|embed\/|watch\?v=|&v=)([^#&?]*).*/;
  const match = url.match(regExp);

  return match && match[2].length === 11 ? match[2] : null;
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
