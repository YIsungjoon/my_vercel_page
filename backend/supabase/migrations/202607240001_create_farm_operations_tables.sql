-- Enable UUID extension if not enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Farms Table
CREATE TABLE IF NOT EXISTS public.farms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    region TEXT NOT NULL,
    crop TEXT NOT NULL,
    variety TEXT NOT NULL,
    planted_at DATE NOT NULL,
    growth_stage TEXT NOT NULL CHECK (growth_stage IN ('육묘기', '영양생장기', '생식생장기', '수확기', '수확후정리')),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Tasks Table
CREATE TABLE IF NOT EXISTS public.tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID NOT NULL REFERENCES public.farms(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    scheduled_date DATE NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('관수/시비', '환경관리', '병해충방제', '수확/정리', '후속작업', '기타')),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'skipped', 'issue')),
    priority TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('high', 'medium', 'low')),
    is_followup BOOLEAN NOT NULL DEFAULT false,
    parent_task_id UUID REFERENCES public.tasks(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Task Logs & Issue Registration Table
CREATE TABLE IF NOT EXISTS public.task_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE,
    farm_id UUID NOT NULL REFERENCES public.farms(id) ON DELETE CASCADE,
    action TEXT NOT NULL CHECK (action IN ('completed', 'skipped', 'issue')),
    note TEXT,
    photo_url TEXT,
    issue_category TEXT CHECK (issue_category IN ('병해충', '시설/장비 고장', '기상/생육 이상', '자재 부족', '기타')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. AI Consultations & Summaries Table
CREATE TABLE IF NOT EXISTS public.ai_consultations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID NOT NULL REFERENCES public.farms(id) ON DELETE CASCADE,
    question TEXT,
    answer TEXT,
    summary_report TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS Policies
ALTER TABLE public.farms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_consultations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read for farms" ON public.farms FOR SELECT USING (true);
CREATE POLICY "Allow public insert/update for farms" ON public.farms FOR ALL USING (true);

CREATE POLICY "Allow public read for tasks" ON public.tasks FOR SELECT USING (true);
CREATE POLICY "Allow public all for tasks" ON public.tasks FOR ALL USING (true);

CREATE POLICY "Allow public read for task_logs" ON public.task_logs FOR SELECT USING (true);
CREATE POLICY "Allow public all for task_logs" ON public.task_logs FOR ALL USING (true);

CREATE POLICY "Allow public read for ai_consultations" ON public.ai_consultations FOR SELECT USING (true);
CREATE POLICY "Allow public all for ai_consultations" ON public.ai_consultations FOR ALL USING (true);
