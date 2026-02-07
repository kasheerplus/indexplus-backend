import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

export interface Customer {
    id: string;
    company_id: string;
    name: string;
    phone: string;
    email?: string;
    tags: string[];
    notes?: string;
    created_at: string;
}

@Injectable()
export class CrmService {
    constructor(private readonly supabase: SupabaseService) { }

    async findAll(companyId: string, search?: string) {
        let query = this.supabase
            .getClient()
            .from('customers')
            .select('*')
            .eq('company_id', companyId)
            .order('created_at', { ascending: false });

        if (search) {
            query = query.or(`name.ilike.%${search}%,phone.ilike.%${search}%`);
        }

        const { data, error } = await query;
        if (error) throw error;
        return data;
    }

    async findOne(id: string, companyId: string) {
        const { data, error } = await this.supabase
            .getClient()
            .from('customers')
            .select('*')
            .eq('id', id)
            .eq('company_id', companyId)
            .single();

        if (error || !data) throw new NotFoundException('العميل غير موجود');
        return data;
    }

    async create(companyId: string, customerData: Partial<Customer>) {
        const { data, error } = await this.supabase
            .getClient()
            .from('customers')
            .insert([{ ...customerData, company_id: companyId }])
            .select()
            .single();

        if (error) throw error;
        return data;
    }

    async update(id: string, companyId: string, customerData: Partial<Customer>) {
        const { data, error } = await this.supabase
            .getClient()
            .from('customers')
            .update(customerData)
            .eq('id', id)
            .eq('company_id', companyId)
            .select()
            .single();

        if (error) throw error;
        return data;
    }

    async remove(id: string, companyId: string) {
        const { error } = await this.supabase
            .getClient()
            .from('customers')
            .delete()
            .eq('id', id)
            .eq('company_id', companyId);

        if (error) throw error;
        return { success: true };
    }
}
