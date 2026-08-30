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
import { knownTags } from '../content/taxonomy';

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
  // 与内容侧同一份封闭词表（`content/taxonomy.ts`）。
  // 原先写死 ['190','491']，用户订阅不到 485、职业清单这些实际存在的标签；
  // 而完全放开又会让人订阅一个永远匹配不上的字符串。
  @IsIn(knownTags(), { each: true })
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
