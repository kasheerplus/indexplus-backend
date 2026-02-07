-- Comprehensive Schema Update for Interactive Flows
-- This script safely adds columns if they are missing and sets up constraints.

-- 1. Ensure columns exist
ALTER TABLE interactive_flows 
ADD COLUMN IF NOT EXISTS trigger_type TEXT DEFAULT 'keyword',
ADD COLUMN IF NOT EXISTS trigger_keyword TEXT,
ADD COLUMN IF NOT EXISTS trigger_post_link TEXT,
ADD COLUMN IF NOT EXISTS is_main_menu BOOLEAN DEFAULT FALSE;

-- 2. Update trigger_type constraint (cleanly)
ALTER TABLE interactive_flows 
DROP CONSTRAINT IF EXISTS interactive_flows_trigger_type_check;

ALTER TABLE interactive_flows 
ADD CONSTRAINT interactive_flows_trigger_type_check 
CHECK (trigger_type IN ('keyword', 'post_link', 'main_menu', 'all'));

-- 3. Setup Unique Constraints for triggers (safely)
-- Drop old constraints if they exist to avoid conflicts with new logic
ALTER TABLE interactive_flows DROP CONSTRAINT IF EXISTS unique_trigger_keyword;
ALTER TABLE interactive_flows DROP CONSTRAINT IF EXISTS unique_trigger_post_link;

ALTER TABLE interactive_flows 
ADD CONSTRAINT unique_trigger_keyword UNIQUE(company_id, trigger_keyword),
ADD CONSTRAINT unique_trigger_post_link UNIQUE(company_id, trigger_post_link);

-- 4. Ensure only one active main menu (using partial unique index)
-- Partial unique index is safer and easier than EXCLUDE constraints.
DROP INDEX IF EXISTS unique_active_main_menu_idx;
CREATE UNIQUE INDEX unique_active_main_menu_idx 
ON interactive_flows (company_id) 
WHERE (is_main_menu = TRUE AND is_active = TRUE);

-- 5. Refresh RLS Policy (ensure it's using the correct logic)
ALTER TABLE interactive_flows ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS interactive_flows_isolation_policy ON interactive_flows;
    CREATE POLICY interactive_flows_isolation_policy ON interactive_flows
        FOR ALL
        USING (company_id = (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid)
        WITH CHECK (company_id = (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid);
EXCEPTION
    WHEN undefined_function THEN
        -- Fallback if get_auth_company_id() or specific JWT logic is different
        NULL;
END
$$;

NOTIFY pgrst, 'reload schema';
