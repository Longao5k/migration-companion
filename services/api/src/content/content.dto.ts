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

export class IngestNewsDto {
  @IsUrl({ require_tld: false })
  sourceRegistryUrl!: string;

  @IsUrl({ require_tld: false })
  sourceUrl!: string;

  @IsString()
  @Length(1, 240)
  sourceTitle!: string;

  @IsString()
  @Length(1, 2000)
  sourceExcerpt!: string;

  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  tags!: string[];

  @IsDateString()
  publishedAt!: string;
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

  // 引用配额。冻结规则要求正文只保留生成差异和审计所需的最小证据，不把官方全文
  // 作为自有内容重新发布。原先各 2000 字、合计 4000 字：实测南澳新闻页规范化正文
  // 只有 2219 字，配额是整页的 180%，而 /v1/content/changes 是公开免鉴权接口——
  // 也就是说旧规则允许把整页官方原文经公开接口发出去。见 excerptQuota。
  @IsOptional()
  @IsString()
  @Length(0, 600)
  oldExcerpt?: string;

  @IsOptional()
  @IsString()
  @Length(0, 600)
  newExcerpt?: string;

  @IsOptional()
  @IsString()
  @Length(0, 600)
  context?: string;

  /// 来源页面规范化正文的字符数，由采集器提供。用于把引用限制在页面正文的一定比例内：
  /// 固定字符上限对短页面仍然可能等于整页。缺省时只能退回固定上限。
  @IsOptional()
  @IsInt()
  @Min(1)
  sourceBodyChars?: number;

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
