import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-kasheer-key',
}

serve(async (req: Request) => {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

    const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const requestId = crypto.randomUUID()

    try {
        const kasheerKey = req.headers.get('x-kasheer-key')
        if (!kasheerKey) {
            return new Response(JSON.stringify({ error: 'Missing Sync Key' }), { status: 401, headers: corsHeaders })
        }

        // 1. Authenticate the key against channels table
        const { data: channel, error: authError } = await supabase
            .from('channels')
            .select('company_id')
            .eq('platform', 'kasheer_plus')
            .eq('token', kasheerKey)
            .eq('status', 'connected')
            .single()

        if (authError || !channel) {
            console.error(`[${requestId}] Invalid Sync Key attempt`)
            return new Response(JSON.stringify({ error: 'Invalid Sync Key' }), { status: 401, headers: corsHeaders })
        }

        const companyId = channel.company_id
        const body = await req.json()
        const products = body.products || []

        console.log(`[${requestId}] Received ${products.length} products from Kasheer Plus for company ${companyId}`)

        // 2. Prepare for upsert
        const upsertData = products.map((p: any) => ({
            company_id: companyId,
            remote_id: p.id.toString(),
            name: p.name,
            sku: p.sku,
            category: p.category,
            price: p.price,
            stock_quantity: p.stock_quantity,
            unit: p.unit || 'piece',
            image_url: p.image_url,
            last_synced_at: new Date().toISOString()
        }))

        // 3. Perform Upsert
        const { error: upsertError } = await supabase
            .from('synced_inventory')
            .upsert(upsertData, { onConflict: 'company_id,remote_id' })

        if (upsertError) throw upsertError

        // 4. Log Success
        await supabase.from('sync_logs').insert({
            company_id: companyId,
            platform: 'kasheer_plus',
            success: true,
            payload_size: products.length
        })

        return new Response(JSON.stringify({
            status: 'success',
            synced_count: products.length
        }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        })

    } catch (error) {
        console.error(`[${requestId}] Sync Error:`, error)
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 400,
        })
    }
})
