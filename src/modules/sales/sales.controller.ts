import {
    Controller,
    Get,
    Post,
    Put,
    Body,
    Param,
    Query,
    UseGuards
} from '@nestjs/common';
import { SalesService, SaleRecord } from './sales.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles, UserRole } from '../auth/decorators/roles.decorator';
import { GetUser } from '../auth/decorators/get-user.decorator';
import { ApiTags, ApiQuery } from '@nestjs/swagger';

@ApiTags('Sales')
@Controller('sales')
@UseGuards(JwtAuthGuard, RolesGuard)
export class SalesController {
    constructor(private readonly salesService: SalesService) { }

    @Get()
    @ApiQuery({ name: 'customer_id', required: false })
    @ApiQuery({ name: 'status', required: false })
    findAll(
        @GetUser('companyId') companyId: string,
        @Query('customer_id') customerId?: string,
        @Query('status') status?: string,
    ) {
        return this.salesService.findAll(companyId, { customer_id: customerId, status });
    }

    @Get('stats')
    @Roles(UserRole.OWNER, UserRole.ADMIN)
    getStats(@GetUser('companyId') companyId: string) {
        return this.salesService.getStats(companyId);
    }

    @Get(':id')
    findOne(
        @Param('id') id: string,
        @GetUser('companyId') companyId: string,
    ) {
        return this.salesService.findOne(id, companyId);
    }

    @Post()
    create(
        @GetUser('companyId') companyId: string,
        @Body() saleData: Partial<SaleRecord>,
    ) {
        return this.salesService.create(companyId, saleData);
    }

    @Put(':id/status')
    @Roles(UserRole.OWNER, UserRole.ADMIN, UserRole.AGENT)
    updateStatus(
        @Param('id') id: string,
        @GetUser('companyId') companyId: string,
        @Body('status') status: string,
    ) {
        return this.salesService.updateStatus(id, companyId, status);
    }
}
