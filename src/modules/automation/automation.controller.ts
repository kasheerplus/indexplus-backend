import {
    Controller,
    Get,
    Post,
    Put,
    Delete,
    Body,
    Param,
    UseGuards
} from '@nestjs/common';
import { AutomationService, QuickReply, KeywordTrigger } from './automation.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles, UserRole } from '../auth/decorators/roles.decorator';
import { GetUser } from '../auth/decorators/get-user.decorator';
import { ApiTags } from '@nestjs/swagger';

@ApiTags('Automation')
@Controller('automation')
@UseGuards(JwtAuthGuard, RolesGuard)
export class AutomationController {
    constructor(private readonly automationService: AutomationService) { }

    @Get('quick-replies')
    findAllQuickReplies(@GetUser('companyId') companyId: string) {
        return this.automationService.findAllQuickReplies(companyId);
    }

    @Post('quick-replies')
    @Roles(UserRole.OWNER, UserRole.ADMIN, UserRole.AGENT)
    createQuickReply(
        @GetUser('companyId') companyId: string,
        @Body() replyData: Partial<QuickReply>,
    ) {
        return this.automationService.createQuickReply(companyId, replyData);
    }

    @Delete('quick-replies/:id')
    @Roles(UserRole.OWNER, UserRole.ADMIN)
    removeQuickReply(
        @Param('id') id: string,
        @GetUser('companyId') companyId: string,
    ) {
        return this.automationService.removeQuickReply(id, companyId);
    }

    @Get('keyword-triggers')
    findAllKeywordTriggers(@GetUser('companyId') companyId: string) {
        return this.automationService.findAllKeywordTriggers(companyId);
    }

    @Post('keyword-triggers')
    @Roles(UserRole.OWNER, UserRole.ADMIN)
    createKeywordTrigger(
        @GetUser('companyId') companyId: string,
        @Body() triggerData: Partial<KeywordTrigger>,
    ) {
        return this.automationService.createKeywordTrigger(companyId, triggerData);
    }

    @Put('keyword-triggers/:id')
    @Roles(UserRole.OWNER, UserRole.ADMIN)
    updateKeywordTrigger(
        @Param('id') id: string,
        @GetUser('companyId') companyId: string,
        @Body() triggerData: Partial<KeywordTrigger>,
    ) {
        return this.automationService.updateKeywordTrigger(id, companyId, triggerData);
    }
}
