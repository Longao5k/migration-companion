import { ChangeImportance, ReviewStatus } from '@prisma/client';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsDateString,
  IsEnum,
  IsIn,
  IsInt,
  Max,
  Min,
  IsOptional,
  IsString,
  IsUrl,
  Length,
} from 'class-validator';

export class CreateSourceDto {
  @IsString()
  @Length(1, 160)
  name!: string;

  @IsUrl({ require_tld: false })
  url!: string;

  @IsString()
  @Length(1, 32)
  jurisdiction!: string;

  @IsString()
  @Length(1, 40)
  sourceType!: string;

  @IsOptional()
  @IsString()
  @Length(0, 1000)
  licenseNote?: string;

  @IsOptional()
  @IsBoolean()
  enabled?: boolean;
}

export class UpdateSourceDto {
  @IsOptional()
  @IsString()
  @Length(1, 160)
  name?: string;

  @IsOptional()
  @IsString()
  @Length(1, 32)
  jurisdiction?: string;

  @IsOptional()
  @IsString()
  @Length(1, 40)
  sourceType?: string;

  @IsOptional()
  @IsString()
  @Length(0, 1000)
  licenseNote?: string;

  @IsOptional()
  @IsBoolean()
  enabled?: boolean;
}

export class CreateNewsDto {
  @IsString()
  sourceId!: string;

  @IsString()
  @Length(1, 240)
  titleZh!: string;

  @IsString()
  @Length(1, 2000)
  summaryZh!: string;

  @IsString()
  @Length(1, 240)
  sourceTitle!: string;

  @IsUrl({ require_tld: false })
  sourceUrl!: string;

  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  tags!: string[];

  @IsDateString()
  publishedAt!: string;

  @IsOptional()
  @IsBoolean()
  isPublished?: boolean;
}

export class UpdateNewsDto {
  @IsOptional()
  @IsString()
  @Length(1, 240)
  titleZh?: string;

  @IsOptional()
  @IsString()
  @Length(1, 2000)
  summaryZh?: string;

  @IsOptional()
  @IsString()
  @Length(1, 240)
  sourceTitle?: string;

  @IsOptional()
  @IsUrl({ require_tld: false })
  sourceUrl?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  tags?: string[];

  @IsOptional()
  @IsDateString()
  publishedAt?: string;

  @IsOptional()
  @IsBoolean()
  isPublished?: boolean;
}

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

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  tags?: string[];
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

export class SourceCheckDto {
  @IsUrl({ require_tld: false })
  sourceUrl!: string;

  @IsString()
  @Length(1, 160)
  sourceName!: string;

  @IsString()
  @Length(1, 32)
  jurisdiction!: string;

  @IsIn(['SUCCESS', 'NOT_MODIFIED', 'ERROR'])
  status!: 'SUCCESS' | 'NOT_MODIFIED' | 'ERROR';

  @IsDateString()
  checkedAt!: string;

  @IsOptional()
  @IsString()
  @Length(64, 64)
  contentHash?: string;

  @IsOptional()
  @IsString()
  @Length(1, 500)
  snapshotKey?: string;

  @IsOptional()
  @IsString()
  @Length(1, 240)
  etag?: string;

  @IsOptional()
  @IsString()
  @Length(1, 240)
  lastModified?: string;

  @IsOptional()
  @IsString()
  @Length(1, 120)
  errorCode?: string;

  @IsOptional()
  @IsInt()
  @Min(100)
  @Max(599)
  httpStatus?: number;
}
