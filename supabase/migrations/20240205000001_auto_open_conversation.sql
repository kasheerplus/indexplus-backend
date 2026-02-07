-- Trigger to automatically reopen conversation when a new message is inserted
CREATE OR REPLACE FUNCTION public.auto_open_conversation_on_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.conversations
    SET 
        status = 'open',
        last_message_at = NOW(),
        updated_at = NOW()
    WHERE id = NEW.conversation_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if it exists to avoid conflicts
DROP TRIGGER IF EXISTS on_message_insert_open_conversation ON public.messages;

-- Create the trigger
CREATE TRIGGER on_message_insert_open_conversation
AFTER INSERT ON public.messages
FOR EACH ROW
EXECUTE FUNCTION public.auto_open_conversation_on_message();
