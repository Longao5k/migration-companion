import { CollaboratorRole } from '@prisma/client';
import { IsEmail, IsEnum, IsString, Length } from 'class-validator';

export class CreateInvitationDto {
  @IsEmail()
  email!: string;

  @IsEnum(CollaboratorRole)
  role!: CollaboratorRole;
}

export class AcceptInvitationDto {
  @IsString()
  @Length(40, 100)
  secret!: string;
}

export class UpdateCollaboratorDto {
  @IsEnum(CollaboratorRole)
  role!: CollaboratorRole;
}

export class CreateCommentDto {
  @IsString()
  @Length(1, 2000)
  body!: string;
}

