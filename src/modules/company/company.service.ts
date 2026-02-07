import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

@Injectable()
export class CompanyService {
    constructor(private readonly supabaseService: SupabaseService) { }

    async getCompanyProfile(companyId: string) {
        const client = this.supabaseService.getAdminClient();
        const { data, error } = await client
            .from('companies')
            .select('*')
            .eq('id', companyId)
            .single();

        if (error || !data) {
            throw new NotFoundException('Company not found');
        }

        return data;
    }

    async updateCompany(companyId: string, updates: any) {
        const client = this.supabaseService.getAdminClient();
        const { data, error } = await client
            .from('companies')
            .update(updates)
            .eq('id', companyId)
            .select()
            .single();

        if (error) {
            throw new Error(`Failed to update company: ${error.message}`);
        }

        return data;
    }
}
