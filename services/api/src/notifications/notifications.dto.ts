import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Length,
  Matches,
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
  // 覆盖八个州领地加联邦。原先只允许 AU-SA / AU-FED，而库里已经有
  // AU-QLD / AU-NSW / AU-WA 的内容——那三个州的资讯匹配不到任何收件人，且不报错。
  @IsIn(
    [
      'AU-SA', 'AU-QLD', 'AU-NSW', 'AU-VIC',
      'AU-WA', 'AU-TAS', 'AU-NT', 'AU-ACT', 'AU-FED',
    ],
    { each: true },
  )
  jurisdictions!: string[];

  @IsArray()
  @ArrayMaxSize(30)
  @IsString({ each: true })
  // 标签不再限定为 190/491：内容上的标签主要是辖区名（南澳/昆士兰/联邦）
  // 加签证类别。写死两个值等于让用户订阅不到绝大多数内容承载的那个标签。
  // 只做长度与字符约束，具体词表由内容决定。
  @Length(1, 24, { each: true })
  @Matches(/^[一-龥A-Za-z0-9_-]+$/, { each: true })
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
