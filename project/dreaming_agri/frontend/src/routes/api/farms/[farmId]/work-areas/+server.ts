import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const AREA_TYPES = [
	'farm',
	'field',
	'block',
	'greenhouse',
	'house',
	'bay',
	'bed',
	'zone',
	'facility'
];

function requiredText(value: unknown, field: string) {
	if (typeof value !== 'string' || !value.trim()) {
		throw new Error(field + ' is required.');
	}

	return value.trim();
}

function optionalUuid(value: unknown, field: string) {
	if (value === undefined || value === null || value === '') {
		return null;
	}

	const parsed = requiredText(value, field);
	if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(parsed)) {
		throw new Error(field + ' must be a valid UUID.');
	}

	return parsed;
}

function isUuid(value: string) {
	return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

export const GET: RequestHandler = async ({ params, locals }) => {
	const farmId = params.farmId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}
	if (!user) {
		return json({ error: 'Authentication is required.' }, { status: 401 });
	}
	if (!isUuid(farmId)) {
		return json({ error: 'Invalid farm id.' }, { status: 400 });
	}

	const { data, error } = await supabase
		.from('farm_work_areas')
		.select(
			'id, farm_id, parent_area_id, code, name, area_type, area_m2, is_active, created_at, updated_at'
		)
		.eq('farm_id', farmId)
		.order('code', { ascending: true });

	if (error) {
		console.error('Work area list query failed:', error);
		return json({ error: 'Unable to load work areas.' }, { status: 500 });
	}

	return json({ work_areas: data ?? [] });
};

export const POST: RequestHandler = async ({ params, request, locals }) => {
	const farmId = params.farmId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}
	if (!user) {
		return json({ error: 'Authentication is required.' }, { status: 401 });
	}
	if (!isUuid(farmId)) {
		return json({ error: 'Invalid farm id.' }, { status: 400 });
	}

	try {
		const body = await request.json();
		const code = requiredText(body.code, 'code');
		const name = requiredText(body.name, 'name');
		const areaType = requiredText(body.area_type, 'area_type');
		const parentAreaId = optionalUuid(body.parent_area_id, 'parent_area_id');
		const areaM2 =
			body.area_m2 === undefined || body.area_m2 === null || body.area_m2 === ''
				? null
				: Number(body.area_m2);
		if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(code)) {
			throw new Error('code has an invalid format.');
		}
		if (!AREA_TYPES.includes(areaType)) {
			throw new Error('area_type is not supported.');
		}
		if (areaM2 !== null && (!Number.isFinite(areaM2) || areaM2 < 0)) {
			throw new Error('area_m2 must be a non-negative number.');
		}

		const { data, error } = await supabase
			.from('farm_work_areas')
			.insert({
				farm_id: farmId,
				parent_area_id: parentAreaId,
				code,
				name,
				area_type: areaType,
				area_m2: areaM2,
				is_active: body.is_active !== false
			})
			.select(
				'id, farm_id, parent_area_id, code, name, area_type, area_m2, is_active, created_at, updated_at'
			)
			.single();

		if (error) {
			console.error('Work area creation failed:', error);
			return json({ error: 'Unable to create work area.' }, { status: 400 });
		}

		return json({ work_area: data }, { status: 201 });
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid work area request.' },
			{ status: 400 }
		);
	}
};
