import { test, expect } from '@playwright/test';

test('unauthenticated users cannot open the parent panel', async ({ page }) => {
  await page.goto('/parent-panel');
  await expect(page).toHaveURL(/\/login(?:\?|$)/);
  await expect(page.getByRole('heading', { name: 'Hoş Geldiniz' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Ebeveyn Yönetim Paneli' })).toHaveCount(0);
});

test('login form exposes accessible email, password and submit controls', async ({ page }) => {
  await page.goto('/login');
  await expect(page.getByLabel('E-Posta Adresi')).toBeVisible();
  await expect(page.getByLabel('Şifre')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Giriş Yap' })).toBeVisible();
});

test('authenticated parent can access and render all parent panel tabs', async ({ page }) => {
  test.skip(
    !process.env.E2E_EMAIL || !process.env.E2E_PASSWORD,
    'E2E_EMAIL/E2E_PASSWORD secrets are required for authenticated coverage.',
  );

  await page.goto('/login');
  await page.getByLabel('E-Posta Adresi').fill(process.env.E2E_EMAIL!);
  await page.getByLabel('Şifre').fill(process.env.E2E_PASSWORD!);
  await page.getByRole('button', { name: 'Giriş Yap' }).click();

  await expect(page).not.toHaveURL(/\/login(?:\?|$)/, { timeout: 15_000 });
  await page.goto('/parent-panel');
  await expect(page.getByRole('heading', { name: 'Ebeveyn Yönetim Paneli' })).toBeVisible({ timeout: 15_000 });

  const tabs = [
    { label: 'Video Yönetimi', heading: 'Video Yönetimi' },
    { label: 'Kullanım Raporları', heading: 'Kullanım Raporları' },
    { label: 'İzleme Geçmişi', heading: 'İzleme Geçmişi' },
    { label: 'Favoriler', heading: 'Favori Videolar' },
    { label: 'Kısıtlamalar ve Süre', heading: 'Kullanım Kısıtlamaları ve Süre Sınırı' },
    { label: 'PIN Yönetimi', heading: 'Ebeveyn PIN Kodu Yönetimi' },
  ];

  for (const tab of tabs) {
    await page.getByRole('button', { name: tab.label, exact: true }).click();
    await expect(page.getByRole('heading', { name: tab.heading, exact: true })).toBeVisible();
  }
});
