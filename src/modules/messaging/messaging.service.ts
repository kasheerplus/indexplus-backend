import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SupabaseService } from '../supabase/supabase.service';

@Injectable()
export class MessagingService {
    constructor(
        private readonly supabaseService: SupabaseService,
        private readonly configService: ConfigService,
    ) { }

    async getConversations(companyId: string, status?: string) {
        const client = this.supabaseService.getAdminClient();
        let query = client
            .from('conversations')
            .select(`
        *,
        customer:customer_id (*),
        assigned_agent:assigned_to (full_name)
      `)
            .eq('company_id', companyId)
            .order('last_message_at', { ascending: false });

        if (status) {
            query = query.eq('status', status);
        }

        const { data, error } = await query;

        if (error) {
            throw new Error(`Failed to fetch conversations: ${error.message}`);
        }

        return data;
    }

    async getConversationMessages(conversationId: string, companyId: string) {
        const client = this.supabaseService.getAdminClient();
        const { data, error } = await client
            .from('messages')
            .select('*')
            .eq('conversation_id', conversationId)
            .order('created_at', { ascending: true });

        if (error) {
            throw new Error(`Failed to fetch messages: ${error.message}`);
        }

        return data;
    }

    async sendMessage(
        conversationId: string,
        companyId: string,
        agentId: string,
        content: string,
        metadata: any = {},
    ) {
        const client = this.supabaseService.getAdminClient();

        // 1. Fetch Conversation and Channel to get Page Token
        const { data: conversation } = await client
            .from('conversations')
            .select('*, customer:customer_id(*)')
            .eq('id', conversationId)
            .single();

        if (!conversation) throw new NotFoundException('Conversation not found');

        // 24-Hour Rule Check
        const lastMessageAt = new Date(conversation.last_message_at).getTime();
        const now = Date.now();
        if (now - lastMessageAt > 24 * 60 * 60 * 1000) {
            throw new Error('خارج نافذة الـ 24 ساعة المسموح بها للرد');
        }

        const { data: channel } = await client
            .from('channels')
            .select('token, platform_id')
            .eq('company_id', companyId)
            .eq('platform', conversation.source)
            .single();

        if (!channel?.token) throw new Error('قناة التواصل غير مربوطة أو الرمز مفقود');

        // 2. Create the internal message record
        const { data: message, error: messageError } = await client
            .from('messages')
            .insert({
                conversation_id: conversationId,
                company_id: companyId,
                sender_id: agentId,
                sender_type: 'agent',
                content,
                metadata,
            })
            .select()
            .single();

        if (messageError) throw new Error(`Failed to save message: ${messageError.message}`);

        // 3. Trigger actual outgoing message to Meta
        const psid = conversation.customer?.metadata?.psid;
        if (psid && (conversation.source === 'facebook' || conversation.source === 'instagram')) {
            await this.sendMetaMessage(channel.token, psid, content);
        }

        // 4. Update conversation last_message_at
        await client
            .from('conversations')
            .update({ last_message_at: new Date().toISOString() })
            .eq('id', conversationId);

        return message;
    }

    async processFacebookWebhook(event: any) {
        const client = this.supabaseService.getAdminClient();

        for (const entry of event.entry) {
            const pageId = entry.id;

            const { data: channel } = await client
                .from('channels')
                .select('company_id')
                .eq('platform', 'facebook')
                .eq('platform_id', pageId)
                .single();

            if (!channel) continue;

            for (const messaging of entry.messaging) {
                const senderPsid = messaging.sender.id;
                const message = messaging.message;

                if (!message || message.is_echo) continue;

                let customer = await this.findOrCreateCustomerByPsid(channel.company_id, senderPsid, 'facebook');
                let conversation = await this.findOrCreateConversation(channel.company_id, customer.id, pageId, 'facebook');

                await client.from('messages').insert({
                    conversation_id: conversation.id,
                    company_id: channel.company_id,
                    sender_type: 'customer',
                    content: message.text || '[محتوى غير نصي]',
                    metadata: { mid: message.mid, psid: senderPsid }
                });

                await client.from('conversations').update({
                    last_message_at: new Date().toISOString(),
                    unread_count: (conversation.unread_count || 0) + 1
                }).eq('id', conversation.id);
            }
        }
    }

