import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ locals }) => {
	const supabase = locals.supabase;

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}

	const { data, error } = await supabase
		.from('agri_operation_types')
		.select('code, name_ko, description, sort_order, is_active')
		.eq('is_active', true)
		.order('sort_order', { ascending: true });

	if (error) {
		console.error('Operation type query failed:', error);
		return json({ error: 'Unable to load operation types.' }, { status: 500 });
	}

	return json({ operation_types: data ?? [] });
};
