import { test, expect } from '@playwright/test';

test('home page loads its primary content', async ({ page }) => {
  await page.goto('');
  await expect(page.getByRole('heading', { name: 'Eğlenceli ve Eğitici İçerikler Burada!' })).toBeVisible();
  await expect(page.getByRole('textbox', { name: 'Video veya konu ara...' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Tümü', exact: true })).toHaveAttribute('aria-pressed', 'true');
});

test('empty public catalog renders its empty state', async ({ page }) => {
  await page.goto('');
  await expect(page.getByRole('heading', { name: 'Henüz Video Bulunmuyor' })).toBeVisible({ timeout: 15_000 });
});

test('category filter changes selected state', async ({ page }) => {
  await page.goto('');
  const category = page.getByRole('button', { name: 'Masallar', exact: true });
  await category.click();
  await expect(category).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByRole('button', { name: 'Tümü', exact: true })).toHaveAttribute('aria-pressed', 'false');
});

test('search input accepts a video query', async ({ page }) => {
  await page.goto('');
  const search = page.getByRole('textbox', { name: 'Video veya konu ara...' });
  await search.fill('hayvan');
  await expect(search).toHaveValue('hayvan');
});

test('unauthenticated users cannot open the parent panel', async ({ page }) => {
  await page.goto('parent-panel');
  await expect(page).toHaveURL(/\/login(?:\?|$)/);
  await expect(page.getByRole('heading', { name: 'Hoş Geldiniz' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Ebeveyn Yönetim Paneli' })).toHaveCount(0);
});

test('login form exposes accessible email, password and submit controls', async ({ page }) => {
  await page.goto('login');
  await expect(page.getByLabel('E-Posta Adresi')).toBeVisible();
  await expect(page.getByLabel('Şifre')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Giriş Yap' })).toBeVisible();
});

test('invalid login remains on login page and shows an error', async ({ page }) => {
  await page.goto('login');
  await page.getByLabel('E-Posta Adresi').fill(`e2e-invalid-${Date.now()}@example.invalid`);
  await page.getByLabel('Şifre').fill('InvalidPassword!123456');
  await page.getByRole('button', { name: 'Giriş Yap' }).click();

  await expect(page).toHaveURL(/\/login(?:\?|$)/);
  await expect(page.getByRole('alert')).toBeVisible({ timeout: 10_000 });
});

test('authenticated parent can access and render all parent panel tabs', async ({ page }) => {
  const hasCredentials = Boolean(process.env.E2E_EMAIL && process.env.E2E_PASSWORD);
  test.skip(!hasCredentials, 'E2E_EMAIL/E2E_PASSWORD are not configured; authenticated coverage is unavailable.');

  await page.goto('login');
  await page.getByLabel('E-Posta Adresi').fill(process.env.E2E_EMAIL!);
  await page.getByLabel('Şifre').fill(process.env.E2E_PASSWORD!);
  await page.getByRole('button', { name: 'Giriş Yap' }).click();

  await expect(page).not.toHaveURL(/\/login(?:\?|$)/, { timeout: 15_000 });
  await page.goto('parent-panel');
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

    if (tab.label === 'Kullanım Raporları') {
      const childSelector = page.getByLabel('Çocuk');
      const emptyState = page.getByText('Henüz bağlı bir çocuk hesabı bulunmuyor.');
      await expect(childSelector.or(emptyState)).toBeVisible();
    }
  }

  await page.getByRole('link', { name: 'Favoriler' }).click();
  await expect(page).toHaveURL(/\/favorites(?:\?|$)/);
  await expect(page.getByRole('heading', { name: 'Favori Videolarım' })).toBeVisible();

  await page.getByRole('link', { name: 'Geçmiş' }).click();
  await expect(page).toHaveURL(/\/history(?:\?|$)/);
  await expect(page.getByRole('heading', { name: 'İzleme Geçmişim' })).toBeVisible();

  await page.getByRole('button', { name: 'Çıkış Yap' }).click();
  await expect(page).toHaveURL(/\/login(?:\?|$)/, { timeout: 10_000 });
  await expect(page.getByRole('heading', { name: 'Hoş Geldiniz' })).toBeVisible();
});
