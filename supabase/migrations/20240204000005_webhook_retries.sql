-- Webhook Retry Mechanism

-- Function to find failed webhooks that need retrying
CREATE OR REPLACE FUNCTION get_failed_webhooks()
RETURNS SETOF webhook_logs AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM webhook_logs
    WHERE status = 'failed'
    AND created_at > (NOW() - INTERVAL '24 hours')
    ORDER BY created_at ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to mark a webhook for retry (resets status to pending)
CREATE OR REPLACE FUNCTION mark_webhook_for_retry(webhook_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE webhook_logs
    SET status = 'pending', error_message = NULL
    WHERE id = webhook_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
