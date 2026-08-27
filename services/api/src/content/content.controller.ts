import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { AdminApiKeyGuard, WorkerApiKeyGuard } from './api-key.guard';
import { IngestChangeDto, ReviewChangeDto } from './content.dto';
import { ContentService } from './content.service';

@Controller('content')
export class ContentController {
  constructor(private readonly content: ContentService) {}

  @Get('news')
  news() {
    return this.content.news();
  }

  @Get('changes')
  changes() {
    return this.content.changes();
  }

  @Get('admin/review-queue')
  @UseGuards(AdminApiKeyGuard)
  reviewQueue() {
    return this.content.reviewQueue();
  }

  @Patch('admin/changes/:id/review')
  @UseGuards(AdminApiKeyGuard)
  review(@Param('id') id: string, @Body() body: ReviewChangeDto) {
    return this.content.review(id, body);
  }

  @Post('worker/changes')
  @UseGuards(WorkerApiKeyGuard)
  ingest(@Body() body: IngestChangeDto) {
    return this.content.ingest(body);
  }
}

