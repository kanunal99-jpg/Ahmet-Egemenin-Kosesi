import { test, expect } from '@playwright/test';

test('CI authenticated E2E configuration is present', async () => {
  expect(process.env.E2E_EMAIL).toBeTruthy();
  expect(process.env.E2E_PASSWORD).toBeTruthy();
  expect(process.env.VITE_SUPABASE_ANON_KEY).toBeTruthy();
});
