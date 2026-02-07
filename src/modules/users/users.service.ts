import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { UserRole } from '../auth/decorators/roles.decorator';

export interface UserProfile {
    id: string;
    company_id: string;
    full_name: string;
    email: string;
    role: UserRole;
    status: 'active' | 'suspended';
    created_at: string;
}

@Injectable()
export class UsersService {
    constructor(private readonly supabase: SupabaseService) { }

    async findAll(companyId: string) {
        const { data, error } = await this.supabase
            .getClient()
            .from('users')
            .select('*')
            .eq('company_id', companyId)
            .order('created_at', { ascending: false });

        if (error) throw error;
        return data;
    }

    async findOne(id: string, companyId: string) {
        const { data, error } = await this.supabase
            .getClient()
            .from('users')
            .select('*')
            .eq('id', id)
            .eq('company_id', companyId)
            .single();

        if (error || !data) throw new NotFoundException('المستخدم غير موجود');
        return data;
    }

    async create(companyId: string, userData: Partial<UserProfile>) {
        const { data, error } = await this.supabase
            .getClient()
            .from('users')
            .insert([{ ...userData, company_id: companyId }])
            .select()
            .single();

        if (error) throw error;
        return data;
    }

    async update(id: string, companyId: string, userData: Partial<UserProfile>) {
        const { data, error } = await this.supabase
            .getClient()
            .from('users')
            .update(userData)
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
            .from('users')
            .delete()
            .eq('id', id)
            .eq('company_id', companyId);

        if (error) throw error;
        return { success: true };
    }
}
