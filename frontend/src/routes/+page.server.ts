import { loadFarmWorkspace } from '$lib/server/farmData';

export async function load({ locals }) {
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return {
			farm: null,
			weather: null,
			farms: [],
			tasks: [],
			supabase: {
				configured: false,
				error: null
			},
			user: null
		};
	}

	const workspace = await loadFarmWorkspace(supabase, Boolean(user));
	const { data: farm, error: farmError } = await supabase
		.from('farms')
		.select('id, slug, name, region, latitude, longitude, timezone, is_virtual')
		.eq('slug', 'gimje-demo-farm')
		.maybeSingle();

	if (farmError || !farm) {
		return {
			farm: null,
			weather: null,
			farms: workspace.farms,
			tasks: workspace.tasks,
			supabase: {
				configured: true,
				error: farmError?.message ?? workspace.error ?? 'Demo farm was not found.'
			},
			user: user ? { id: user.id, email: user.email ?? null } : null
		};
	}

	const { data: weather, error: weatherError } = await supabase
		.from('weather_observations')
		.select(
			'observed_at, temperature_c, relative_humidity_pct, precipitation_mm, rain_mm, weather_code, wind_speed_kph, wind_direction_deg, source'
		)
		.eq('farm_id', farm.id)
		.order('observed_at', { ascending: false })
		.limit(1)
		.maybeSingle();

	return {
		farm,
		weather,
		farms: workspace.farms,
		tasks: workspace.tasks,
		supabase: {
			configured: true,
			error: weatherError?.message ?? workspace.error ?? null
		},
		user: user ? { id: user.id, email: user.email ?? null } : null
	};
}