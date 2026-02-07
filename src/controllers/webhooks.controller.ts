/**
 * Paymob Webhook Handler
 * Receives payment status updates from Paymob gateway
 * Endpoint: POST /api/webhooks/paymob
 */

import { Controller, Post, Body, Headers, HttpCode, HttpStatus, BadRequestException } from '@nestjs/common';
import { createClient } from '@supabase/supabase-js';
import PaymobService from '../services/paymob.service';

const supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY! // Use service role to bypass RLS
);

@Controller('webhooks')
export class WebhooksController {

    /**
     * Paymob Webhook Handler
     * Called by Paymob when payment status changes
     */
    @Post('paymob')
    @HttpCode(HttpStatus.OK)
    async handlePaymobWebhook(
        @Body() payload: any,
        @Headers('x-paymob-signature') signature: string
    ) {
        try {
            console.log('📥 Paymob Webhook Received:', {
                transactionId: payload.obj?.id,
                orderId: payload.obj?.order?.merchant_order_id,
                success: payload.obj?.success
            });

            // Step 1: Verify HMAC signature
            const paymobConfig = await this.getPaymobConfig(payload.obj?.order?.merchant_order_id);
            if (!paymobConfig) {
                throw new BadRequestException('Payment configuration not found');
            }

            const paymobService = new PaymobService(paymobConfig);
            const isValid = paymobService.verifyWebhookSignature(payload.obj, payload.hmac);

            if (!isValid) {
                console.error('❌ Invalid webhook signature');
                throw new BadRequestException('Invalid signature');
            }

            // Step 2: Extract payment data
            const {
                id: gatewayTransactionId,
                success,
                pending,
                order,
                amount_cents,
                source_data,
                error_occured,
                data
            } = payload.obj;

            const merchantOrderId = order?.merchant_order_id;
            if (!merchantOrderId) {
                throw new BadRequestException('Missing merchant order ID');
            }

            // Step 3: Determine payment status
            let status: string;
            let failureReason: string | null = null;

            if (success) {
                status = 'success';
            } else if (pending) {
                status = 'processing';
            } else if (error_occured) {
                status = 'failed';
                failureReason = data?.message || source_data?.message || 'Payment failed';
            } else {
                status = 'failed';
                failureReason = 'Unknown error';
            }

            // Step 4: Update payment transaction in database
            const { data: transaction, error: updateError } = await supabase
                .from('payment_transactions')
                .update({
                    status,
                    gateway_transaction_id: gatewayTransactionId.toString(),
                    paid_at: success ? new Date().toISOString() : null,
                    failure_reason: failureReason,
                    metadata: payload.obj
                })
                .eq('gateway_order_id', merchantOrderId)
                .select('*, customers(*), sales_records(*)')
                .single();

            if (updateError) {
                console.error('❌ Database update error:', updateError);
                throw new Error('Failed to update transaction');
            }

            console.log('✅ Transaction updated:', {
                id: transaction.id,
                status: transaction.status,
                amount: transaction.amount
            });

            // Step 5: Handle successful payment
            if (success && transaction) {
                await this.handleSuccessfulPayment(transaction);
            }

            // Step 6: Handle failed payment
            if (status === 'failed' && transaction) {
                await this.handleFailedPayment(transaction, failureReason);
            }

            return { received: true, status };

        } catch (error: any) {
            console.error('🔥 Webhook processing error:', error);
            // Return 200 to prevent Paymob retries for invalid requests
            if (error instanceof BadRequestException) {
                return { received: false, error: error.message };
            }
            throw error;
        }
    }

