import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Length,
  Max,
  Min,
} from 'class-validator';

export class UpdateNotificationPreferenceDto {
  @IsBoolean()
  policyUpdates!: boolean;

  @IsOptional()
  @IsBoolean()
  productUpdates?: boolean;

  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  @IsIn(['AU-SA', 'AU-FED'], { each: true })
  jurisdictions!: string[];

  @IsArray()
  @ArrayMaxSize(30)
  @IsString({ each: true })
  @IsIn(['190', '491'], { each: true })
  tags!: string[];

  @IsBoolean()
  importantOnly!: boolean;

  @IsString()
  @Length(1, 80)
  timezone!: string;
}

export class ClaimNotificationsDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  batchSize?: number;
}

export class NotificationResultDto {
  @IsIn(['SENT', 'FAILED'])
  status!: 'SENT' | 'FAILED';

  @IsOptional()
  @IsString()
  @Length(1, 120)
  errorCode?: string;
}

export class AcknowledgeNotificationsDto {
  @IsArray()
  @IsString({ each: true })
  @ArrayMaxSize(100)
  ids!: string[];
}
