// Supabase Edge Function: Meta Webhook Handler (WhatsApp, FB, IG)
// Deploy with: supabase functions deploy meta-webhook

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// HMAC Verification Helper
async function verifySignature(payload: string, signature: string, secret: string) {
    const encoder = new TextEncoder();
    const keyData = encoder.encode(secret);
    const key = await crypto.subtle.importKey(
        'raw',
        keyData,
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['verify']
    );

    const sigHex = signature.startsWith('sha256=') ? signature.slice(7) : signature;
    const sigBytes = new Uint8Array(sigHex.match(/.{1,2}/g)!.map(byte => parseInt(byte, 16)));

    return await crypto.subtle.verify('HMAC', key, sigBytes, encoder.encode(payload));
}

// WhatsApp Outbound Helper
async function sendWhatsAppMessage(phoneNumberId: string, accessToken: string, to: string, content: string) {
    const response = await fetch(`https://graph.facebook.com/v17.0/${phoneNumberId}/messages`, {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            messaging_product: 'whatsapp',
            to: to,
            type: 'text',
            text: { body: content },
        }),
    });
    return response.json();
}

serve(async (req: Request) => {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

    const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const requestId = crypto.randomUUID()

    try {
        const url = new URL(req.url)
        const mode = url.searchParams.get('hub.mode')
        const token = url.searchParams.get('hub.verify_token')
        const challenge = url.searchParams.get('hub.challenge')

        // 1. Meta Verification
        if (mode === 'subscribe' && token === Deno.env.get('META_VERIFY_TOKEN')) {
            console.log(`[${requestId}] Webhook verification successful`)
            return new Response(challenge, { status: 200 })
        }

        // 2. Security: HMAC Verification
        const signature = req.headers.get('x-hub-signature-256')
        const rawBody = await req.text()
        const appSecret = Deno.env.get('META_APP_SECRET')

        if (appSecret && signature) {
            const isValid = await verifySignature(rawBody, signature, appSecret)
            if (!isValid) {
                console.error(`[${requestId}] Invalid signature`)
                return new Response('Invalid Signature', { status: 401 })
            }
        }

        const body = JSON.parse(rawBody)
        const entry = body.entry?.[0]
        const changes = entry?.changes?.[0]
        const value = changes?.value

        // 3. Reliability: Log Webhook & Idempotency Check
        const externalId = body.object === 'whatsapp_business_account'
            ? (value?.messages?.[0]?.id || value?.statuses?.[0]?.id)
            : entry?.id;

        if (externalId) {
            const { data: existing } = await supabase
                .from('webhook_logs')
                .select('id')
                .eq('platform', 'meta')
                .eq('external_id', externalId)
                .single()

            if (existing) {
                console.log(`[${requestId}] Request ${externalId} already processed`)
                return new Response('Already Processed', { status: 200 })
            }

            await supabase.from('webhook_logs').insert({
                platform: 'meta',
                external_id: externalId,
                payload: body
            })
        }

        console.log(`[${requestId}] Processing Meta Webhook: ${body.object}`)

        // 4. Handle Content
        if (body.object === 'whatsapp_business_account') {
            // A. Handle Incoming Messages
            const message = value?.messages?.[0]
            if (message) {
                // FIND OR CREATE CUSTOMER
                // 1. Get company_id from meta configuration (stored in a hidden settings table)
                // For now we assume a lookup by phone number
                const { data: customer } = await supabase
                    .from('customers')
                    .select('id, company_id')
                    .eq('phone', message.from)
                    .single()

                if (customer) {
                    // QUOTA CHECK
                    const { data: hasQuota, error: quotaError } = await supabase.rpc('check_message_quota', {
                        company_id_param: customer.company_id
                    })

                    if (!hasQuota) return new Response('Quota Exceeded', { status: 429 })

                    // FIND OR CREATE CONVERSATION
                    let { data: conv } = await supabase
                        .from('conversations')
                        .select('id')
                        .eq('customer_id', customer.id)
                        .eq('channel_id', value.metadata.display_phone_number)
                        .single()

                    if (!conv) {
                        const { data: newConv } = await supabase
                            .from('conversations')
                            .insert({
                                company_id: customer.company_id,
                                customer_id: customer.id,
                                channel_id: value.metadata.display_phone_number,
                                source: 'whatsapp'
                            })
                            .select()
                            .single()
                        conv = newConv
                    }

                    const content = message.text?.body || ''
                    // INSERT MESSAGE
                    await supabase
                        .from('messages')
                        .insert({
                            conversation_id: conv.id,
                            company_id: customer.company_id,
                            sender_type: 'customer',
                            content: content || '[Media]',
                            metadata: { whatsapp_id: message.id, raw: body }
                        })

                    // LOGIC: AUTOMATION ENGINE
                    if (content) {
                        const { data: rules } = await supabase
                            .from('automation_rules')
                            .select('*')
                            .eq('company_id', customer.company_id)
                            .eq('is_active', true)

                        const msgText = content.toLowerCase().trim()
                        const matchedRule = rules?.find(rule => {
                            return rule.keywords.some((kw: string) => {
                                const k = kw.toLowerCase().trim()
                                if (rule.trigger_type === 'exact') return msgText === k
                                if (rule.trigger_type === 'contains') return msgText.includes(k)
                                if (rule.trigger_type === 'starts_with') return msgText.startsWith(k)
                                return false
                            })
                        })

                        if (matchedRule) {
                            // 1. Get WhatsApp credentials for this company
                            const { data: channel } = await supabase
                                .from('channels')
                                .select('token, platform_id')
                                .eq('company_id', customer.company_id)
                                .eq('platform', 'whatsapp')
                                .eq('status', 'connected')
                                .single()

                            if (channel?.token && channel?.platform_id) {
                                // 2. Send Auto-Response
                                await sendWhatsAppMessage(
                                    channel.platform_id,
                                    channel.token,
                                    message.from,
                                    matchedRule.response_content
                                )

                                // 3. Log the auto-response in message history
                                await supabase.from('messages').insert({
                                    conversation_id: conv.id,
                                    company_id: customer.company_id,
                                    sender_type: 'agent',
                                    content: matchedRule.response_content,
                                    metadata: { automation_rule_id: matchedRule.id, type: 'auto_response' }
                                })
                            }
                        }
                    }

                    // UPDATE CONVERSATION STATUS
                    await supabase.from('conversations').update({
                        last_message_at: new Date().toISOString(),
                        unread_count: 1 // In a real app we'd increment this
                    }).eq('id', conv.id)

                    // Mark webhook as processed
                    await supabase.from('webhook_logs')
                        .update({ status: 'processed', company_id: customer.company_id, processed_at: new Date().toISOString() })
                        .eq('platform', 'meta')
                        .eq('external_id', externalId)
                }
            }

            // B. Handle Delivery Statuses (Lifecycle)
            const statusUpdate = value?.statuses?.[0]
            if (statusUpdate) {
                const statusMap: Record<string, string> = {
                    'sent': 'sent', 'delivered': 'delivered', 'read': 'read', 'failed': 'failed'
                }

                await supabase
                    .from('messages')
                    .update({
                        delivery_status: statusMap[statusUpdate.status] || 'sent',
                        delivered_at: statusUpdate.status === 'delivered' ? new Date().toISOString() : undefined,
                        read_at: statusUpdate.status === 'read' ? new Date().toISOString() : undefined
                    })
                    .eq('metadata->>whatsapp_id', statusUpdate.id)

                await supabase.from('webhook_logs')
                    .update({ status: 'processed', processed_at: new Date().toISOString() })
                    .eq('platform', 'meta')
                    .eq('external_id', externalId)
            }
        }

        return new Response(JSON.stringify({ status: 'success' }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        })
    } catch (error) {
        console.error(`[${requestId}] Error:`, error)
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 400,
        })
    }
})
