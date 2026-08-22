import { test, expect } from '@playwright/test';

test('unauthenticated users cannot open the parent panel', async ({ page }) => {
  await page.goto('/parent-panel');
  await expect(page).toHaveURL(/\/login(?:\?|$)/);
});

test('authenticated parent can access all parent panel tabs', async ({ page }) => {
  test.skip(!process.env.E2E_EMAIL || !process.env.E2E_PASSWORD, 'E2E_EMAIL/E2E_PASSWORD secrets are required for authenticated coverage.');

  await page.goto('/login');
  await page.getByLabel(/e-?posta/i).fill(process.env.E2E_EMAIL!);
  await page.getByLabel(/şifre|password/i).fill(process.env.E2E_PASSWORD!);
  await page.getByRole('button', { name: /giriş yap|login/i }).click();

  await expect(page).not.toHaveURL(/\/login(?:\?|$)/, { timeout: 15_000 });
  await page.goto('/parent-panel');

  await expect(page.getByRole('heading', { name: 'Ebeveyn Yönetim Paneli' })).toBeVisible({ timeout: 15_000 });

  const tabs = [
    'Video Yönetimi',
    'Kullanım Raporları',
    'İzleme Geçmişi',
    'Favoriler',
    'Kısıtlamalar ve Süre',
    'PIN Yönetimi',
  ];

  for (const tab of tabs) {
    await page.getByRole('button', { name: tab, exact: true }).click();
    await expect(page.getByRole('button', { name: tab, exact: true })).toBeVisible();
  }
});
