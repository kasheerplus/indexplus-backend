-- Helper functions for deduplicating and merging customers

-- 1. Find potential duplicates for a customer
CREATE OR REPLACE FUNCTION get_duplicate_customers(target_customer_id UUID)
RETURNS TABLE (
    id UUID,
    name TEXT,
    phone TEXT,
    email TEXT,
    match_reason TEXT
) AS $$
DECLARE
    target_phone TEXT;
    target_email TEXT;
    target_company_id UUID;
BEGIN
    SELECT phone, email, company_id INTO target_phone, target_email, target_company_id
    FROM customers WHERE customers.id = target_customer_id;

    RETURN QUERY
    SELECT c.id, c.name, c.phone, c.email,
           CASE 
             WHEN c.phone = target_phone THEN 'Phone Match'
             WHEN c.email = target_email THEN 'Email Match'
             ELSE 'Fuzzy Name Match'
           END as match_reason
    FROM customers c
    WHERE c.id != target_customer_id
    AND c.company_id = target_company_id
    AND (
        (c.phone IS NOT NULL AND c.phone = target_phone) OR
        (c.email IS NOT NULL AND c.email = target_email)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Merge two customers (Move all related data to the primary one and delete the duplicate)
CREATE OR REPLACE FUNCTION merge_customers(primary_id UUID, duplicate_id UUID)
RETURNS VOID AS $$
BEGIN
    -- Only merge if they belong to the same company (security check)
    IF (SELECT company_id FROM customers WHERE id = primary_id) != 
       (SELECT company_id FROM customers WHERE id = duplicate_id) THEN
        RAISE EXCEPTION 'Cannot merge customers from different companies';
    END IF;

    -- Update Conversations
    UPDATE conversations SET customer_id = primary_id WHERE customer_id = duplicate_id;
    
    -- Update Sales Records
    UPDATE sales_records SET customer_id = primary_id WHERE customer_id = duplicate_id;
    
    -- Update Payment Proofs (if any)
    -- ...
    
    -- Delete the duplicate customer
    DELETE FROM customers WHERE id = duplicate_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
