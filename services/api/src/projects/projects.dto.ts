import { ChecklistStatus, ProjectTemplate } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsDateString,
  IsEnum,
  IsInt,
  IsOptional,
  IsIn,
  IsString,
  Length,
  Min,
} from 'class-validator';

export class CreateProjectDto {
  @IsString()
  @Length(1, 120)
  name!: string;

  @IsEnum(ProjectTemplate)
  template!: ProjectTemplate;

  @IsString()
  @Length(1, 120)
  applicantName!: string;

  @IsOptional()
  @IsDateString()
  targetDate?: string;
}

export class UpdateChecklistDto {
  @IsEnum(ChecklistStatus)
  status!: ChecklistStatus;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedProjectVersion!: number;

  @IsOptional()
  @IsString()
  @Length(0, 2000)
  note?: string;

  @IsOptional()
  @IsDateString()
  dueAt?: string;

  @IsOptional()
  @IsDateString()
  reminderAt?: string;

  @IsOptional()
  @IsBoolean()
  clearDueAt?: boolean;

  @IsOptional()
  @IsBoolean()
  clearReminderAt?: boolean;
}

export class CloudFilesConsentDto {
  @IsBoolean()
  enabled!: boolean;
}

export class ViewerDownloadDto {
  @IsBoolean()
  enabled!: boolean;
}

export class CreateChecklistItemDto {
  @IsString()
  @Length(1, 240)
  title!: string;

  @IsOptional()
  @IsString()
  @Length(1, 120)
  category?: string;
}

export class SyncOperationDto {
  @IsString()
  @Length(8, 100)
  operationId!: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  baseVersion!: number;

  @IsIn(['ADD_CHECKLIST', 'UPDATE_CHECKLIST'])
  kind!: 'ADD_CHECKLIST' | 'UPDATE_CHECKLIST';

  @IsString()
  @Length(1, 100)
  clientItemId!: string;

  @IsOptional()
  @IsString()
  remoteItemId?: string;

  @IsOptional()
  @IsString()
  @Length(1, 240)
  title?: string;

  @IsOptional()
  @IsString()
  @Length(1, 120)
  category?: string;

  @IsOptional()
  @IsEnum(ChecklistStatus)
  status?: ChecklistStatus;

  @IsOptional()
  @IsString()
  @Length(0, 2000)
  note?: string;

  @IsOptional()
  @IsDateString()
  dueAt?: string;

  @IsOptional()
  @IsDateString()
  reminderAt?: string;

  @IsOptional()
  @IsBoolean()
  clearDueAt?: boolean;

  @IsOptional()
  @IsBoolean()
  clearReminderAt?: boolean;
}
