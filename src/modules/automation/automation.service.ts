import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

export interface QuickReply {
    id: string;
    company_id: string;
    shortcut: string;
    content: string;
    created_at: string;
}

export interface KeywordTrigger {
    id: string;
    company_id: string;
    keyword: string;
    response: string;
    is_active: boolean;
    created_at: string;
}

@Injectable()
export class AutomationService {
    constructor(private readonly supabase: SupabaseService) { }

    async findAllQuickReplies(companyId: string) {
        const { data, error } = await this.supabase
            .getClient()
            .from('quick_replies')
            .select('*')
            .eq('company_id', companyId)
            .order('shortcut', { ascending: true });

        if (error) throw error;
        return data;
    }

    async createQuickReply(companyId: string, replyData: Partial<QuickReply>) {
        const { data, error } = await this.supabase
            .getClient()
            .from('quick_replies')
            .insert([{ ...replyData, company_id: companyId }])
            .select()
            .single();

        if (error) throw error;
        return data;
    }

    async findAllKeywordTriggers(companyId: string) {
        const { data, error } = await this.supabase
            .getClient()
            .from('keyword_triggers')
            .select('*')
            .eq('company_id', companyId)
            .order('keyword', { ascending: true });

        if (error) throw error;
        return data;
    }

    async createKeywordTrigger(companyId: string, triggerData: Partial<KeywordTrigger>) {
        const { data, error } = await this.supabase
            .getClient()
            .from('keyword_triggers')
            .insert([{ ...triggerData, company_id: companyId }])
            .select()
            .single();

        if (error) throw error;
        return data;
    }

    async updateKeywordTrigger(id: string, companyId: string, triggerData: Partial<KeywordTrigger>) {
        const { data, error } = await this.supabase
            .getClient()
            .from('keyword_triggers')
            .update(triggerData)
            .eq('id', id)
            .eq('company_id', companyId)
            .select()
            .single();

        if (error) throw error;
        return data;
    }

    async removeQuickReply(id: string, companyId: string) {
        const { error } = await this.supabase
            .getClient()
            .from('quick_replies')
            .delete()
            .eq('id', id)
            .eq('company_id', companyId);

        if (error) throw error;
        return { success: true };
    }
}
