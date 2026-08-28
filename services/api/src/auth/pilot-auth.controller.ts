import { Body, Controller, Post } from '@nestjs/common';
import { PilotLoginDto } from './pilot-auth.dto';
import { PilotAuthService } from './pilot-auth.service';

@Controller('auth')
export class PilotAuthController {
  constructor(private readonly pilotAuth: PilotAuthService) {}

  @Post('pilot')
  login(@Body() body: PilotLoginDto) {
    return this.pilotAuth.login(body);
  }
}
