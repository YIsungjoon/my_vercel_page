import { json } from '@sveltejs/kit';
import { isUuid, requiredText, uuidArray } from '$lib/server/apiValidation';
import { COLLECTION_AGENT_KINDS } from '$lib/server/observationValidation';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ params, locals }) => {
	const farmId = params.farmId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) return json({ error: 'Supabase is not configured.' }, { status: 503 });
	if (!user) return json({ error: 'Authentication is required.' }, { status: 401 });
	if (!isUuid(farmId)) return json({ error: 'Invalid farm id.' }, { status: 400 });

	const { data, error } = await supabase
		.from('collection_agents')
		.select(
			'id, farm_id, agent_code, name, agent_kind, status, authentication_mode, last_seen_at, version, status_reason_code, status_note, status_changed_at, created_by, updated_by, created_at, updated_at, collection_agent_sources(source_id, status, version, grant_reason_code, grant_note, granted_by, granted_at, revoked_by, revoked_at, revocation_reason_code, revocation_note, updated_at)'
		)
		.eq('farm_id', farmId)
		.order('agent_code', { ascending: true });

	if (error) {
		console.error('Collection agent list query failed:', error);
		return json({ error: 'Unable to load collection agents.' }, { status: 500 });
	}

	return json({ collection_agents: data ?? [] });
};

export const POST: RequestHandler = async ({ params, request, locals }) => {
	const farmId = params.farmId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) return json({ error: 'Supabase is not configured.' }, { status: 503 });
	if (!user) return json({ error: 'Authentication is required.' }, { status: 401 });
	if (!isUuid(farmId)) return json({ error: 'Invalid farm id.' }, { status: 400 });

	try {
		const body = (await request.json()) as Record<string, unknown>;
		const agentKind = requiredText(body.agent_kind, 'agent_kind');
		if (!COLLECTION_AGENT_KINDS.includes(agentKind)) {
			throw new Error('agent_kind is not supported.');
		}

		const authorizedSourceIds = uuidArray(
			body.authorized_source_ids,
			'authorized_source_ids'
		);
		if (authorizedSourceIds.length === 0) {
			throw new Error('authorized_source_ids must contain at least one source.');
		}

		const { data, error } = await supabase.rpc('create_collection_agent', {
			target_farm_id: farmId,
			agent_code: requiredText(body.agent_code, 'agent_code'),
			agent_name: requiredText(body.name, 'name'),
			agent_kind: agentKind,
			authorized_source_ids: authorizedSourceIds
		});

		if (error) {
			console.error('Collection agent creation failed:', error);
			return json({ error: 'Unable to create collection agent.' }, { status: 400 });
		}

		return json(data, { status: 201 });
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid collection agent request.' },
			{ status: 400 }
		);
	}
};
