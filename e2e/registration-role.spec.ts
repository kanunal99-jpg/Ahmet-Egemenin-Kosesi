import { test, expect } from '@playwright/test';

test('registration does not submit a client-controlled elevated role', async ({ page }) => {
  let signupPayload: Record<string, unknown> | null = null;

  await page.route('**/auth/v1/signup', async (route) => {
    signupPayload = route.request().postDataJSON() as Record<string, unknown>;
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ user: null, session: null }),
    });
  });

  await page.goto('register');
  await page.locator('input[placeholder="Ahmet"]').fill('Test');
  await page.locator('input[placeholder="ornek@eposta.com"]').fill(`audit-${Date.now()}@example.com`);
  await page.locator('input[type="password"]').fill('TestPassword123!');
  await page.getByRole('button', { name: 'Hesap Oluştur' }).click();

  await expect.poll(() => signupPayload).not.toBeNull();
  expect(signupPayload).toBeTruthy();
  const options = (signupPayload?.options ?? {}) as { data?: Record<string, unknown> };
  expect(options.data?.role).toBeUndefined();
  expect(options.data?.first_name).toBe('Test');
});
