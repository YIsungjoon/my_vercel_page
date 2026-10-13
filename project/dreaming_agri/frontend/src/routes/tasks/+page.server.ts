import { loadFarmWorkspace } from '$agri/server/farmData';

export async function load({ locals }: { locals: App.Locals }) {
	const user = await locals.getUser();
	const workspace = loadFarmWorkspace(locals.supabase, Boolean(user));

	return {
		...(await workspace),
		authenticated: Boolean(user)
	};
}
