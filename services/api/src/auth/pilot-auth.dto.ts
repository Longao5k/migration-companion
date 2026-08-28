import { IsEmail, IsString, Length } from 'class-validator';

export class PilotLoginDto {
  @IsEmail()
  email!: string;

  @IsString()
  @Length(8, 128)
  accessCode!: string;
}
