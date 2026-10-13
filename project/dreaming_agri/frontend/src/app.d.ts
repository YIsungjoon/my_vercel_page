import type { SupabaseClient, User } from '@supabase/supabase-js';

// See https://svelte.dev/docs/kit/types#app.d.ts
declare global {
  namespace App {
    interface Locals {
      supabase: SupabaseClient | null;
      getUser: () => Promise<User | null>;
    }
  }
}

export {};