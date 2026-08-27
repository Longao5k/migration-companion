import { IsDateString, IsEmail, IsIn, IsOptional, IsString, Length } from 'class-validator';

export class VerifiedStoreEventDto {
  @IsIn(['APPLE', 'GOOGLE'])
  provider!: 'APPLE' | 'GOOGLE';

  @IsString()
  @Length(1, 160)
  productId!: string;

  @IsIn(['ACTIVE', 'GRACE', 'EXPIRED', 'REVOKED', 'REFUNDED'])
  status!: 'ACTIVE' | 'GRACE' | 'EXPIRED' | 'REVOKED' | 'REFUNDED';

  @IsString()
  @Length(8, 240)
  originalTransaction!: string;

  @IsEmail()
  accountEmail!: string;

  @IsOptional()
  @IsDateString()
  currentPeriodEndsAt?: string;
}

export class SubmitPurchaseDto {
  @IsIn(['APPLE', 'GOOGLE', 'LOCAL_SANDBOX'])
  provider!: 'APPLE' | 'GOOGLE' | 'LOCAL_SANDBOX';

  @IsString()
  @Length(1, 160)
  productId!: string;

  @IsString()
  @Length(8, 20000)
  verificationData!: string;
}
