import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

export interface SaleRecord {
    id: string;
    company_id: string;
    customer_id: string;
    conversation_id?: string;
    amount: number;
    items: any[];
    status: 'pending' | 'completed' | 'cancelled';
    created_at: string;
}

@Injectable()
export class SalesService {
    constructor(private readonly supabase: SupabaseService) { }

    async findAll(companyId: string, filters?: any) {
        let query = this.supabase
            .getClient()
            .from('sales_records')
            .select('*, customers(name)')
            .eq('company_id', companyId)
            .order('created_at', { ascending: false });

        if (filters?.customer_id) {
            query = query.eq('customer_id', filters.customer_id);
        }

        if (filters?.status) {
            query = query.eq('status', filters.status);
        }

        const { data, error } = await query;
        if (error) throw error;
        return data;
    }

    async findOne(id: string, companyId: string) {
        const { data, error } = await this.supabase
            .getClient()
            .from('sales_records')
            .select('*, customers(*)')
            .eq('id', id)
            .eq('company_id', companyId)
            .single();

        if (error || !data) throw new NotFoundException('الطلب غير موجود');
        return data;
    }

    async create(companyId: string, saleData: Partial<SaleRecord>) {
        const { data, error } = await this.supabase
            .getClient()
            .from('sales_records')
            .insert([{ ...saleData, company_id: companyId }])
            .select()
            .single();

        if (error) throw error;
        return data;
    }

    async updateStatus(id: string, companyId: string, status: string) {
        const { data, error } = await this.supabase
            .getClient()
            .from('sales_records')
            .update({ status })
            .eq('id', id)
            .eq('company_id', companyId)
            .select()
            .single();

        if (error) throw error;
        return data;
    }

    async getStats(companyId: string) {
        const { data, error } = await this.supabase
            .getClient()
            .from('sales_records')
            .select('amount, status')
            .eq('company_id', companyId);

        if (error) throw error;

        const stats = {
            total_sales: 0,
            completed_orders: 0,
            pending_orders: 0,
        };

        data.forEach((sale) => {
            if (sale.status === 'completed') {
                stats.total_sales += sale.amount;
                stats.completed_orders++;
            } else if (sale.status === 'pending') {
                stats.pending_orders++;
            }
        });

        return stats;
    }
}
