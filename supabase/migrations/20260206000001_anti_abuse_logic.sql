-- ========================================================
-- MIGRATION: Anti-Abuse RPCs & Constraints
-- Date: 2026-02-06
-- ========================================================

-- 1. Update identifier_type constraint to include kasheer_plus
ALTER TABLE public.trial_used_identifiers DROP CONSTRAINT IF EXISTS trial_used_identifiers_identifier_type_check;
ALTER TABLE public.trial_used_identifiers ADD CONSTRAINT trial_used_identifiers_identifier_type_check 
CHECK (identifier_type IN ('whatsapp', 'facebook', 'instagram', 'phone_number', 'kasheer_plus'));

-- 2. Update channels platform constraint to include kasheer_plus
ALTER TABLE public.channels DROP CONSTRAINT IF EXISTS channels_platform_check;
ALTER TABLE public.channels ADD CONSTRAINT channels_platform_check 
CHECK (platform IN ('whatsapp', 'facebook', 'instagram', 'tiktok', 'kasheer_plus'));

-- 3. Function: check_channel_trial_abuse
-- Checks if an identifier has already been used in a trial by any company
CREATE OR REPLACE FUNCTION public.check_channel_trial_abuse(identifier_type_param TEXT, identifier_value_param TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    found_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO found_count
    FROM public.trial_used_identifiers
    WHERE identifier_type = identifier_type_param AND identifier_value = identifier_value_param;
    
    RETURN found_count > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Function: log_trial_identifier
-- Logs the usage of an identifier during a trial period
CREATE OR REPLACE FUNCTION public.log_trial_identifier(company_id_param UUID, identifier_type_param TEXT, identifier_value_param TEXT)
RETURNS VOID AS $$
BEGIN
    INSERT INTO public.trial_used_identifiers (company_id, identifier_type, identifier_value)
    VALUES (company_id_param, identifier_type_param, identifier_value_param)
    ON CONFLICT (identifier_type, identifier_value) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
