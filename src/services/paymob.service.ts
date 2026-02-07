/**
 * Paymob Payment Gateway Service
 * Handles Egyptian payment methods: Fawry, Wallets, Cards
 */

const PAYMOB_BASE_URL = process.env.PAYMOB_SANDBOX === 'true'
    ? 'https://accept.paymobsolutions.com/api'
    : 'https://accept.paymob.com/api';

interface PaymobConfig {
    apiKey: string;
    integrationIdCard: string;
    integrationIdFawry: string;
    integrationIdWallet: string;
    iframeId: string;
    hmacSecret: string;
}

interface PaymentRequest {
    amount: number;
    customerName: string;
    customerPhone: string;
    customerEmail?: string;
    orderId: string;
    paymentMethod: 'fawry' | 'card' | 'vodafone_cash' | 'orange_money' | 'etisalat_cash';
}

interface PaymentResponse {
    success: boolean;
    paymentUrl?: string;
    referenceCode?: string;
    transactionId?: string;
    expiresAt?: Date;
    error?: string;
}

export class PaymobService {
    private config: PaymobConfig;
    private authToken: string | null = null;
    private tokenExpiry: Date | null = null;

    constructor(config: PaymobConfig) {
        this.config = config;
    }

    /**
     * Step 1: Authenticate with Paymob
     */
    private async getAuthToken(): Promise<string> {
        // Return cached token if still valid
        if (this.authToken && this.tokenExpiry && this.tokenExpiry > new Date()) {
            return this.authToken;
        }

        try {
            const response = await fetch(`${PAYMOB_BASE_URL}/auth/tokens`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ api_key: this.config.apiKey })
            });

            if (!response.ok) {
                throw new Error(`Paymob auth failed: ${response.statusText}`);
            }

            const data = await response.json();
            this.authToken = data.token;
            // Tokens typically expire after 1 hour
            this.tokenExpiry = new Date(Date.now() + 50 * 60 * 1000); // 50 min safety margin

            if (!this.authToken) {
                throw new Error('Failed to retrieve auth token');
            }
            return this.authToken;
        } catch (error) {
            console.error('Paymob authentication error:', error);
            throw new Error('Failed to authenticate with payment gateway');
        }
    }

    /**
     * Step 2: Register Order with Paymob
     */
    private async registerOrder(authToken: string, amount: number, orderId: string): Promise<number> {
        try {
            const response = await fetch(`${PAYMOB_BASE_URL}/ecommerce/orders`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    auth_token: authToken,
                    delivery_needed: false,
                    amount_cents: Math.round(amount * 100), // Convert EGP to cents
                    currency: 'EGP',
                    merchant_order_id: orderId,
                    items: []
                })
            });

            if (!response.ok) {
                throw new Error(`Order registration failed: ${response.statusText}`);
            }

            const data = await response.json();
            return data.id; // Paymob order ID
        } catch (error) {
            console.error('Order registration error:', error);
            throw new Error('Failed to register order with payment gateway');
        }
    }

    /**
     * Step 3: Generate Payment Key
     */
    private async generatePaymentKey(
        authToken: string,
        amount: number,
        paymobOrderId: number,
        customerData: { name: string; phone: string; email?: string },
        integrationId: string
    ): Promise<string> {
        try {
            const [firstName, ...lastNameParts] = customerData.name.split(' ');
            const lastName = lastNameParts.join(' ') || 'Customer';

            const response = await fetch(`${PAYMOB_BASE_URL}/acceptance/payment_keys`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    auth_token: authToken,
                    amount_cents: Math.round(amount * 100),
                    expiration: 3600, // 1 hour
                    order_id: paymobOrderId,
                    billing_data: {
                        first_name: firstName || 'Customer',
                        last_name: lastName,
                        email: customerData.email || 'customer@indexplus.com',
                        phone_number: customerData.phone.replace(/\D/g, ''), // Remove non-digits
                        apartment: 'NA',
                        floor: 'NA',
                        street: 'NA',
                        building: 'NA',
                        shipping_method: 'NA',
                        postal_code: 'NA',
                        city: 'Cairo',
                        country: 'EG',
                        state: 'Cairo'
                    },
                    currency: 'EGP',
                    integration_id: parseInt(integrationId)
                })
            });

            if (!response.ok) {
                throw new Error(`Payment key generation failed: ${response.statusText}`);
            }

            const data = await response.json();
            return data.token;
        } catch (error) {
            console.error('Payment key generation error:', error);
            throw new Error('Failed to generate payment key');
        }
    }

    /**
     * Create Payment for Cards
     */
    async createCardPayment(request: PaymentRequest): Promise<PaymentResponse> {
        try {
            const authToken = await this.getAuthToken();
            const paymobOrderId = await this.registerOrder(authToken, request.amount, request.orderId);
            const paymentToken = await this.generatePaymentKey(
                authToken,
                request.amount,
                paymobOrderId,
                {
                    name: request.customerName,
                    phone: request.customerPhone,
                    email: request.customerEmail
                },
                this.config.integrationIdCard
            );

            return {
                success: true,
                paymentUrl: `https://accept.paymob.com/api/acceptance/iframes/${this.config.iframeId}?payment_token=${paymentToken}`,
                transactionId: paymobOrderId.toString(),
                expiresAt: new Date(Date.now() + 60 * 60 * 1000) // 1 hour
            };
        } catch (error: any) {
            return {
                success: false,
                error: error.message || 'Card payment creation failed'
            };
        }
    }

    /**
     * Create Payment for Fawry
     */
    async createFawryPayment(request: PaymentRequest): Promise<PaymentResponse> {
        try {
            const authToken = await this.getAuthToken();
            const paymobOrderId = await this.registerOrder(authToken, request.amount, request.orderId);
            const paymentToken = await this.generatePaymentKey(
                authToken,
                request.amount,
                paymobOrderId,
                {
                    name: request.customerName,
                    phone: request.customerPhone,
                    email: request.customerEmail
                },
                this.config.integrationIdFawry
            );

            // Fawry reference code is typically the last 16 chars of token
            const referenceCode = paymentToken.substring(paymentToken.length - 16);

            return {
                success: true,
                paymentUrl: `https://accept.paymob.com/fawry?payment_token=${paymentToken}`,
                referenceCode: referenceCode,
                transactionId: paymobOrderId.toString(),
                expiresAt: new Date(Date.now() + 48 * 60 * 60 * 1000) // 48 hours for Fawry
            };
        } catch (error: any) {
            return {
                success: false,
                error: error.message || 'Fawry payment creation failed'
            };
        }
    }

    /**
     * Create Payment for Mobile Wallets
     */
    async createWalletPayment(request: PaymentRequest): Promise<PaymentResponse> {
        try {
            const authToken = await this.getAuthToken();
            const paymobOrderId = await this.registerOrder(authToken, request.amount, request.orderId);
            const paymentToken = await this.generatePaymentKey(
                authToken,
                request.amount,
                paymobOrderId,
                {
                    name: request.customerName,
                    phone: request.customerPhone,
                    email: request.customerEmail
                },
                this.config.integrationIdWallet
            );

            // Wallet payments redirect to provider
            const walletUrls: Record<string, string> = {
                vodafone_cash: `https://accept.paymob.com/api/acceptance/post_pay?payment_token=${paymentToken}`,
                orange_money: `https://accept.paymob.com/api/acceptance/post_pay?payment_token=${paymentToken}`,
                etisalat_cash: `https://accept.paymob.com/api/acceptance/post_pay?payment_token=${paymentToken}`
            };

            return {
                success: true,
                paymentUrl: walletUrls[request.paymentMethod] || walletUrls.vodafone_cash,
                transactionId: paymobOrderId.toString(),
                expiresAt: new Date(Date.now() + 30 * 60 * 1000) // 30 minutes for wallets
            };
        } catch (error: any) {
            return {
                success: false,
                error: error.message || 'Wallet payment creation failed'
            };
        }
    }

    /**
     * Main entry point - Create payment based on method
     */
    async createPayment(request: PaymentRequest): Promise<PaymentResponse> {
        switch (request.paymentMethod) {
            case 'card':
                return this.createCardPayment(request);
            case 'fawry':
                return this.createFawryPayment(request);
            case 'vodafone_cash':
            case 'orange_money':
            case 'etisalat_cash':
                return this.createWalletPayment(request);
            default:
                return {
                    success: false,
                    error: 'Unsupported payment method'
                };
        }
    }

    /**
     * Verify webhook HMAC signature
     */
    verifyWebhookSignature(payload: any, receivedHmac: string): boolean {
        const crypto = require('crypto');

        // Paymob HMAC calculation (specific order of fields)
        const concatenated = [
            payload.amount_cents,
            payload.created_at,
            payload.currency,
            payload.error_occured,
            payload.has_parent_transaction,
            payload.id,
            payload.integration_id,
            payload.is_3d_secure,
            payload.is_auth,
            payload.is_capture,
            payload.is_refunded,
            payload.is_standalone_payment,
            payload.is_voided,
            payload.order?.id,
            payload.owner,
            payload.pending,
            payload.source_data?.pan,
            payload.source_data?.sub_type,
            payload.source_data?.type,
            payload.success
        ].join('');

        const calculatedHmac = crypto
            .createHmac('sha512', this.config.hmacSecret)
            .update(concatenated)
            .digest('hex');

        return calculatedHmac === receivedHmac;
    }
}

export default PaymobService;
