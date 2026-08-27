import { ChecklistStatus, ProjectTemplate } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsDateString,
  IsEnum,
  IsInt,
  IsOptional,
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
