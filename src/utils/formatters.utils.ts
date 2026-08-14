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

/**
 * Determines whether current time falls within a given start (HH:mm) and end (HH:mm) window
 */
export function isWithinTimeRange(startStr?: string | null, endStr?: string | null): boolean {
  if (!startStr || !endStr) return false;
  const now = new Date();
  const currentMinutes = now.getHours() * 60 + now.getMinutes();

  const [sH, sM] = startStr.split(':').map(Number);
  const [eH, eM] = endStr.split(':').map(Number);
  if (isNaN(sH) || isNaN(sM) || isNaN(eH) || isNaN(eM)) return false;

  const startMinutes = sH * 60 + sM;
  const endMinutes = eH * 60 + eM;

  if (startMinutes <= endMinutes) {
    return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
  } else {
    // Overnight window (e.g. 21:00 to 07:00)
    return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
  }
}
