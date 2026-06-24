import { Body, Controller, Get, Post, Query, Req, UseGuards } from "@nestjs/common";
import { AuthenticatedRequest, AuthGuard } from "../auth/auth.guard";
import { TelemetryBatch } from "../domain/types";
import { TelemetryService } from "./telemetry.service";

@Controller()
@UseGuards(AuthGuard)
export class TelemetryController {
  constructor(private readonly telemetry: TelemetryService) {}

  @Post("telemetry/batch")
  ingest(@Req() request: AuthenticatedRequest, @Body() body: TelemetryBatch) {
    return this.telemetry.ingest(request.authUser.id, body);
  }

  @Get("partner/overview")
  overview(@Req() request: AuthenticatedRequest) {
    return this.telemetry.overviewForPartner(request.authUser.id);
  }

  @Get("partner/app-usage")
  appUsage(@Req() request: AuthenticatedRequest, @Query("date") date?: string) {
    return this.telemetry.appUsageForPartner(request.authUser.id, date);
  }

  @Get("partner/daily-report")
  dailyReport(@Req() request: AuthenticatedRequest, @Query("date") date?: string) {
    return this.telemetry.dailyReportForPartner(request.authUser.id, date);
  }

  @Get("partner/events")
  events(@Req() request: AuthenticatedRequest, @Query("limit") limit?: string) {
    return this.telemetry.eventsForPartner(request.authUser.id, limit ? Number(limit) : undefined);
  }
}

