export interface EnvironmentalSample {
	timestamp: string;
	temperature_c: number;
	relative_humidity_pct: number;
	co2_ppm: number;
	solar_radiation_wm2: number;
	ec_ms_cm: number;
	ph: number;
	soil_moisture_pct: number;
}

export interface SyntheticDataOptions {
	crop: string;
	days?: number;
	anomalyType?: 'powdery_mildew_risk' | 'drought' | 'heatwave' | 'normal';
}

/**
 * Generates reproducible virtual farm environmental time-series data
 */
export function generateSyntheticEnvironment(options: SyntheticDataOptions): EnvironmentalSample[] {
	const days = options.days ?? 7;
	const samples: EnvironmentalSample[] = [];
	const now = Date.now();

	for (let i = days * 24; i >= 0; i--) {
		const time = new Date(now - i * 3600 * 1000);
		const hour = time.getHours();

		// Diurnal cycle simulation
		const tempSine = Math.sin(((hour - 6) / 24) * 2 * Math.PI);
		let temp = 22 + tempSine * 5 + (Math.random() - 0.5) * 0.8;
		let humidity = 65 - tempSine * 15 + (Math.random() - 0.5) * 2;
		let co2 = hour >= 6 && hour <= 18 ? 450 + (Math.random() - 0.5) * 30 : 650 + (Math.random() - 0.5) * 40;
		let solar = hour >= 6 && hour <= 18 ? Math.max(0, Math.sin(((hour - 6) / 12) * Math.PI) * 750) : 0;
		let ec = 2.2 + (Math.random() - 0.5) * 0.1;
		let ph = 5.8 + (Math.random() - 0.5) * 0.1;
		let soilMoisture = 72 + (Math.random() - 0.5) * 3;

		// Inject realistic environmental anomalies
		if (options.anomalyType === 'powdery_mildew_risk') {
			humidity += 18; // High humidity > 80% triggers mildew risk
			temp -= 2;
		} else if (options.anomalyType === 'heatwave') {
			temp += 6;
			humidity -= 15;
		} else if (options.anomalyType === 'drought') {
			soilMoisture -= 25;
			ec += 0.4;
		}

		samples.push({
			timestamp: time.toISOString(),
			temperature_c: Math.round(temp * 10) / 10,
			relative_humidity_pct: Math.min(99, Math.max(30, Math.round(humidity * 10) / 10)),
			co2_ppm: Math.round(co2),
			solar_radiation_wm2: Math.round(solar),
			ec_ms_cm: Math.round(ec * 100) / 100,
			ph: Math.round(ph * 100) / 100,
			soil_moisture_pct: Math.round(soilMoisture * 10) / 10
		});
	}

	return samples;
}
