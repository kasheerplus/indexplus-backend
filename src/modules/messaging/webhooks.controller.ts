import { Controller, Post, Get, Query, Body, Headers, UnauthorizedException, Logger, RawBody } from '@nestjs/common';
import { MessagingService } from './messaging.service';
import { ConfigService } from '@nestjs/config';
import { WebhookService } from './webhook.service';
import { ApiTags } from '@nestjs/swagger';

@ApiTags('Webhooks')
@Controller('webhooks')
export class WebhooksController {
    private readonly logger = new Logger(WebhooksController.name);

    constructor(
        private readonly messagingService: MessagingService,
        private readonly configService: ConfigService,
        private readonly webhookService: WebhookService,
    ) { }

    @Post('whatsapp')
    async handleWhatsApp(
        @RawBody() rawBody: Buffer,
        @Headers('x-hub-signature-256') signature: string,
    ) {
        if (!this.webhookService.verifyMetaSignature(rawBody.toString(), signature)) {
            throw new UnauthorizedException('توقيع غير صالح');
        }

        this.logger.log('WhatsApp Webhook Verified');
        // TODO: Process WhatsApp specific logic
        return { status: 'received' };
    }

    // --- FACEBOOK (Messenger) WEBHOOKS ---

    @Get('facebook')
    verifyFacebook(@Query() query: any) {
        return this.webhookService.verifyWebhookChallenge(query);
    }

    @Post('facebook')
    async handleFacebook(
        @RawBody() rawBody: Buffer,
        @Headers('x-hub-signature-256') signature: string,
    ) {
        if (!this.webhookService.verifyMetaSignature(rawBody.toString(), signature)) {
            throw new UnauthorizedException('توقيع غير صالح');
        }

        const event = JSON.parse(rawBody.toString());
        this.logger.log(`Received Facebook Webhook: ${event.object}`);

        if (event.object === 'page') {
            await this.messagingService.processFacebookWebhook(event);
        }

        return { status: 'received' };
    }

    // --- INSTAGRAM WEBHOOKS ---

    @Get('instagram')
    verifyInstagram(@Query() query: any) {
        return this.webhookService.verifyWebhookChallenge(query);
    }

    @Post('instagram')
    async handleInstagram(
        @RawBody() rawBody: Buffer,
        @Headers('x-hub-signature-256') signature: string,
    ) {
        if (!this.webhookService.verifyMetaSignature(rawBody.toString(), signature)) {
            throw new UnauthorizedException('توقيع غير صالح');
        }

        const event = JSON.parse(rawBody.toString());
        this.logger.log(`Received Instagram Webhook: ${event.object}`);

        if (event.object === 'instagram') {
            await this.messagingService.processInstagramWebhook(event);
        }

        return { status: 'received' };
    }
}
