import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ url, setHeaders }) => {
	const crop = url.searchParams.get('crop') || '토마토';

	// 1-hour cache control
	setHeaders({
		'Cache-Control': 'public, max-age=3600, s-maxage=3600'
	});

	let marketData;

	if (crop.includes('참외')) {
		marketData = {
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
	} else if (crop.includes('파프리카')) {
		marketData = {
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
	} else {
		marketData = {
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

	return json({
		success: true,
		crop,
		market: marketData
	});
};
