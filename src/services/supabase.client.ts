import { createClient, SupabaseClient } from '@supabase/supabase-js';

const env = (import.meta as unknown as { env: Record<string, string | undefined> }).env || {};
const supabaseUrl = env.VITE_SUPABASE_URL || '';
const supabaseAnonKey = env.VITE_SUPABASE_ANON_KEY || '';

export const isSupabaseConfigured = Boolean(
  supabaseUrl &&
    supabaseUrl !== 'https://your-project.supabase.co' &&
    supabaseAnonKey &&
    supabaseAnonKey !== 'your-anon-key'
);

if (!isSupabaseConfigured) {
  console.warn(
    '[Supabase] VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY is missing or invalid. Application is running in frontend structural mock mode.'
  );
}

// Fallback dummy URL to prevent createClient from crashing if unconfigured
const effectiveUrl = isSupabaseConfigured ? supabaseUrl : 'https://dummy.supabase.co';
const effectiveKey = isSupabaseConfigured ? supabaseAnonKey : 'dummy-key';

export const supabase: SupabaseClient = createClient(effectiveUrl, effectiveKey);
