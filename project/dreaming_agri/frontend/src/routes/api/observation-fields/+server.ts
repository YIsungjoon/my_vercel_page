import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ locals }) => {
	const supabase = locals.supabase;

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}

	const [fieldsResult, unitsResult] = await Promise.all([
		supabase
			.from('observation_fields')
			.select('code, name, event_type, value_type, canonical_unit_code, is_active')
			.eq('is_active', true)
			.order('code', { ascending: true }),
		supabase
			.from('measurement_units')
			.select('code, name, symbol, quantity_kind, is_active')
			.eq('is_active', true)
			.order('code', { ascending: true })
	]);

	if (fieldsResult.error || unitsResult.error) {
		console.error('Observation reference query failed:', {
			fields: fieldsResult.error,
			units: unitsResult.error
		});
		return json({ error: 'Unable to load observation reference data.' }, { status: 500 });
	}

	return json({
		observation_fields: fieldsResult.data ?? [],
		measurement_units: unitsResult.data ?? []
	});
};