    async processInstagramWebhook(event: any) {
        const client = this.supabaseService.getAdminClient();

        for (const entry of event.entry) {
            const igId = entry.id;

            const { data: channel } = await client
                .from('channels')
                .select('company_id')
                .eq('platform', 'instagram')
                .eq('platform_id', igId)
                .single();

            if (!channel) continue;

            for (const messaging of entry.messaging) {
                const senderIgsid = messaging.sender.id;
                const message = messaging.message;

                if (!message || message.is_echo) continue;

                let customer = await this.findOrCreateCustomerByPsid(channel.company_id, senderIgsid, 'instagram');
                let conversation = await this.findOrCreateConversation(channel.company_id, customer.id, igId, 'instagram');

                await client.from('messages').insert({
                    conversation_id: conversation.id,
                    company_id: channel.company_id,
                    sender_type: 'customer',
                    content: message.text || '[محتوى غير نصي]',
                    metadata: { mid: message.mid, igsid: senderIgsid }
                });

                await client.from('conversations').update({
                    last_message_at: new Date().toISOString(),
                    unread_count: (conversation.unread_count || 0) + 1
                }).eq('id', conversation.id);
            }
        }
    }

    private async findOrCreateCustomerByPsid(companyId: string, psid: string, platform: string) {
        const client = this.supabaseService.getAdminClient();

        const { data: customer } = await client
            .from('customers')
            .select('*')
            .eq('company_id', companyId)
            .contains('metadata', { [platform === 'instagram' ? 'igsid' : 'psid']: psid })
            .limit(1)
            .maybeSingle();

        if (customer) return customer;

        const name = `${platform === 'instagram' ? 'Instagram' : 'Facebook'} Customer (${psid.substring(0, 5)})`;

        const { data: newCustomer } = await client
            .from('customers')
            .insert({
                company_id: companyId,
                name,
                phone: psid,
                metadata: { [platform === 'instagram' ? 'igsid' : 'psid']: psid, platform }
            })
            .select()
            .single();

        return newCustomer;
    }

    private async findOrCreateConversation(companyId: string, customerId: string, channelId: string, source: string) {
        const client = this.supabaseService.getAdminClient();

        const { data: conversation } = await client
            .from('conversations')
            .select('*')
            .eq('company_id', companyId)
            .eq('customer_id', customerId)
            .eq('source', source)
            .eq('status', 'open')
            .maybeSingle();

        if (conversation) return conversation;

        const { data: newConversation } = await client
            .from('conversations')
            .insert({
                company_id: companyId,
                customer_id: customerId,
                channel_id: channelId,
                source,
                status: 'open'
            })
            .select()
            .single();

        return newConversation;
    }

    async markAsRead(conversationId: string, companyId: string) {
        const client = this.supabaseService.getAdminClient();
        const { error } = await client
            .from('conversations')
            .update({ unread_count: 0 })
            .eq('id', conversationId)
            .eq('company_id', companyId);

        if (error) {
            throw new Error(`Failed to mark as read: ${error.message}`);
        }

        return { success: true };
    }

    async exchangeMetaCode(code: string, companyId: string) {
        const appId = this.configService.get<string>('META_APP_ID');
        const appSecret = this.configService.get<string>('META_APP_SECRET');
        const frontendUrl = this.configService.get<string>('FRONTEND_URL') || 'http://localhost:3000';
        const redirectUri = `${frontendUrl}/auth/facebook/callback`;

        // 1. Get User Access Token
        const tokenUrl = `https://graph.facebook.com/v20.0/oauth/access_token?client_id=${appId}&client_secret=${appSecret}&code=${code}&redirect_uri=${redirectUri}`;

        const tokenResp = await fetch(tokenUrl);
        const tokenData = await tokenResp.json();
        if (tokenData.error) throw new Error(`Meta Token Error: ${tokenData.error.message}`);

        const userToken = tokenData.access_token;

        // 2. Fetch Pages and Instagram Accounts
        const accountsUrl = `https://graph.facebook.com/v20.0/me/accounts?access_token=${userToken}&fields=name,id,fan_count,picture,access_token,instagram_business_account{id,name,username,profile_picture_url}`;

        const accountsResp = await fetch(accountsUrl);
        const accountsData = await accountsResp.json();
        if (accountsData.error) throw new Error(`Meta Accounts Error: ${accountsData.error.message}`);

        const accounts = [];

        for (const page of (accountsData.data || [])) {
            // Add Facebook Page
            accounts.push({
                id: page.id,
                name: page.name,
                fans: page.fan_count || 0,
                icon: page.picture?.data?.url,
                token: page.access_token,
                platform: 'facebook'
            });

            // Add Instagram Account if linked
            if (page.instagram_business_account) {
                const ig = page.instagram_business_account;
                accounts.push({
                    id: ig.id,
                    name: ig.name || ig.username,
                    fans: 'Business',
                    icon: ig.profile_picture_url,
                    token: page.access_token, // Instagram uses the Page Token
                    platform: 'instagram'
                });
            }
        }

        return accounts;
    }

    private async sendMetaMessage(pageToken: string, recipientId: string, text: string) {
        const url = `https://graph.facebook.com/v20.0/me/messages?access_token=${pageToken}`;

        const response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                recipient: { id: recipientId },
                messaging_type: 'RESPONSE',
                message: { text }
            })
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(`Meta API Error: ${error.error?.message || 'Unknown error'}`);
        }
    }
}
