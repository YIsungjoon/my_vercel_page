import { createServerClient } from '@supabase/ssr';
import { env as privateEnv } from '$env/dynamic/private';
import { env as publicEnv } from '$env/dynamic/public';
import type { Handle } from '@sveltejs/kit';

const supabaseUrl = privateEnv.SUPABASE_URL ?? publicEnv.PUBLIC_SUPABASE_URL;
const supabaseKey =
  privateEnv.SUPABASE_PUBLISHABLE_KEY ??
  privateEnv.SUPABASE_ANON_KEY ??
  publicEnv.PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
  publicEnv.PUBLIC_SUPABASE_ANON_KEY;

export const handle: Handle = async ({ event, resolve }) => {
  if (!supabaseUrl || !supabaseKey) {
    event.locals.supabase = null;
    event.locals.getUser = async () => null;
    return resolve(event);
  }

  const supabase = createServerClient(supabaseUrl, supabaseKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false
    },
    cookies: {
      getAll() {
        return event.cookies.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value, options } of cookiesToSet) {
          event.cookies.set(name, value, {
            ...options,
            path: '/'
          });
        }
      }
    }
  });

  event.locals.supabase = supabase;
  event.locals.getUser = async () => {
    const {
      data: { user }
    } = await supabase.auth.getUser();

    return user;
  };

  return resolve(event);
};