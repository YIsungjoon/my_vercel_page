import type { SupabaseClient } from '@supabase/supabase-js';

const FARM_FIELDS =
	'id, slug, name, region, country_code, latitude, longitude, timezone, is_virtual, created_by, created_at, updated_at, cultivation_cycles(id, crop, variety, planted_at, expected_harvest_at, growth_stage, status, notes, created_at, updated_at)';
const TASK_FIELDS =
	'id, farm_id, cultivation_cycle_id, operation_type_code, title, description, scheduled_date, category, status, priority, is_followup, parent_task_id, created_at, updated_at, task_work_areas(work_area_id, is_primary)';

export async function loadFarmWorkspace(supabase: SupabaseClient | null, authenticated: boolean) {
	if (!supabase || !authenticated) {
		return { farms: [], tasks: [], error: null };
	}

	const { data: farms, error: farmsError } = await supabase
		.from('farms')
		.select(FARM_FIELDS)
		.order('created_at', { ascending: false });

	if (farmsError) {
		return { farms: [], tasks: [], error: farmsError.message };
	}

	const farmIds = (farms ?? []).map((farm) => farm.id);
	if (farmIds.length === 0) {
		return { farms: farms ?? [], tasks: [], error: null };
	}

	const { data: tasks, error: tasksError } = await supabase
		.from('tasks')
		.select(TASK_FIELDS)
		.in('farm_id', farmIds)
		.order('scheduled_date', { ascending: true })
		.order('created_at', { ascending: true });

	return {
		farms: farms ?? [],
		tasks: tasks ?? [],
		error: tasksError?.message ?? null
	};
}
