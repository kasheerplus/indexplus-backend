import { createClient } from '@supabase/supabase-js';
import * as dotenv from 'dotenv';
import * as path from 'path';

dotenv.config({ path: 'd:/index plus/backend/.env' });

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseKey) {
    console.error('Missing env vars');
    process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function checkUsers() {
    const { data: { users }, error } = await supabase.auth.admin.listUsers();
    if (error) {
        console.error('Error listing users:', error);
    } else {
        console.log('--- USERS LIST ---');
        users.forEach(u => {
            console.log(`Email: ${u.email}, ID: ${u.id}, Metadata: ${JSON.stringify(u.user_metadata)}`);
        });
        console.log('------------------');
    }
}

checkUsers();
