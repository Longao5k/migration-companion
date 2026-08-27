import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  Length,
  MinLength,
} from 'class-validator';

export class CreateShareDto {
  @Type(() => Number)
  @IsIn([1, 7, 14, 30])
  expiresInDays!: 1 | 7 | 14 | 30;

  @IsBoolean()
  allowDownload!: boolean;

  @IsOptional()
  @IsString()
  @MinLength(8)
  accessCode?: string;

  @IsArray()
  @ArrayMaxSize(100)
  @IsString({ each: true })
  checklistItemIds!: string[];

  @IsArray()
  @ArrayMaxSize(100)
  @IsString({ each: true })
  fileIds!: string[];

  @IsBoolean()
  includeNotes!: boolean;
}

export class AccessShareDto {
  @IsString()
  @Length(40, 100)
  secret!: string;

  @IsString()
  @Length(8, 64)
  accessCode!: string;
}

