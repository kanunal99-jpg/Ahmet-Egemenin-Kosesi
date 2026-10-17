/**
 * A child account must not see unrestricted categories while parental settings
 * are pending, unavailable or belong to another user.
 *
 * NULL allowed categories from a VERIFIED server response means unrestricted.
 * An empty array means no categories are permitted.
 * Playback authorization remains server-side; this is a UI defense in depth.
 */
export interface ChildCategoryPolicy {
  userId: string;
  status: 'ready' | 'error';
  allowedCategoryIds: string[] | null;
}

export function permittedCategoryIds(
  role: string | null,
  userId: string | undefined,
  policy: ChildCategoryPolicy | null,
): string[] | null {
  if (role !== 'child') return null;
  if (!userId || !policy || policy.userId !== userId || policy.status !== 'ready') return [];
  return policy.allowedCategoryIds;
}

export function isVisibleForChild(
  categoryId: string | null | undefined,
  permittedIds: string[] | null,
): boolean {
  if (permittedIds === null) return true;
  return Boolean(categoryId && permittedIds.includes(categoryId));
}
