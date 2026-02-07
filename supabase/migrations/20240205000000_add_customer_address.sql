-- Migration: Add address field to customers
-- Component: CRM / Inbox
-- Description: Adds a nullable text column for customer addresses.

ALTER TABLE public.customers 
ADD COLUMN IF NOT EXISTS address TEXT;

-- Verify the column exists (for visibility in logs)
DO $$ 
BEGIN 
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='customers' AND column_name='address') THEN
        RAISE NOTICE 'Column address added successfully to customers table.';
    END IF;
END $$;
