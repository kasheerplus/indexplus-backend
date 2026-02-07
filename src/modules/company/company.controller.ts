import { Controller, Get, UseGuards } from '@nestjs/common';
import { CompanyService } from './company.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { GetUser } from '../auth/decorators/get-user.decorator';

@Controller('company')
@UseGuards(JwtAuthGuard)
export class CompanyController {
    constructor(private readonly companyService: CompanyService) { }

    @Get('profile')
    async getProfile(@GetUser('companyId') companyId: string) {
        return this.companyService.getCompanyProfile(companyId);
    }
}
