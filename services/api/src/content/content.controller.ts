import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { AdminApiKeyGuard, WorkerApiKeyGuard } from './api-key.guard';
import {
  CreateNewsDto,
  CreateSourceDto,
  IngestChangeDto,
  IngestNewsDto,
  ReviewChangeDto,
  SourceCheckDto,
  UpdateNewsDto,
  UpdateSourceDto,
} from './content.dto';
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

  @Get('monitoring')
  monitoring() {
    return this.content.monitoringStatus();
  }

  @Get('admin/review-queue')
  @UseGuards(AdminApiKeyGuard)
  reviewQueue() {
    return this.content.reviewQueue();
  }

  @Get('admin/changes')
  @UseGuards(AdminApiKeyGuard)
  adminChanges() {
    return this.content.adminChanges();
  }

  @Get('admin/corrections')
  @UseGuards(AdminApiKeyGuard)
  corrections() {
    return this.content.corrections();
  }

  @Get('admin/sources')
  @UseGuards(AdminApiKeyGuard)
  sources() {
    return this.content.sources();
  }

  @Post('admin/sources')
  @UseGuards(AdminApiKeyGuard)
  createSource(@Body() body: CreateSourceDto) {
    return this.content.createSource(body);
  }

  @Patch('admin/sources/:id')
  @UseGuards(AdminApiKeyGuard)
  updateSource(@Param('id') id: string, @Body() body: UpdateSourceDto) {
    return this.content.updateSource(id, body);
  }

  @Get('admin/news')
  @UseGuards(AdminApiKeyGuard)
  adminNews() {
    return this.content.adminNews();
  }

  @Post('admin/news')
  @UseGuards(AdminApiKeyGuard)
  createNews(@Body() body: CreateNewsDto) {
    return this.content.createNews(body);
  }

  @Patch('admin/news/:id')
  @UseGuards(AdminApiKeyGuard)
  updateNews(@Param('id') id: string, @Body() body: UpdateNewsDto) {
    return this.content.updateNews(id, body);
  }

  @Get('admin/tags')
  @UseGuards(AdminApiKeyGuard)
  tags() {
    return this.content.tags();
  }

  @Get('admin/source-health')
  @UseGuards(AdminApiKeyGuard)
  sourceHealth() {
    return this.content.sourceHealth();
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

  @Post('worker/news')
  @UseGuards(WorkerApiKeyGuard)
  ingestNews(@Body() body: IngestNewsDto) {
    return this.content.ingestNews(body);
  }

  @Post('worker/source-checks')
  @UseGuards(WorkerApiKeyGuard)
  sourceCheck(@Body() body: SourceCheckDto) {
    return this.content.reportSourceCheck(body);
  }
}
