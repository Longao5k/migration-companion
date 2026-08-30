import { IsEmail, IsString, Length } from 'class-validator';

export class AdminLoginDto {
  @IsEmail()
  email!: string;

  // 下限 12 位。后台密码是人手输的，不像访问码由我们生成——
  // 不设下限就会出现「admin123」这种，而这个账号能发布政策。
  @IsString()
  @Length(12, 200)
  password!: string;
}
