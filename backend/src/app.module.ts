import { Module } from "@nestjs/common";
import { AccountController } from "./account/account.controller";
import { AuthController } from "./auth/auth.controller";
import { AuthGuard } from "./auth/auth.guard";
import { AuthService } from "./auth/auth.service";
import { TokenService } from "./auth/token.service";
import { InMemoryStore } from "./domain/in-memory.store";
import { PairingController } from "./pairing/pairing.controller";
import { PairingService } from "./pairing/pairing.service";
import { RealtimeGateway } from "./realtime/realtime.gateway";
import { TelemetryController } from "./telemetry/telemetry.controller";
import { TelemetryService } from "./telemetry/telemetry.service";

@Module({
  controllers: [AccountController, AuthController, PairingController, TelemetryController],
  providers: [AuthGuard, AuthService, InMemoryStore, PairingService, RealtimeGateway, TelemetryService, TokenService]
})
export class AppModule {}