    /**
     * Handle successful payment
     */
    private async handleSuccessfulPayment(transaction: any) {
        try {
            // 1. Update order status to completed
            if (transaction.order_id) {
                await supabase
                    .from('sales_records')
                    .update({ status: 'completed' })
                    .eq('id', transaction.order_id);

                console.log('✅ Order marked as completed:', transaction.order_id);
            }

            // 2. Tag customer as 'Paid'
            if (transaction.customer_id) {
                const { data: customer } = await supabase
                    .from('customers')
                    .select('tags')
                    .eq('id', transaction.customer_id)
                    .single();

                const currentTags = customer?.tags || [];
                if (!currentTags.includes('Paid')) {
                    await supabase
                        .from('customers')
                        .update({ tags: [...currentTags, 'Paid'] })
                        .eq('id', transaction.customer_id);
                }
            }

            // 3. Send confirmation notification
            await this.sendPaymentNotification(transaction, 'success');

            // 4. Trigger automation (if payment success node exists)
            await this.triggerPaymentAutomation(transaction, 'success');

        } catch (error) {
            console.error('Error handling successful payment:', error);
        }
    }

    /**
     * Handle failed payment
     */
    private async handleFailedPayment(transaction: any, reason: string | null) {
        try {
            // 1. Tag customer as 'Payment Failed'
            if (transaction.customer_id) {
                const { data: customer } = await supabase
                    .from('customers')
                    .select('tags')
                    .eq('id', transaction.customer_id)
                    .single();

                const currentTags = customer?.tags || [];
                if (!currentTags.includes('Payment Failed')) {
                    await supabase
                        .from('customers')
                        .update({ tags: [...currentTags, 'Payment Failed'] })
                        .eq('id', transaction.customer_id);
                }
            }

            // 2. Send failure notification with alternative payment methods
            await this.sendPaymentNotification(transaction, 'failed', reason);

            // 3. Trigger automation (if payment failure node exists)
            await this.triggerPaymentAutomation(transaction, 'failed');

        } catch (error) {
            console.error('Error handling failed payment:', error);
        }
    }

    /**
     * Send payment notification to customer
     */
    private async sendPaymentNotification(transaction: any, status: 'success' | 'failed', reason?: string | null) {
        // TODO: Integrate with messaging service (WhatsApp/Messenger/Instagram)
        // For now, just log
        const messages = {
            success: `✅ تم استلام دفعتك بنجاح!\nالمبلغ: ${transaction.amount} جنيه\nرقم المعاملة: ${transaction.id}`,
            failed: `❌ فشلت عملية الدفع\n${reason ? `السبب: ${reason}\n` : ''}جرب طريقة دفع أخرى أو تواصل معنا.`
        };

        console.log('📤 Notification:', {
            customerId: transaction.customer_id,
            message: messages[status]
        });

        // Placeholder for actual implementation
        // await messagingService.send({
        //     to: transaction.customers?.phone,
        //     message: messages[status]
        // });
    }

    /**
     * Trigger payment automation flow
     */
    private async triggerPaymentAutomation(transaction: any, event: 'success' | 'failed') {
        // TODO: Integrate with automation engine
        console.log('🤖 Triggering automation:', {
            event: `payment_${event}`,
            transactionId: transaction.id,
            companyId: transaction.company_id
        });

        // Placeholder for actual implementation
        // await automationEngine.trigger({
        //     event: `payment_${event}`,
        //     data: transaction
        // });
    }

    /**
     * Get Paymob configuration for a company
     */
    private async getPaymobConfig(merchantOrderId: string): Promise<any> {
        // Extract company_id from merchant_order_id (format: company_id-order_id)
        const companyId = merchantOrderId?.split('-')[0];
        if (!companyId) return null;

        const { data } = await supabase
            .from('payment_gateway_config')
            .select('*')
            .eq('company_id', companyId)
            .single();

        if (!data) return null;

        // Decrypt credentials (simplified - use proper encryption in production)
        return {
            apiKey: data.api_key_encrypted, // TODO: Decrypt
            integrationIdCard: data.integration_id_card,
            integrationIdFawry: data.integration_id_fawry,
            integrationIdWallet: data.integration_id_wallet,
            iframeId: data.iframe_id,
            hmacSecret: data.hmac_secret_encrypted // TODO: Decrypt
        };
    }
}
