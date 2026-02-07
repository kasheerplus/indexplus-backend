// Supabase Edge Function: Stripe Webhook Handler
// Deploy with: supabase functions deploy stripe-webhook

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@11.1.0?target=deno'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
    apiVersion: '2022-11-15',
    httpClient: Stripe.createFetchHttpClient(),
})

const cryptoProvider = Stripe.createSubtleCryptoProvider()

serve(async (req: Request) => {
    const signature = req.headers.get('stripe-signature')

    if (!signature) {
        return new Response('No signature', { status: 400 })
    }

    const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const body = await req.text()
    const endpointSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET')

    try {
        const event = await stripe.webhooks.constructEventAsync(
            body,
            signature,
            endpointSecret ?? '',
            undefined,
            cryptoProvider
        )

        console.log(`Received event: ${event.type}`)

        // Reliability: Log the event
        await supabase.from('webhook_logs').insert({
            platform: 'stripe',
            external_id: event.id,
            payload: event
        })

        // Handle the event
        switch (event.type) {
            case 'checkout.session.completed':
                const session = event.data.object as any
                const companyId = session.metadata.company_id
                const planId = session.metadata.plan_id

                await supabase
                    .from('subscriptions')
                    .update({
                        status: 'active',
                        plan_id: planId,
                        starts_at: new Date().toISOString(),
                        ends_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
                    })
                    .eq('company_id', companyId)

                await supabase.from('webhook_logs').update({ status: 'processed', company_id: companyId, processed_at: new Date().toISOString() }).eq('external_id', event.id)
                break

            case 'customer.subscription.deleted':
                // Handle expiration
                break
        }

        return new Response(JSON.stringify({ received: true }), { status: 200 })
    } catch (err) {
        console.error(`Webhook Error: ${err.message}`)
        return new Response(JSON.stringify({ error: err.message }), { status: 400 })
    }
})
