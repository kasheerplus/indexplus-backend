import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';

export interface AuthenticatedUser {
    id: string;
    email: string;
    companyId: string;
    role: string;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
    constructor(private readonly configService: ConfigService) {
        super({
            jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
            ignoreExpiration: false,
            secretOrKey: configService.get<string>('JWT_SECRET')!,
        });
    }

    async validate(payload: any): Promise<AuthenticatedUser> {
        // Supabase JWT payload structure:
        // {
        //   sub: "user_id",
        //   email: "user@example.com",
        //   company_id: "...", // Custom claim
        //   role: "authenticated",
        //   ...
        // }
        return {
            id: payload.sub,
            email: payload.email,
            companyId: payload.company_id,
            role: payload.role,
        };
    }
}
