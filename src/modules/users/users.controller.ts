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
import { UsersService, UserProfile } from './users.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles, UserRole } from '../auth/decorators/roles.decorator';
import { GetUser } from '../auth/decorators/get-user.decorator';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { ApiTags } from '@nestjs/swagger';

@ApiTags('Users')
@Controller('users')
@UseGuards(JwtAuthGuard, RolesGuard)
export class UsersController {
    constructor(private readonly usersService: UsersService) { }

    @Get()
    @Roles(UserRole.OWNER, UserRole.ADMIN)
    findAll(@GetUser('companyId') companyId: string) {
        return this.usersService.findAll(companyId);
    }

    @Get(':id')
    @Roles(UserRole.OWNER, UserRole.ADMIN)
    findOne(
        @Param('id') id: string,
        @GetUser('companyId') companyId: string,
    ) {
        return this.usersService.findOne(id, companyId);
    }

    @Post()
    @Roles(UserRole.OWNER, UserRole.ADMIN)
    create(
        @GetUser('companyId') companyId: string,
        @Body() userData: Partial<UserProfile>,
    ) {
        return this.usersService.create(companyId, userData);
    }

    @Put(':id')
    @Roles(UserRole.OWNER, UserRole.ADMIN)
    update(
        @Param('id') id: string,
        @GetUser('companyId') companyId: string,
        @Body() userData: Partial<UserProfile>,
    ) {
        return this.usersService.update(id, companyId, userData);
    }

    @Delete(':id')
    @Roles(UserRole.OWNER)
    remove(
        @Param('id') id: string,
        @GetUser('companyId') companyId: string,
    ) {
        return this.usersService.remove(id, companyId);
    }
}

