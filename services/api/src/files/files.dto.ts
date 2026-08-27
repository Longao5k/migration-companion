import { FileScanStatus } from '@prisma/client';
import { IsEnum, IsInt, IsOptional, IsString, Length, Matches, Max, Min } from 'class-validator';

export class CreateUploadDto {
  @IsString()
  @Length(1, 240)
  originalName!: string;

  @IsString()
  @Length(1, 120)
  contentType!: string;

  @IsInt()
  @Min(1)
  @Max(50 * 1024 * 1024)
  byteSize!: number;

  @IsString()
  @Matches(/^[a-f0-9]{64}$/)
  sha256!: string;

  @IsOptional()
  @IsString()
  checklistItemId?: string;
}

export class CompleteUploadDto {
  @IsOptional()
  @IsString()
  checklistItemId?: string;
}

export class DirectUploadDto {
  @IsOptional()
  @IsString()
  checklistItemId?: string;
}

export class ScanResultDto {
  @IsEnum(FileScanStatus)
  status!: FileScanStatus;

  @IsString()
  @Length(1, 120)
  scannerVersion!: string;
}
