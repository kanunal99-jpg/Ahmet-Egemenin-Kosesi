/**
 * Formats duration in seconds to HH:MM:SS or MM:SS string
 */
export function formatDuration(seconds: number): string {
  if (!seconds || seconds <= 0) return '00:00';

  const hrs = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);

  const formattedMins = mins.toString().padStart(2, '0');
  const formattedSecs = secs.toString().padStart(2, '0');

  if (hrs > 0) {
    return `${hrs}:${formattedMins}:${formattedSecs}`;
  }
  return `${formattedMins}:${formattedSecs}`;
}

/**
 * Formats seconds into human-readable Turkish duration (e.g. 15 dk 30 sn)
 */
export function formatDurationHuman(seconds: number): string {
  if (!seconds || seconds <= 0) return '0 saniye';

  const hrs = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);

  if (hrs > 0) {
    return `${hrs} saat ${mins} dk`;
  }
  if (mins > 0) {
    return `${mins} dk`;
  }
  return `${seconds} saniye`;
}
