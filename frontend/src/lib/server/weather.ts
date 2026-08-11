import type { SupabaseClient } from '@supabase/supabase-js';

type StoredWeather = {
  region: string;
  temperature: number;
  humidity: number;
  precipitationProbability: number;
  skyCondition: 'sunny' | 'cloudy' | 'rainy' | 'snowy';
  warningType: 'none' | 'frost' | 'heatwave' | 'high_humidity' | 'heavy_rain';
  warningMessage: string;
  recommendation: string;
  updatedAt: string;
};

function classifyWeatherCode(code: number): StoredWeather['skyCondition'] {
  if (code >= 71 && code <= 86) return 'snowy';
  if (code >= 51 && code <= 67) return 'rainy';
  if (code >= 80 && code <= 99) return 'rainy';
  if (code >= 1 && code <= 48) return 'cloudy';
  return 'sunny';
}

function buildWarning(temperature: number, humidity: number) {
  if (temperature >= 30) {
    return {
      warningType: 'heatwave' as const,
      warningMessage: '고온 관측 (' + temperature + '°C): 시설 환기와 차광을 확인하세요.',
      recommendation: '관수량과 환기 상태를 현장에서 확인하세요.'
    };
  }

  if (temperature <= 5) {
    return {
      warningType: 'frost' as const,
      warningMessage: '저온 관측 (' + temperature + '°C): 보온 상태를 확인하세요.',
      recommendation: '야간 보온과 동해 위험 구역을 점검하세요.'
    };
  }

  if (humidity >= 80) {
    return {
      warningType: 'high_humidity' as const,
      warningMessage: '고습 관측 (' + humidity + '%): 병해충 발생 조건을 확인하세요.',
      recommendation: '환기와 잎 표면 결로 여부를 확인하세요.'
    };
  }

  return {
    warningType: 'none' as const,
    warningMessage: '정상 농업 관측 조건 (' + temperature + '°C, 습도 ' + humidity + '%).',
    recommendation: '현재 관리 계획을 유지하세요.'
  };
}

export async function getLatestFarmWeather(
  supabase: SupabaseClient | null,
  region: string
): Promise<StoredWeather | null> {
  if (!supabase) return null;

  try {
    const { data: farm, error: farmError } = await supabase
      .from('farms')
      .select('id, name, region')
      .ilike('region', '%' + region + '%')
      .order('is_virtual', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (farmError || !farm) return null;

    const { data: observation, error: observationError } = await supabase
      .from('weather_observations')
      .select(
        'observed_at, temperature_c, relative_humidity_pct, precipitation_mm, weather_code'
      )
      .eq('farm_id', farm.id)
      .order('observed_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (observationError || !observation) return null;

    const observedAt = new Date(observation.observed_at);
    if (Number.isNaN(observedAt.getTime())) return null;
    if (Date.now() - observedAt.getTime() > 2 * 60 * 60 * 1000) return null;

    const temperature = Number(observation.temperature_c);
    const humidity = Number(observation.relative_humidity_pct);
    const precipitation = Number(observation.precipitation_mm);
    const weatherCode = Number(observation.weather_code);

    if (![temperature, humidity, precipitation, weatherCode].every(Number.isFinite)) {
      return null;
    }

    const warning = buildWarning(temperature, humidity);

    return {
      region: farm.region,
      temperature,
      humidity,
      precipitationProbability: 0,
      skyCondition: classifyWeatherCode(weatherCode),
      ...warning,
      updatedAt: observedAt.toISOString()
    };
  } catch (error) {
    console.warn('Stored weather lookup failed:', error);
    return null;
  }
}