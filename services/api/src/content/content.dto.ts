import { ChangeImportance, ReviewStatus } from '@prisma/client';
import { IsDateString, IsEnum, IsOptional, IsString, IsUrl, Length } from 'class-validator';

export class IngestChangeDto {
  @IsUrl({ require_tld: false })
  sourceUrl!: string;

  @IsString()
  @Length(1, 160)
  sourceName!: string;

  @IsString()
  @Length(1, 240)
  titleZh!: string;

  @IsOptional()
  @IsString()
  @Length(0, 2000)
  oldExcerpt?: string;

  @IsOptional()
  @IsString()
  @Length(0, 2000)
  newExcerpt?: string;

  @IsOptional()
  @IsString()
  @Length(0, 1000)
  context?: string;

  @IsEnum(ChangeImportance)
  importance!: ChangeImportance;

  @IsDateString()
  discoveredAt!: string;
}

export class ReviewChangeDto {
  @IsEnum(ReviewStatus)
  status!: ReviewStatus;

  @IsOptional()
  @IsString()
  @Length(0, 2000)
  editorSummaryZh?: string;

  @IsOptional()
  @IsString()
  @Length(0, 1000)
  correctionNote?: string;
}

