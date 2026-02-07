import { SetMetadata } from '@nestjs/common';

export enum UserRole {
    SUPER_ADMIN = 'super_admin',
    OWNER = 'owner',
    ADMIN = 'admin',
    AGENT = 'agent',
}

export const ROLES_KEY = 'roles';
export const Roles = (...roles: UserRole[]) => SetMetadata(ROLES_KEY, roles);
