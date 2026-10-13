import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ url }) => {
	const crop = url.searchParams.get('crop') || '토마토';

	let warnings = [];

	if (crop.includes('토마토')) {
		warnings = [
			{
				crop: '토마토',
				pestName: '토마토 흰가루병 & 담배가루이',
				warningLevel: '주의',
				description: '농진청 병해충 예찰: 생식생장기 고온 다습 환경으로 잎 뒷면 흰가루병 균사체 관찰',
				preventiveAction: '황색 끈적이 트랩 10m 간격 설치, 3화방 하부 노화 엽 정리 및 5일 간격 예방 약제 살포',
				optimalConditions: '온도 25~30°C, 습도 80% 이상 지속 시',
				updatedAt: new Date().toISOString()
			},
			{
				crop: '토마토',
				pestName: '잎곰팡이병 & 궤양병',
				warningLevel: '관심',
				description: '장마 후 온실 습도 급증 시 줄기 상처 부위 병원균 침투 위험',
				preventiveAction: '적엽 작업 시 무균 가위 사용 및 소독 후 엽면 도포',
				optimalConditions: '습도 85% 이상 시',
				updatedAt: new Date().toISOString()
			}
		];
	} else if (crop.includes('참외')) {
		warnings = [
			{
				crop: '참외',
				pestName: '참외 덩굴쪼김병 & 흰가루병',
				warningLevel: '경보',
				description: '성주 지역 수확기 하우스 고온 다습에 따른 덩굴 시듦 병원균 증식 경보',
				preventiveAction: '관수 횟수 일시 조절, 덩굴 뿌리 부근 토양 소독 및 2차 수확 전 세력 점검',
				optimalConditions: '온도 28~33°C, 토양과습 시',
				updatedAt: new Date().toISOString()
			}
		];
	} else {
		warnings = [
			{
				crop,
				pestName: `${crop} 주요 균류병 및 진딧물`,
				warningLevel: '관심',
				description: '생육 환경 예찰: 온실 환기 및 유인끈 청결 유지 권장',
				preventiveAction: '주간 환기팬 정기점검 및 엽면 시비 예방 관리',
				optimalConditions: '일교차 10°C 이상 발생 시',
				updatedAt: new Date().toISOString()
			}
		];
	}

	return json({
		success: true,
		crop,
		warnings
	});
};
