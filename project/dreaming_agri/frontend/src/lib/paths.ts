// The portal mounts this service here; standalone development uses an empty base.
export const serviceBase: string = import.meta.env.VITE_DREAMING_AGRI_BASE_PATH ?? '';

export function appPath(path: string): string {
	if (!path.startsWith('/') || path.startsWith('//') || path.includes('\\')) return serviceBase || '/';
	if (serviceBase && (path === serviceBase || path.startsWith(serviceBase + '/') || path.startsWith(serviceBase + '?'))) return path;
	return serviceBase + (path === '/' ? '' : path) || '/';
}

export function loginPath(next: string): string {
	return appPath('/auth') + '?next=' + encodeURIComponent(appPath(next));
}
