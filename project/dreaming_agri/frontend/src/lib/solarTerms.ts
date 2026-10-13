export interface SolarTermInfo {
	name: string;
	nameHanja: string;
	month: number;
	approxDay: number;
	solarLongitude: number;
	farmingAdvice: string;
	season: 'spring' | 'summer' | 'autumn' | 'winter';
	icon: string;
}

export const SOLAR_TERMS: SolarTermInfo[] = [
	{
		name: '소한',
		nameHanja: '小寒',
		month: 1,
		approxDay: 5,
		solarLongitude: 285,
		farmingAdvice: '작은 추위 발생. 온실 보온 다겹 커튼 및 야간 최저 난방 온도(15°C)점검 필수.',
		season: 'winter',
		icon: '❄️'
	},
	{
		name: '대한',
		nameHanja: '大寒',
		month: 1,
		approxDay: 20,
		solarLongitude: 300,
		farmingAdvice: '동계 최저 기온 구간. 동파 방지를 위해 양액 관수 라인 및 펌프 보온재 점검.',
		season: 'winter',
		icon: '☃️'
	},
	{
		name: '입춘',
		nameHanja: '立春',
		month: 2,
		approxDay: 4,
		solarLongitude: 315,
		farmingAdvice: '봄의 시작. 육묘 파종 준비 및 차년도 작기 환기/일조량 계획 점검.',
		season: 'spring',
		icon: '🌱'
	},
	{
		name: '우수',
		nameHanja: '雨水',
		month: 2,
		approxDay: 19,
		solarLongitude: 330,
		farmingAdvice: '얼음이 녹고 비가 내림. 뿌리 활력을 돕기 위한 약한 관수 개시.',
		season: 'spring',
		icon: '🌧️'
	},
	{
		name: '경칩',
		nameHanja: '驚蟄',
		month: 3,
		approxDay: 6,
		solarLongitude: 345,
		farmingAdvice: '월동 개구리가 깨어남. 하우스 주변 1차 병해충 방제 및 환경 정비.',
		season: 'spring',
		icon: '🐸'
	},
	{
		name: '춘분',
		nameHanja: '春分',
		month: 3,
		approxDay: 21,
		solarLongitude: 0,
		farmingAdvice: '낮과 밤의 길이가 같음. 봄 작물(토마토, 참외) 정식 작업 집중 시기.',
		season: 'spring',
		icon: '🌸'
	},
	{
		name: '청명',
		nameHanja: '清明',
		month: 4,
		approxDay: 5,
		solarLongitude: 15,
		farmingAdvice: '날씨가 맑고 온화함. 토양 시비 작업 및 양액 EC 2.2 표준 세팅.',
		season: 'spring',
		icon: '☀️'
	},
	{
		name: '곡우',
		nameHanja: '穀雨',
		month: 4,
		approxDay: 20,
		solarLongitude: 30,
		farmingAdvice: '농사비가 내림. 줄기 유인 및 곁순 제거로 초세 균형 확보.',
		season: 'spring',
		icon: '🌾'
	},
	{
		name: '입하',
		nameHanja: '立夏',
		month: 5,
		approxDay: 5,
		solarLongitude: 45,
		farmingAdvice: '여름의 시작. 주간 기온 상승 대비 측창 환기 스케줄 자동화 확인.',
		season: 'summer',
		icon: '🌿'
	},
	{
		name: '소만',
		nameHanja: '小滿',
		month: 5,
		approxDay: 21,
		solarLongitude: 60,
		farmingAdvice: '햇볕이 풍부함. 1차 화방 착과 확인 및 적과 작업 시행.',
		season: 'summer',
		icon: '☀️'
	},
	{
		name: '망종',
		nameHanja: '芒種',
		month: 6,
		approxDay: 6,
		solarLongitude: 75,
		farmingAdvice: '씨뿌리기 및 수확 적기. 수확 엽 적엽 및 하부 통풍성 확보.',
		season: 'summer',
		icon: '🌾'
	},
	{
		name: '하지',
		nameHanja: '夏至',
		month: 6,
		approxDay: 21,
		solarLongitude: 90,
		farmingAdvice: '낮이 가장 김. 차광막(30% 차광) 가동으로 온실 내부 고온 예방.',
		season: 'summer',
		icon: '🌻'
	},
	{
		name: '소서',
		nameHanja: '小暑',
		month: 7,
		approxDay: 7,
		solarLongitude: 105,
		farmingAdvice: '작은 더위와 장마철. 고습도로 인한 흰가루병/곰팡이병 예방 방제 집중.',
		season: 'summer',
		icon: '⛈️'
	},
	{
		name: '대서',
		nameHanja: '大暑',
		month: 7,
		approxDay: 22,
		solarLongitude: 120,
		farmingAdvice: '큰 더위 삼복철. 엽면 스프레이 및 양액 EC 2.0 미세 하향 조정.',
		season: 'summer',
		icon: '🔥'
	},
	{
		name: '입추',
		nameHanja: '立秋',
		month: 8,
		approxDay: 7,
		solarLongitude: 135,
		farmingAdvice: '가을의 시작. 수확기 세력 유지용 영양제 조절 공급.',
		season: 'autumn',
		icon: '🍁'
	},
	{
		name: '처서',
		nameHanja: '處暑',
		month: 8,
		approxDay: 23,
		solarLongitude: 150,
		farmingAdvice: '더위가 꺾임. 야간 일교차 확대에 맞춘 환기 스케줄 보정.',
		season: 'autumn',
		icon: '🌬️'
	},
	{
		name: '백로',
		nameHanja: '白露',
		month: 9,
		approxDay: 7,
		solarLongitude: 165,
		farmingAdvice: '이슬이 내림. 수확기 과실 당도 및 적색 착색률 관리 집중.',
		season: 'autumn',
		icon: '💧'
	},
	{
		name: '추분',
		nameHanja: '秋分',
		month: 9,
		approxDay: 23,
		solarLongitude: 180,
		farmingAdvice: '밤이 길어짐. 야간 온도 하강 대비 차광막 보온 모드 전환.',
		season: 'autumn',
		icon: '🌕'
	},
	{
		name: '한로',
		nameHanja: '寒露',
		month: 10,
		approxDay: 8,
		solarLongitude: 195,
		farmingAdvice: '찬 이슬 내림. 서리 피해 방지를 위해 야간 최저 온실 16°C 설정.',
		season: 'autumn',
		icon: '🍂'
	},
	{
		name: '상강',
		nameHanja: '霜降',
		month: 10,
		approxDay: 23,
		solarLongitude: 210,
		farmingAdvice: '첫서리가 내림. 수확 마무리 및 노화 엽 2차 수거 정돈.',
		season: 'autumn',
		icon: '🍁'
	},
	{
		name: '입동',
		nameHanja: '立冬',
		month: 11,
		approxDay: 7,
		solarLongitude: 225,
		farmingAdvice: '겨울의 시작. 난방기 시운전 및 양액 관수 라인 배관 점검.',
		season: 'winter',
		icon: '❄️'
	},
	{
		name: '소설',
		nameHanja: '小雪',
		month: 11,
		approxDay: 22,
		solarLongitude: 240,
		farmingAdvice: '첫눈 내림. 하우스 겉비닐 및 보온 덮개 자동 작동 상태 확인.',
		season: 'winter',
		icon: '🌨️'
	},
	{
		name: '대설',
		nameHanja: '大雪',
		month: 12,
		approxDay: 7,
		solarLongitude: 255,
		farmingAdvice: '큰눈 내림. 적설 피해 예방용 하우스 수동 열선 제어 준비.',
		season: 'winter',
		icon: '⛄'
	},
	{
		name: '동지',
		nameHanja: '冬至',
		month: 12,
		approxDay: 22,
		solarLongitude: 270,
		farmingAdvice: '밤이 가장 김. 동계 수확 유지 및 야간 일조 부족 보광등 점검.',
		season: 'winter',
		icon: '🌌'
	}
];

/**
 * Returns solar term info if given date (YYYY-MM-DD) matches or falls near a 24 solar term
 */
export function getSolarTermForDate(dateStr: string): SolarTermInfo | null {
	const d = new Date(dateStr);
	const month = d.getMonth() + 1;
	const day = d.getDate();

	for (const term of SOLAR_TERMS) {
		if (term.month === month && Math.abs(term.approxDay - day) <= 1) {
			return term;
		}
	}
	return null;
}

/**
 * Returns list of solar terms for a given month (1~12)
 */
export function getSolarTermsForMonth(month: number): SolarTermInfo[] {
	return SOLAR_TERMS.filter((t) => t.month === month);
}
