export interface PriceTrendItem {
	date: string;
	price: number; // KRW
	changeRate: number; // %
}

export interface MarketPriceInfo {
	crop: string;
	variety: string;
	unit: string; // e.g. "10kg 상자"
	avgPrice: number; // 평균가
	maxPrice: number; // 최고가
	minPrice: number; // 최저가
	changeRate: number; // 전일 대비 변동률 (%)
	trendStatus: 'up' | 'down' | 'flat';
	topMarket: string; // 최고가 형성 시장 (예: 서울 가락시장)
	topMarketPrice: number;
	weeklyHistory: PriceTrendItem[];
	updatedAt: string;
}

export interface RevenueSimulation {
	boxCount: number;
	pricePerBox: number;
	totalRevenue: number;
	recommendedMarket: string;
}

/**
 * Fetch wholesale market price data for a given crop from KAMIS API endpoint
 */
export async function fetchCropMarketPrice(crop: string = '토마토'): Promise<MarketPriceInfo> {
	try {
		const res = await fetch(`/api/market?crop=${encodeURIComponent(crop)}`);
		if (!res.ok) throw new Error(`HTTP error ${res.status}`);
		const data = await res.json();
		return data.market;
	} catch (err) {
		console.warn('Market API fallback invoked:', err);
		return getFallbackMarketPrice(crop);
	}
}

/**
 * Calculate estimated harvest revenue
 */
export function simulateHarvestRevenue(boxCount: number, pricePerBox: number, recommendedMarket: string = '서울 가락도매시장'): RevenueSimulation {
	return {
		boxCount,
		pricePerBox,
		totalRevenue: boxCount * pricePerBox,
		recommendedMarket
	};
}

function getFallbackMarketPrice(crop: string): MarketPriceInfo {
	if (crop === '참외') {
		return {
			crop: '참외',
			variety: '성주 꿀참외 (상품)',
			unit: '10kg 상자',
			avgPrice: 48500,
			maxPrice: 53000,
			minPrice: 42000,
			changeRate: 2.1,
			trendStatus: 'up',
			topMarket: '서울 가락도매시장',
			topMarketPrice: 53000,
			weeklyHistory: [
				{ date: '07/18', price: 46000, changeRate: 0 },
				{ date: '07/19', price: 46500, changeRate: 1.0 },
				{ date: '07/20', price: 47000, changeRate: 1.1 },
				{ date: '07/21', price: 47200, changeRate: 0.4 },
				{ date: '07/22', price: 47800, changeRate: 1.2 },
				{ date: '07/23', price: 48000, changeRate: 0.4 },
				{ date: '07/24', price: 48500, changeRate: 1.0 }
			],
			updatedAt: new Date().toISOString()
		};
	} else if (crop === '파프리카') {
		return {
			crop: '파프리카',
			variety: '착색 파프리카 (상품)',
			unit: '5kg 상자',
			avgPrice: 29000,
			maxPrice: 32000,
			minPrice: 26000,
			changeRate: -1.5,
			trendStatus: 'down',
			topMarket: '대전 노은도매시장',
			topMarketPrice: 32000,
			weeklyHistory: [
				{ date: '07/18', price: 30000, changeRate: 0 },
				{ date: '07/19', price: 29800, changeRate: -0.6 },
				{ date: '07/20', price: 29500, changeRate: -1.0 },
				{ date: '07/21', price: 29500, changeRate: 0 },
				{ date: '07/22', price: 29200, changeRate: -1.0 },
				{ date: '07/23', price: 29400, changeRate: 0.6 },
				{ date: '07/24', price: 29000, changeRate: -1.3 }
			],
			updatedAt: new Date().toISOString()
		};
	}

	return {
		crop: '토마토',
		variety: '완숙 마이노르 (상품)',
		unit: '10kg 상자',
		avgPrice: 34500,
		maxPrice: 38000,
		minPrice: 31000,
		changeRate: 4.2,
		trendStatus: 'up',
		topMarket: '서울 가락도매시장',
		topMarketPrice: 38000,
		weeklyHistory: [
			{ date: '07/18', price: 32000, changeRate: 0 },
			{ date: '07/19', price: 32500, changeRate: 1.5 },
			{ date: '07/20', price: 33000, changeRate: 1.5 },
			{ date: '07/21', price: 33200, changeRate: 0.6 },
			{ date: '07/22', price: 33800, changeRate: 1.8 },
			{ date: '07/23', price: 34000, changeRate: 0.6 },
			{ date: '07/24', price: 34500, changeRate: 1.5 }
		],
		updatedAt: new Date().toISOString()
	};
}
