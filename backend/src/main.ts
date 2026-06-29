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
  const host = process.env.HOST ?? "0.0.0.0";
  await app.listen(port, host);
  console.log(`Mutual Watch backend listening on http://${host}:${port}`);
}

void bootstrap();
