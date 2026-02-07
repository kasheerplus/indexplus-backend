import { Controller, Get, Post, Body, Param, Query, UseGuards } from '@nestjs/common';
import { MessagingService } from './messaging.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { GetUser } from '../auth/decorators/get-user.decorator';

@Controller('messaging')
@UseGuards(JwtAuthGuard)
export class MessagingController {
    constructor(private readonly messagingService: MessagingService) { }

    @Get('conversations')
    async getConversations(
        @GetUser('companyId') companyId: string,
        @Query('status') status?: string,
    ) {
        return this.messagingService.getConversations(companyId, status);
    }

    @Get('conversations/:id/messages')
    async getMessages(
        @Param('id') conversationId: string,
        @GetUser('companyId') companyId: string,
    ) {
        return this.messagingService.getConversationMessages(conversationId, companyId);
    }

    @Post('conversations/:id/send')
    async sendMessage(
        @Param('id') conversationId: string,
        @GetUser('companyId') companyId: string,
        @GetUser('id') agentId: string,
        @Body('content') content: string,
        @Body('metadata') metadata?: any,
    ) {
        return this.messagingService.sendMessage(conversationId, companyId, agentId, content, metadata);
    }

    @Post('conversations/:id/read')
    async markAsRead(
        @Param('id') conversationId: string,
        @GetUser('companyId') companyId: string,
    ) {
        return this.messagingService.markAsRead(conversationId, companyId);
    }

    @Post('meta/exchange')
    async exchangeMetaCode(
        @Body('code') code: string,
        @GetUser('companyId') companyId: string,
    ) {
        return this.messagingService.exchangeMetaCode(code, companyId);
    }
}
