import { Injectable, Logger, Scope } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';

@Injectable({ scope: Scope.DEFAULT })
export class SupabaseService {
    private readonly logger = new Logger(SupabaseService.name);
    private clientInstance: SupabaseClient;
    private adminClientInstance: SupabaseClient;

    constructor(private readonly configService: ConfigService) { }

    getClient(): SupabaseClient {
        if (this.clientInstance) {
            return this.clientInstance;
        }

        const url = this.configService.get<string>('SUPABASE_URL')!;
        const key = this.configService.get<string>('SUPABASE_KEY')!;

        this.clientInstance = createClient(url, key);
        return this.clientInstance;
    }

    /**
     * Returns a Supabase client with service role privileges.
     * Use this for administrative tasks that bypass RLS.
     */
    getAdminClient(): SupabaseClient {
        if (this.adminClientInstance) {
            return this.adminClientInstance;
        }

        const url = this.configService.get<string>('SUPABASE_URL')!;
        const key = this.configService.get<string>('SUPABASE_SERVICE_ROLE_KEY')!;

        this.adminClientInstance = createClient(url, key, {
            auth: {
                autoRefreshToken: false,
                persistSession: false,
            },
        });
        return this.adminClientInstance;
    }

    /**
     * Returns a Supabase client initialized with a specific user's JWT.
     * This ensures that RLS policies are applied for that user.
     */
    getClientForUser(jwt: string): SupabaseClient {
        const url = this.configService.get<string>('SUPABASE_URL')!;
        const key = this.configService.get<string>('SUPABASE_KEY')!;

        return createClient(url, key, {
            global: {
                headers: {
                    Authorization: `Bearer ${jwt}`,
                },
            },
        });
    }
}
