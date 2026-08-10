/**
 * Compute SHA-256 hash of string (e.g., Parent PIN)
 */
export async function hashPin(pin: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(pin);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Compare plain pin against stored hash
 */
export async function verifyPin(pin: string, storedHash: string): Promise<boolean> {
  const computedHash = await hashPin(pin);
  return computedHash === storedHash;
}
