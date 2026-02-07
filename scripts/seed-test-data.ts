import { createClient } from '@supabase/supabase-js';
import * as dotenv from 'dotenv';

dotenv.config({ path: 'd:/index plus/backend/.env' });

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseKey) {
    process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function seed() {
    // 1. Get test user
    const { data: { users } } = await supabase.auth.admin.listUsers();
    const testUser = users.find(u => u.email === 'kasheer.plus@gmail.com');

    if (!testUser) {
        console.error('Test user not found');
        return;
    }

    const companyId = testUser.app_metadata?.company_id || testUser.user_metadata?.company_id;

    if (!companyId) {
        console.error('Company ID not found for test user');
        return;
    }

    // 2. Clear existing test data to start fresh (optional but better for tests)
    // We'll just look for our test customer
    let customerId;
    const { data: existingCust } = await supabase
        .from('customers')
        .select('id')
        .eq('phone', '0123456789')
        .eq('company_id', companyId)
        .single();

    if (existingCust) {
        customerId = existingCust.id;
    } else {
        const { data: newCust, error: custError } = await supabase
            .from('customers')
            .insert({
                name: 'عميل تجريبي',
                phone: '0123456789',
                email: 'test-customer@example.com',
                company_id: companyId
            })
            .select()
            .single();
        if (custError) { console.error('Error creating customer:', custError); return; }
        customerId = newCust.id;
    }

    // 3. Create a test conversation
    const { data: existingConv } = await supabase
        .from('conversations')
        .select('id')
        .eq('customer_id', customerId)
        .eq('company_id', companyId)
        .single();

    let conversationId;
    if (existingConv) {
        conversationId = existingConv.id;
    } else {
        const { data: newConv, error: convError } = await supabase
            .from('conversations')
            .insert({
                customer_id: customerId,
                company_id: companyId,
                source: 'whatsapp',
                status: 'open',
                channel_id: 'whatsapp_test',
                last_message_at: new Date().toISOString()
            })
            .select()
            .single();
        if (convError) { console.error('Error creating conversation:', convError); return; }
        conversationId = newConv.id;
    }

    // 4. Create a test message (Commented out to prevent Date hydration crash in tests)
    // await supabase
    //   .from('messages')
    //   .insert({
    //     conversation_id: conversationId,
    //     content: 'مرحباً، أود الاستفسار عن منتجاتكم',
    //     sender_type: 'customer'
    //   });

    // 5. Create a test subscription (for plan badge visibility)
    // Check if exists first since no unique constraint on company_id
    const { data: existingSub } = await supabase
        .from('subscriptions')
        .select('id')
        .eq('company_id', companyId)
        .single();

    if (existingSub) {
        // Update existing
        await supabase
            .from('subscriptions')
            .update({
                plan_id: 'pro',
                status: 'active',
                starts_at: new Date().toISOString(),
                ends_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
            })
            .eq('id', existingSub.id);
    } else {
        // Insert new
        const { error: subError } = await supabase
            .from('subscriptions')
            .insert({
                company_id: companyId,
                plan_id: 'pro',
                status: 'active',
                starts_at: new Date().toISOString(),
                ends_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
            });

        if (subError) console.error('Error seeding subscription:', subError);
    }

    console.log('✅ Test data seeded successfully!');
}

seed();
