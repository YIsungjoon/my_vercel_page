
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

// Add one entry here for each independent application under project/<service-name>.
export const services: Service[] = [
	{
		id: 'dreaming-agri',
		name: 'Dreaming Agri',
		kicker: '꿈꾸는 농업',
		category: '농업·스마트팜',
		description: '생육 환경, 작업 일정, 도매 시세와 AI 도우미를 제공하는 농장 운영 관리 서비스.',
		tags: ['농장 관리', '작업 일정', 'AI 도우미'],
		href: '/dreaming-agri',
		sourceUrl: 'https://github.com/YIsungjoon/my_vercel_page/tree/main/project/dreaming_agri',
		local: false,
		icon: 'sprout'
	},
	{
		id: 'ai-practice',
		name: 'Practice Lab',
		kicker: '문제 연습과 모의고사',
		category: '학습·자격증',
		description: 'AI 역량평가부터 자격증·공무원 시험까지, 과정별 문제은행·모의고사·오답 복습을 제공하는 학습 서비스.',
		tags: ['문제은행', '모의고사', '오답노트'],
		href: '/ai-practice',
		sourceUrl: 'https://github.com/YIsungjoon/my_vercel_page/tree/main/project/ai-practice',
		local: false,
		icon: 'grid'
	}
];

export const categories = [...new Set(services.map((service) => service.category))];
