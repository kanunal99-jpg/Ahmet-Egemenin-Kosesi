import { test, expect } from '@playwright/test';

test('authenticated E2E configuration is usable', async ({ page }) => {
  const email = process.env.E2E_EMAIL;
  const password = process.env.E2E_PASSWORD;
  const supabaseKey = process.env.VITE_SUPABASE_ANON_KEY;

  expect(email, 'E2E_EMAIL must be configured').toBeTruthy();
  expect(password, 'E2E_PASSWORD must be configured').toBeTruthy();
  expect(supabaseKey, 'VITE_SUPABASE_ANON_KEY must be configured').toBeTruthy();

  await page.goto('login');
  await expect(page.getByLabel('E-Posta Adresi')).toBeVisible();
  await expect(page.getByLabel('Şifre')).toBeVisible();
});
