import { Controller, Post, UseGuards } from '@nestjs/common';
import { WorkerApiKeyGuard } from '../content/api-key.guard';
import { AccountDeletionService } from './account-deletion.service';

@Controller('account-worker')
@UseGuards(WorkerApiKeyGuard)
export class AccountDeletionWorkerController {
  constructor(private readonly deletion: AccountDeletionService) {}

  @Post('run-due-deletions')
  runDueDeletions() {
    return this.deletion.runDueDeletions();
  }
}
