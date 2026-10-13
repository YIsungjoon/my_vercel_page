-- Chat Conversations & Performance Analytics Table
CREATE TABLE IF NOT EXISTS public.chat_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL DEFAULT gen_random_uuid(),
    farm_id UUID REFERENCES public.farms(id) ON DELETE SET NULL,
    
    -- Essential Message Content
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    content TEXT NOT NULL,
    
    -- Agricultural Domain Context
    crop TEXT,
    growth_stage TEXT,
    
    -- AI Model & Performance Metrics
    model TEXT NOT NULL,
    mode TEXT NOT NULL DEFAULT 'chat' CHECK (mode IN ('chat', 'agent')),
    latency_ms INTEGER,
    prompt_tokens INTEGER,
    completion_tokens INTEGER,
    total_tokens INTEGER,
    http_status INTEGER DEFAULT 200,
    
    -- Reasoning & RAG Evidence Traces
    reasoning_content TEXT,
    retrieved_doc_ids JSONB DEFAULT '[]'::jsonb,
    
    -- Feedback & Quality Metrics
    user_feedback_score INTEGER CHECK (user_feedback_score BETWEEN 1 AND 5),
    feedback_comment TEXT,
    is_issue_triggered BOOLEAN DEFAULT false,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Performance Indexes for Analytics & Monitoring
CREATE INDEX IF NOT EXISTS idx_chat_logs_farm_id ON public.chat_logs(farm_id);
CREATE INDEX IF NOT EXISTS idx_chat_logs_created_at ON public.chat_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_logs_model ON public.chat_logs(model);
CREATE INDEX IF NOT EXISTS idx_chat_logs_mode ON public.chat_logs(mode);
CREATE INDEX IF NOT EXISTS idx_chat_logs_http_status ON public.chat_logs(http_status);

-- RLS Policy for Public / Authenticated Access
ALTER TABLE public.chat_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public select for chat_logs" ON public.chat_logs FOR SELECT USING (true);
CREATE POLICY "Allow public insert for chat_logs" ON public.chat_logs FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow public update for chat_logs" ON public.chat_logs FOR UPDATE USING (true);
