import {
    Controller,
    Get,
    Post,
    Put,
    Delete,
    Body,
    Param,
    Query,
    UseGuards
} from '@nestjs/common';
import { CrmService, Customer } from './crm.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles, UserRole } from '../auth/decorators/roles.decorator';
import { GetUser } from '../auth/decorators/get-user.decorator';
import { ApiTags, ApiQuery } from '@nestjs/swagger';

@ApiTags('CRM')
@Controller('customers')
@UseGuards(JwtAuthGuard, RolesGuard)
export class CrmController {
    constructor(private readonly crmService: CrmService) { }

    @Get()
    @ApiQuery({ name: 'search', required: false })
    findAll(
        @GetUser('companyId') companyId: string,
        @Query('search') search?: string,
    ) {
        return this.crmService.findAll(companyId, search);
    }

    @Get(':id')
    findOne(
        @Param('id') id: string,
        @GetUser('companyId') companyId: string,
    ) {
        return this.crmService.findOne(id, companyId);
    }

    @Post()
    create(
        @GetUser('companyId') companyId: string,
        @Body() customerData: Partial<Customer>,
    ) {
        return this.crmService.create(companyId, customerData);
    }

    @Put(':id')
    update(
        @Param('id') id: string,
        @GetUser('companyId') companyId: string,
        @Body() customerData: Partial<Customer>,
    ) {
        return this.crmService.update(id, companyId, customerData);
    }

    @Delete(':id')
    @Roles(UserRole.OWNER, UserRole.ADMIN)
    remove(
        @Param('id') id: string,
        @GetUser('companyId') companyId: string,
    ) {
        return this.crmService.remove(id, companyId);
    }
}
