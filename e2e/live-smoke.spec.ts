import { test, expect } from '@playwright/test';

test('live home page loads on production', async ({ page }) => {
  await page.goto('');
  await expect(page.getByRole('heading', { name: 'Eğlenceli ve Eğitici İçerikler Burada!' })).toBeVisible();
  await expect(page.getByRole('textbox', { name: 'Video veya konu ara...' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Tümü', exact: true })).toHaveAttribute('aria-pressed', 'true');
});

test('live category filter and search controls work', async ({ page }) => {
  await page.goto('');
  const category = page.getByRole('button', { name: 'Masallar', exact: true });
  await category.click();
  await expect(category).toHaveAttribute('aria-pressed', 'true');

  const search = page.getByRole('textbox', { name: 'Video veya konu ara...' });
  await search.fill('hayvan');
  await expect(search).toHaveValue('hayvan');
});

test('live parent panel remains protected for guests', async ({ page }) => {
  await page.goto('parent-panel');
  await expect(page).toHaveURL(/\/login(?:\?|$)/);
  await expect(page.getByRole('heading', { name: 'Ebeveyn Yönetim Paneli' })).toHaveCount(0);
  await expect(page.getByRole('heading', { name: 'Hoş Geldiniz' })).toBeVisible();
});

test('live public catalog matches current production state', async ({ page }) => {
  await page.goto('');
  await expect(page.getByRole('heading', { name: 'Henüz Video Bulunmuyor' })).toBeVisible({ timeout: 15_000 });
});
