import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req: Request) => {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

    const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
        {
            auth: {
                autoRefreshToken: false,
                persistSession: false,
            },
        }
    )

    try {
        // 1. Get the requester's user object from the token
        const authHeader = req.headers.get('Authorization')
        if (!authHeader) throw new Error('Missing Authorization header')

        const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
        if (userError || !user) throw new Error('Invalid token')

        // 2. Check if the requester has permission (Owner/Admin)
        const role = user.app_metadata?.role || user.user_metadata?.role
        const companyId = user.app_metadata?.company_id || user.user_metadata?.company_id

        if (role !== 'owner' && role !== 'admin') {
            return new Response(JSON.stringify({ error: 'Unauthorized: Only owners and admins can create employees' }), {
                status: 403,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            })
        }

        if (!companyId) {
            return new Response(JSON.stringify({ error: 'Unauthorized: Company ID missing' }), {
                status: 403,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            })
        }

        // 3. Parse and validate the new employee's data
        const { email, password, fullName, memberRole } = await req.json()

        if (!email || !password || !fullName || !memberRole) {
            throw new Error('Missing required fields (email, password, fullName, memberRole)')
        }

        if (!['admin', 'agent', 'supervisor'].includes(memberRole)) {
            throw new Error('Invalid role')
        }

        // 4. Create the user using the Admin API
        const { data: newUser, error: createError } = await supabaseAdmin.auth.admin.createUser({
            email,
            password,
            email_confirm: true, // Auto-confirm for manual creation
            user_metadata: {
                full_name: fullName,
                company_id: companyId,
                role: memberRole
            }
        })

        if (createError) throw createError

        return new Response(JSON.stringify({
            status: 'success',
            user: newUser.user
        }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        })

    } catch (error) {
        console.error('Create Employee Error:', error)
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 400,
        })
    }
})
