import {
    Controller,
    Get,
    Post,
    Body,
    UseGuards
} from '@nestjs/common';
import { SubscriptionsService, PaymentProof } from './subscriptions.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles, UserRole } from '../auth/decorators/roles.decorator';
import { GetUser } from '../auth/decorators/get-user.decorator';
import { ApiTags } from '@nestjs/swagger';

@ApiTags('Subscriptions')
@Controller('subscriptions')
@UseGuards(JwtAuthGuard, RolesGuard)
export class SubscriptionsController {
    constructor(private readonly subscriptionsService: SubscriptionsService) { }

    @Get('current')
    getCurrent(@GetUser('companyId') companyId: string) {
        return this.subscriptionsService.getCurrent(companyId);
    }

    @Get('history')
    @Roles(UserRole.OWNER, UserRole.ADMIN)
    getHistory(@GetUser('companyId') companyId: string) {
        return this.subscriptionsService.getHistory(companyId);
    }

    @Post('proof')
    @Roles(UserRole.OWNER)
    createProof(
        @GetUser('companyId') companyId: string,
        @Body() proofData: Partial<PaymentProof>,
    ) {
        return this.subscriptionsService.createPaymentProof(companyId, proofData);
    }

    @Get('proofs')
    @Roles(UserRole.OWNER, UserRole.ADMIN)
    getProofs(@GetUser('companyId') companyId: string) {
        return this.subscriptionsService.getPaymentProofs(companyId);
    }
}
