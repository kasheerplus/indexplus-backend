-- Add address column to customers table for Interactive Flows
ALTER TABLE customers ADD COLUMN IF NOT EXISTS address TEXT;

-- Update sales_records to ensure we track order numbers and stock deduction details if needed
-- (Items JSONB already supports metadata like size/color)

-- Function to handle stock deduction (Simplified for UI/Logic demonstration)
CREATE OR REPLACE FUNCTION deduct_stock(item_id UUID, quantity INTEGER)
RETURNS VOID AS $$
BEGIN
    UPDATE synced_inventory
    SET stock_quantity = stock_quantity - quantity
    WHERE id = item_id AND stock_quantity >= quantity;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
