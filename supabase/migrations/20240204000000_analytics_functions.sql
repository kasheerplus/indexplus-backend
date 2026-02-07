-- Advanced Analytics Functions for Index Plus

-- 1. Calculate Average Response Time (in minutes)
-- Defines response time as the interval between a customer message and the subsequent agent reply in the same conversation.
CREATE OR REPLACE FUNCTION get_avg_response_time(company_id_param UUID)
RETURNS NUMERIC AS $$
DECLARE
    avg_minutes NUMERIC;
BEGIN
    WITH message_pairs AS (
        SELECT 
            m1.conversation_id,
            m1.created_at as customer_time,
            MIN(m2.created_at) as agent_time
        FROM messages m1
        JOIN messages m2 ON m1.conversation_id = m2.conversation_id
        JOIN conversations c ON m1.conversation_id = c.id
        WHERE c.company_id = company_id_param
        AND m1.sender_type = 'customer'
        AND m2.sender_type = 'agent'
        AND m2.created_at > m1.created_at
        GROUP BY m1.conversation_id, m1.created_at
    )
    SELECT AVG(EXTRACT(EPOCH FROM (agent_time - customer_time)) / 60) INTO avg_minutes
    FROM message_pairs;

    RETURN ROUND(COALESCE(avg_minutes, 0), 1);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Calculate Peak Order Hour
-- Returns the hour (0-23) when most sales are created.
CREATE OR REPLACE FUNCTION get_peak_order_hour(company_id_param UUID)
RETURNS TEXT AS $$
DECLARE
    peak_hour INTEGER;
BEGIN
    SELECT EXTRACT(HOUR FROM created_at) INTO peak_hour
    FROM sales_records
    WHERE company_id = company_id_param
    GROUP BY EXTRACT(HOUR FROM created_at)
    ORDER BY COUNT(*) DESC
    LIMIT 1;

    RETURN LPAD(COALESCE(peak_hour, 12)::TEXT, 2, '0') || ':00';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Get Real-time Statistics Summary
-- Returns revenue, sales count, conversion rate, response time, and peak hour in one call.
CREATE OR REPLACE FUNCTION get_business_stats(company_id_param UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_revenue', (SELECT COALESCE(SUM(amount), 0) FROM sales_records WHERE company_id = company_id_param AND status = 'completed'),
        'total_sales', (SELECT COUNT(*) FROM sales_records WHERE company_id = company_id_param AND status = 'completed'),
        'total_customers', (SELECT COUNT(DISTINCT customer_id) FROM sales_records WHERE company_id = company_id_param AND status = 'completed'),
        'avg_response_time', get_avg_response_time(company_id_param),
        'peak_order_hour', get_peak_order_hour(company_id_param),
        'conversion_rate', CASE 
            WHEN (SELECT COUNT(*) FROM conversations WHERE company_id = company_id_param) = 0 THEN 0
            ELSE (SELECT COUNT(DISTINCT conversation_id) FROM sales_records WHERE company_id = company_id_param)::NUMERIC / (SELECT COUNT(*) FROM conversations WHERE company_id = company_id_param) * 100
        END
    ) INTO result;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
