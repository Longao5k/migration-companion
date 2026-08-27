import { INestApplication, ValidationPipe } from '@nestjs/common';
import helmet from 'helmet';

/**
 * Shared HTTP configuration so the end-to-end acceptance suite exercises the same
 * prefix, validation and hardening pipeline as the deployed process.
 */
export function configureApp(app: INestApplication) {
  app.use(helmet());
  app.enableCors({
    origin: (process.env.APP_ORIGIN ?? 'http://localhost:5173').split(','),
    credentials: false,
  });
  app.setGlobalPrefix('v1');
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
  );
  return app;
}
