import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const DEFAULT_FARM_LOCATION = {
  country_code: 'KR',
  latitude: 35.80167,
  longitude: 126.88889,
  timezone: 'Asia/Seoul'
};

function requiredText(value: unknown, field: string) {
  if (typeof value !== 'string' || !value.trim()) {
    throw new Error(field + ' is required.');
  }

  return value.trim();
}

function optionalText(value: unknown) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function numberOrDefault(value: unknown, fallback: number, field: string) {
  if (value === undefined || value === null || value === '') return fallback;

  const numberValue = Number(value);
  if (!Number.isFinite(numberValue)) {
    throw new Error(field + ' must be a number.');
  }

  return numberValue;
}

export const GET: RequestHandler = async ({ locals }) => {
  const supabase = locals.supabase;

  if (!supabase) {
    return json({ error: 'Supabase is not configured.' }, { status: 503 });
  }

  const { data, error } = await supabase
    .from('farms')
    .select(
      'id, slug, name, region, country_code, latitude, longitude, timezone, is_virtual, created_by, created_at, updated_at, cultivation_cycles(*)'
    )
    .order('created_at', { ascending: false });

  if (error) {
    console.error('Farm list query failed:', error);
    return json({ error: 'Unable to load farms.' }, { status: 500 });
  }

  return json({ farms: data });
};

export const POST: RequestHandler = async ({ request, locals }) => {
  const supabase = locals.supabase;
  const user = await locals.getUser();

  if (!supabase) {
    return json({ error: 'Supabase is not configured.' }, { status: 503 });
  }

  if (!user) {
    return json({ error: 'Authentication is required.' }, { status: 401 });
  }

  try {
    const body = await request.json();
    const name = requiredText(body.name, 'name');
    const region = requiredText(body.region, 'region');
    const crop = requiredText(body.crop, 'crop');
    const variety = requiredText(body.variety, 'variety');
    const plantedAt = requiredText(body.planted_at, 'planted_at');
    const growthStage = requiredText(body.growth_stage, 'growth_stage');
    const slug = optionalText(body.slug) ?? 'farm-' + crypto.randomUUID().slice(0, 8);

    const { data, error } = await supabase.rpc('create_farm_with_cycle', {
      farm_slug: slug,
      farm_name: name,
      farm_region: region,
      farm_country_code: optionalText(body.country_code) ?? DEFAULT_FARM_LOCATION.country_code,
      farm_latitude: numberOrDefault(
        body.latitude,
        DEFAULT_FARM_LOCATION.latitude,
        'latitude'
      ),
      farm_longitude: numberOrDefault(
        body.longitude,
        DEFAULT_FARM_LOCATION.longitude,
        'longitude'
      ),
      farm_timezone: optionalText(body.timezone) ?? DEFAULT_FARM_LOCATION.timezone,
      cycle_crop: crop,
      cycle_variety: variety,
      cycle_planted_at: plantedAt,
      cycle_growth_stage: growthStage,
      cycle_notes: optionalText(body.notes)
    });

    if (error) {
      console.error('Farm creation RPC failed:', error);
      return json({ error: 'Unable to create farm.' }, { status: 400 });
    }

    return json(data, { status: 201 });
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : 'Invalid farm request.' },
      { status: 400 }
    );
  }
};