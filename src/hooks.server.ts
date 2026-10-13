import type { Handle } from '@sveltejs/kit';
import { handle as handleAgri } from '../project/dreaming_agri/frontend/src/hooks.server';

export const handle: Handle = ({ event, resolve }) => {
	if (event.url.pathname === '/dreaming-agri' || event.url.pathname.startsWith('/dreaming-agri/')) {
		return handleAgri({ event, resolve });
	}
	return resolve(event);
};
