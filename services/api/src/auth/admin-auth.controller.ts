import { Body, Controller, Post } from '@nestjs/common';
import { AdminLoginDto } from './admin-auth.dto';
import { AdminAuthService } from './admin-auth.service';

@Controller('auth')
export class AdminAuthController {
  constructor(private readonly adminAuth: AdminAuthService) {}

  @Post('admin')
  login(@Body() body: AdminLoginDto) {
    return this.adminAuth.login(body);
  }
}
