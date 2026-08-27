import { CollaboratorRole } from '@prisma/client';
import { ForbiddenException } from '@nestjs/common';
import { ProjectsService } from '../src/projects/projects.service';

describe('ProjectsService permissions', () => {
  it('does not let a viewer enable cloud file upload', async () => {
    const prisma = {
      project: {
        findUnique: jest.fn().mockResolvedValue({
          ownerId: 'owner',
          collaborators: [{ role: CollaboratorRole.VIEWER }],
        }),
      },
    } as any;
    const service = new ProjectsService(prisma);

    await expect(service.setCloudFiles('viewer', 'project-1', true)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });
});

