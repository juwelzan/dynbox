-- DynBox First-Party OTA Schema & Storage Migration for Supabase
-- Version: 20261016000000_ota_releases.sql
-- Description: Creates release metadata tables, storage bucket, and strict Row Level Security (RLS) policies.

-- 1. Create ota_releases table
CREATE TABLE IF NOT EXISTS public.ota_releases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    app_id TEXT NOT NULL,
    release_id TEXT NOT NULL,
    version INTEGER NOT NULL CHECK (version >= 1),
    channel TEXT NOT NULL DEFAULT 'production',
    platform TEXT NOT NULL DEFAULT 'all',
    min_app_version TEXT NOT NULL DEFAULT '1.0.0',
    runtime_schema_version TEXT NOT NULL DEFAULT '1.0',
    payload_sha256 TEXT NOT NULL CHECK (length(payload_sha256) = 64),
    payload_size_bytes INTEGER NOT NULL CHECK (payload_size_bytes > 0 AND payload_size_bytes <= 524288),
    payload_storage_path TEXT,
    payload_url TEXT,
    payload_json TEXT,
    signature TEXT,
    published_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_rolled_back BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_app_release UNIQUE (app_id, release_id),
    CONSTRAINT chk_payload_source CHECK (payload_storage_path IS NOT NULL OR payload_url IS NOT NULL OR payload_json IS NOT NULL)
);

-- Index for efficient client update lookup (app_id, channel, platform, is_active)
CREATE INDEX IF NOT EXISTS idx_ota_releases_lookup 
ON public.ota_releases (app_id, channel, is_active, is_rolled_back, version DESC);

-- 2. Enable Row Level Security (RLS)
ALTER TABLE public.ota_releases ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies
-- Policy 1: Public / Anonymous read access for active, non-rolled-back releases.
-- Mobile clients with public anonKey can only query active releases.
DROP POLICY IF EXISTS "Public clients can read active compatible OTA releases" ON public.ota_releases;
CREATE POLICY "Public clients can read active compatible OTA releases" 
ON public.ota_releases
FOR SELECT
TO anon, authenticated
USING (
    is_active = true 
    AND is_rolled_back = false
);

-- Policy 2: Publishing & management restricted to service_role or authenticated administrators.
-- Public anon users CANNOT insert, update, or delete releases.
DROP POLICY IF EXISTS "Only service_role can manage OTA releases" ON public.ota_releases;
CREATE POLICY "Only service_role can manage OTA releases"
ON public.ota_releases
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- 4. Supabase Storage Bucket setup for OTA bundles
-- Insert ota-payloads bucket if storage schema exists
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'ota-payloads',
    'ota-payloads',
    true,
    524288, -- 512KB max size limit
    ARRAY['application/json', 'application/octet-stream']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 524288,
    allowed_mime_types = ARRAY['application/json', 'application/octet-stream'];

-- Storage RLS: Public can read ota-payloads objects
DROP POLICY IF EXISTS "Public Read OTA Payloads" ON storage.objects;
CREATE POLICY "Public Read OTA Payloads"
ON storage.objects
FOR SELECT
TO anon, authenticated
USING (bucket_id = 'ota-payloads');

-- Storage RLS: Only service_role can upload or delete OTA payloads
DROP POLICY IF EXISTS "Service Role Upload OTA Payloads" ON storage.objects;
CREATE POLICY "Service Role Upload OTA Payloads"
ON storage.objects
FOR INSERT
TO service_role
WITH CHECK (bucket_id = 'ota-payloads');

DROP POLICY IF EXISTS "Service Role Mutate OTA Payloads" ON storage.objects;
CREATE POLICY "Service Role Mutate OTA Payloads"
ON storage.objects
FOR UPDATE
TO service_role
USING (bucket_id = 'ota-payloads');

DROP POLICY IF EXISTS "Service Role Delete OTA Payloads" ON storage.objects;
CREATE POLICY "Service Role Delete OTA Payloads"
ON storage.objects
FOR DELETE
TO service_role
USING (bucket_id = 'ota-payloads');
