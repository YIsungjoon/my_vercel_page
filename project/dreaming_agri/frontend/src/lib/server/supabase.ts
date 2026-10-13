import { env as privateEnv } from '$env/dynamic/private';
import { env as publicEnv } from '$env/dynamic/public';
import { createClient } from '@supabase/supabase-js';

export function createServerSupabaseClient() {
	const url = privateEnv.SUPABASE_URL ?? publicEnv.PUBLIC_SUPABASE_URL;
	const key =
		privateEnv.SUPABASE_PUBLISHABLE_KEY ??
		privateEnv.SUPABASE_ANON_KEY ??
		publicEnv.PUBLIC_SUPABASE_PUBLISHABLE_KEY;

	if (!url || !key) {
		return null;
	}

	return createClient(url, key, {
		auth: {
			autoRefreshToken: false,
			persistSession: false
		}
	});
}
