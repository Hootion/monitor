import "reflect-metadata";
import compression from "compression";
import helmet from "helmet";
import { NestFactory } from "@nestjs/core";
import { AppModule } from "./app.module";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.enableCors({ origin: true, credentials: true });
  app.use(helmet());
  app.use(compression());
  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port);
  console.log(`Mutual Watch backend listening on http://localhost:${port}`);
}

void bootstrap();

