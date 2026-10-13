import { browser } from '$app/environment';
import { env as publicEnv } from '$env/dynamic/public';
import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';

const supabaseUrl = publicEnv.PUBLIC_SUPABASE_URL || '';
const supabasePublishableKey =
  publicEnv.PUBLIC_SUPABASE_PUBLISHABLE_KEY || publicEnv.PUBLIC_SUPABASE_ANON_KEY || '';

export let supabase: SupabaseClient | null = null;

export function getSupabaseBrowserClient(): SupabaseClient | null {
  if (!browser || supabase || !supabaseUrl || !supabasePublishableKey) {
    return supabase;
  }

  try {
    supabase = createBrowserClient(supabaseUrl, supabasePublishableKey);
  } catch (error) {
    console.warn('Failed to initialize public Supabase client:', error);
  }

  return supabase;
}

export function isSupabaseConnected(): boolean {
  return getSupabaseBrowserClient() !== null;
}