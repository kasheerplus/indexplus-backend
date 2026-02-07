import { createClient } from '@supabase/supabase-js';
import * as fs from 'fs';
import * as path from 'path';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseServiceRoleKey) {
    console.error('❌ Error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in your .env file.');
    process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

async function setupDatabase() {
    console.log('🚀 Starting Database Setup...');

    const migrationPath = path.join(__dirname, '../supabase/migrations/20240124000000_core_schema.sql');

    if (!fs.existsSync(migrationPath)) {
        console.error(`❌ Error: Migration file not found at ${migrationPath}`);
        process.exit(1);
    }

    const sql = fs.readFileSync(migrationPath, 'utf8');

    console.log('⏳ Applying migration...');

    // Note: supabase-js doesn't have a direct 'run raw sql' method for general use, 
    // but we can use the 'rpc' method if we have an edge function, or more commonly,
    // we use the postgres connection directly if available. 
    // Since we are in a limited environment, I will provide instructions for the CLI 
    // or a direct copy-paste instruction if the script isn't feasible for raw SQL.

    console.log('\n--- MIGRATION CONTENT START ---');
    console.log(sql);
    console.log('--- MIGRATION CONTENT END ---\n');

    console.log('💡 Since supabase-js is restricted for raw DDL, please use one of these:');
    console.log('1. Copy the code above and paste it into the Supabase SQL Editor.');
    console.log('2. Use the Supabase CLI: "supabase db push"');
    console.log('3. Use a tool like TablePlus or pgAdmin to connect and run the script.');
}

setupDatabase();
