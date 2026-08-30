import { test, expect } from '@playwright/test';

test('registration page does not expose a selectable elevated role', async ({ page }) => {
  await page.goto('register');
  await expect(page.getByText('parent', { exact: true })).toHaveCount(0);
  await expect(page.getByText('publisher', { exact: true })).toHaveCount(0);
  await expect(page.getByText('admin', { exact: true })).toHaveCount(0);
  await expect(page.locator('input[name="role"]')).toHaveCount(0);
});
