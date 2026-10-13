import { dev } from '$app/environment';

export interface Service {
	id: string;
	name: string;
	kicker: string;
	category: string;
	description: string;
	tags: string[];
	href: string | null;
	sourceUrl: string;
	local: boolean;
	icon?: 'sprout' | 'grid';
}

function serviceUrl(value: string | undefined): string | null {
	if (!value?.trim()) return null;
	try {
		const url = new URL(value.trim());
		if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password) {
			throw new Error('Expected a public HTTP(S) URL without credentials.');
		}
		return url.href;
	} catch {
		throw new Error('VITE_DREAMING_AGRI_URL must be a valid public HTTP(S) URL.');
	}
}

const productionUrl = serviceUrl(import.meta.env.VITE_DREAMING_AGRI_URL);

// Add one entry here for each independent application under project/<service-name>.
export const services: Service[] = [
	{
		id: 'dreaming-agri',
		name: 'Dreaming Agri',
		kicker: '꿈꾸는 농업',
		category: '농업·스마트팜',
		description: '생육 환경, 작업 일정, 도매 시세와 AI 도우미를 제공하는 농장 운영 관리 서비스.',
		tags: ['농장 관리', '작업 일정', 'AI 도우미'],
		href: productionUrl ?? (dev ? 'http://localhost:5174' : null),
		sourceUrl: 'https://github.com/YIsungjoon/my_vercel_page/tree/main/project/dreaming_agri',
		local: dev && !productionUrl,
		icon: 'sprout'
	}
];

export const categories = [...new Set(services.map((service) => service.category))];
