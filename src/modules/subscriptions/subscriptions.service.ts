import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

export interface Subscription {
    id: string;
    company_id: string;
    plan_id: string;
    status: 'active' | 'pending' | 'expired';
    starts_at: string;
    ends_at: string;
}

export interface PaymentProof {
    id: string;
    company_id: string;
    amount: number;
    proof_image_url: string;
    status: 'pending' | 'approved' | 'rejected';
    created_at: string;
}

@Injectable()
export class SubscriptionsService {
    constructor(private readonly supabase: SupabaseService) { }

    async getCurrent(companyId: string) {
        const { data, error } = await this.supabase
            .getClient()
            .from('subscriptions')
            .select('*')
            .eq('company_id', companyId)
            .eq('status', 'active')
            .order('ends_at', { ascending: false })
            .limit(1)
            .single();

        if (error && error.code !== 'PGRST116') throw error;
        return data || null;
    }

    async getHistory(companyId: string) {
        const { data, error } = await this.supabase
            .getClient()
            .from('subscriptions')
            .select('*')
            .eq('company_id', companyId)
            .order('created_at', { ascending: false });

        if (error) throw error;
        return data;
    }

    async createPaymentProof(companyId: string, proofData: Partial<PaymentProof>) {
        const { data, error } = await this.supabase
            .getClient()
            .from('payment_proofs')
            .insert([{ ...proofData, company_id: companyId, status: 'pending' }])
            .select()
            .single();

        if (error) throw error;
        return data;
    }

    async getPaymentProofs(companyId: string) {
        const { data, error } = await this.supabase
            .getClient()
            .from('payment_proofs')
            .select('*')
            .eq('company_id', companyId)
            .order('created_at', { ascending: false });

        if (error) throw error;
        return data;
    }
}
