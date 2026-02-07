import { Module } from '@nestjs/common';
import { MessagingService } from './messaging.service';
import { MessagingController } from './messaging.controller';
import { WebhooksController } from './webhooks.controller';
import { WebhookService } from './webhook.service';

@Module({
    providers: [MessagingService, WebhookService],
    controllers: [MessagingController, WebhooksController],
    exports: [MessagingService],
})
export class MessagingModule { }
