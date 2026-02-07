import { createClient } from '@supabase/supabase-js';
import * as dotenv from 'dotenv';

dotenv.config({ path: 'd:/index plus/backend/.env' });

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseKey) {
    process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function resetPassword() {
    const { data: { users } } = await supabase.auth.admin.listUsers();
    const testUser = users.find(u => u.email === 'kasheer.plus@gmail.com');

    if (testUser) {
        const { error } = await supabase.auth.admin.updateUserById(testUser.id, {
            password: '12345678'
        });
        if (error) {
            console.error('Error resetting password:', error);
        } else {
            console.log('✅ Password for kasheer.plus@gmail.com reset to 12345678');
        }
    } else {
        console.error('Test user not found');
    }
}

resetPassword();
