export interface WeatherInfo {
	region: string;
	temperature: number; // °C
	humidity: number; // %
	precipitationProbability: number; // %
	skyCondition: 'sunny' | 'cloudy' | 'rainy' | 'snowy';
	warningType: 'none' | 'frost' | 'heatwave' | 'high_humidity' | 'heavy_rain';
	warningMessage: string;
	recommendation: string;
	updatedAt: string;
}

export interface PestWarningInfo {
	crop: string;
	pestName: string;
	warningLevel: '관심' | '주의' | '경보';
	description: string;
	preventiveAction: string;
	optimalConditions: string;
	updatedAt: string;
}

/**
 * Fetch agricultural weather forecast and microclimate warnings for a given region
 */
export async function fetchAgriculturalWeather(region: string = '전북특별자치도 김제시'): Promise<WeatherInfo> {
	try {
		const res = await fetch(`/api/weather?region=${encodeURIComponent(region)}`);
		if (!res.ok) throw new Error(`HTTP error ${res.status}`);
		const data = await res.json();
		return data.weather;
	} catch (err) {
		console.warn('Weather API fallback invoked:', err);
		return getFallbackWeather(region);
	}
}

/**
 * Fetch agricultural pest and disease warning data for a given crop
 */
export async function fetchPestWarnings(crop: string = '토마토'): Promise<PestWarningInfo[]> {
	try {
		const res = await fetch(`/api/pest?crop=${encodeURIComponent(crop)}`);
		if (!res.ok) throw new Error(`HTTP error ${res.status}`);
		const data = await res.json();
		return data.warnings;
	} catch (err) {
		console.warn('Pest API fallback invoked:', err);
		return getFallbackPestWarnings(crop);
	}
}

function getFallbackWeather(region: string): WeatherInfo {
	return {
		region,
		temperature: 28.5,
		humidity: 82,
		precipitationProbability: 40,
		skyCondition: 'cloudy',
		warningType: 'high_humidity',
		warningMessage: '⚠️ 고습도(82%) 농업 주의보: 곰팡이병 발생 위험 고조',
		recommendation: '하부 잎 적엽을 통해 통풍을 확보하고, 온실 환기팬 가동 및 5일 간격 예방 방제제를 준비하세요.',
		updatedAt: new Date().toISOString()
	};
}

function getFallbackPestWarnings(crop: string): PestWarningInfo[] {
	if (crop === '참외') {
		return [
			{
				crop: '참외',
				pestName: '흰가루병 & 덩굴쪼김병',
				warningLevel: '경보',
				description: '야간 온습도차 및 토양 다습 조건에서 덩굴 병원균 증식 활성화',
				preventiveAction: '관수량 20% 일시 감축, 토양 배수 점검 및 친환경 수화제 엽면 살포',
				optimalConditions: '온도 22~28°C, 습도 75% 이상',
				updatedAt: new Date().toISOString()
			}
		];
	}

	return [
		{
			crop: '토마토',
			pestName: '토마토 흰가루병 & 담배가루이',
			warningLevel: '주의',
			description: '생식생장기 고온 다습 환경으로 잎 뒷면 균사체 및 진딧물/가루이류 관찰',
			preventiveAction: '황색 끈적이 트랩 설치, 3화방 하부 노화 엽 정리 및 5일 간격 예방 약제 살포',
			optimalConditions: '온도 25~30°C, 습도 80% 이상',
			updatedAt: new Date().toISOString()
		},
		{
			crop: '토마토',
			pestName: '궤양병 & 잎곰팡이병',
			warningLevel: '관심',
			description: '장마 및 과습 시 줄기 상처 부위 유입 주의',
			preventiveAction: '적엽 작업 후 상처 부위 즉시 소독 및 온실 차광막 가동',
			optimalConditions: '습도 85% 이상 장시간 지속 시',
			updatedAt: new Date().toISOString()
		}
	];
}
