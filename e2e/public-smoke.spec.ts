import { test, expect } from '@playwright/test';

// Guest-only coverage: does not depend on an authenticated test account,
// production catalog contents, or privileged database credentials.
test('public homepage and filters remain accessible', async ({ page }) => {
  await page.goto('');
  await expect(page.getByRole('heading', { name: 'Eğlenceli ve Eğitici İçerikler Burada!' })).toBeVisible();

  const search = page.getByRole('textbox', { name: 'Video veya konu ara...' });
  await expect(search).toBeVisible();
  await search.fill('hayvan');
  await expect(search).toHaveValue('hayvan');

  const category = page.getByRole('button', { name: 'Masallar', exact: true });
  await category.click();
  await expect(category).toHaveAttribute('aria-pressed', 'true');
});

test('guests cannot access parent dashboard or protected history', async ({ page }) => {
  await page.goto('parent-panel');
  await expect(page).toHaveURL(/\/login(?:\?|$)/);
  await expect(page.getByRole('heading', { name: 'Ebeveyn Yönetim Paneli' })).toHaveCount(0);
  await expect(page.getByRole('heading', { name: 'Hoş Geldiniz' })).toBeVisible();

  await page.goto('history');
  await expect(page).toHaveURL(/\/login(?:\?|$)/);
});

test('login and registration UI do not expose privileged role selection', async ({ page }) => {
  await page.goto('login');
  await expect(page.getByLabel('E-Posta Adresi')).toBeVisible();
  await expect(page.getByLabel('Şifre')).toBeVisible();

  await page.goto('register');
  await expect(page.locator('input[name="role"]')).toHaveCount(0);
  await expect(page.getByText('admin', { exact: true })).toHaveCount(0);
  await expect(page.getByText('parent', { exact: true })).toHaveCount(0);
});
