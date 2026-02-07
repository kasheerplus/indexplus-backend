import { Injectable, UnauthorizedException, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as crypto from 'crypto';

@Injectable()
export class WebhookService {
    private readonly logger = new Logger(WebhookService.name);

    constructor(private readonly configService: ConfigService) { }

    verifyWebhookChallenge(query: any): string {
        const mode = query['hub.mode'];
        const token = query['hub.verify_token'];
        const challenge = query['hub.challenge'];

        const verifyToken = this.configService.get<string>('META_VERIFY_TOKEN');

        if (mode === 'subscribe' && token === verifyToken) {
            this.logger.log('Webhook Verified Successfully');
            return challenge;
        }

        this.logger.error('Webhook Verification Failed: Token Mismatch');
        throw new UnauthorizedException('فشل التحقق من التوقيع');
    }

    verifyMetaSignature(payload: string, signature: string): boolean {
        const secret = this.configService.get<string>(`META_APP_SECRET`);
        if (!secret || !signature) return false;

        const [algorithm, hash] = signature.split('=');
        if (algorithm !== 'sha256') return false;

        const expectedHash = crypto
            .createHmac('sha256', secret)
            .update(payload)
            .digest('hex');

        return crypto.timingSafeEqual(
            Buffer.from(hash),
            Buffer.from(expectedHash)
        );
    }
}
