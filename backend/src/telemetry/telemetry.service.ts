import { ForbiddenException, Injectable, NotFoundException } from "@nestjs/common";
import { InMemoryStore } from "../domain/in-memory.store";
import { PartnerOverview, TelemetryBatch } from "../domain/types";
import { RealtimeGateway } from "../realtime/realtime.gateway";

const today = () => new Date().toISOString().slice(0, 10);

@Injectable()
export class TelemetryService {
  constructor(
    private readonly store: InMemoryStore,
    private readonly realtime: RealtimeGateway
  ) {}

  ingest(userId: string, batch: TelemetryBatch) {
    const result = this.store.addTelemetry(userId, batch);
    const partnerId = this.store.getPartnerId(userId);
    if (partnerId) {
      this.realtime.notifyUser(partnerId, "partner.updated", {
        partnerId: userId,
        changedAt: new Date().toISOString(),
        snapshot: Boolean(result.snapshot),
        dailyReport: Boolean(result.dailyReport),
        appUsageCount: result.appUsageCount,
        eventCount: result.eventCount
      });
    }
    return { accepted: true, ...result };
  }

  overviewForPartner(userId: string): PartnerOverview {
    const partnerId = this.visiblePartnerId(userId);
    const partner = this.store.findUser(partnerId);
    if (!partner) throw new NotFoundException("Partner not found.");
    return {
      partner: this.store.toPublicUser(partner),
      latestSnapshot: this.store.latestSnapshot(partnerId),
      dailyReport: this.store.reportForDate(partnerId, today()),
      latestEvents: this.store.eventsForUser(partnerId, 10)
    };
  }

  appUsageForPartner(userId: string, date = today()) {
    return { date, sessions: this.store.appUsageForDate(this.visiblePartnerId(userId), date) };
  }

  dailyReportForPartner(userId: string, date = today()) {
    const report = this.store.reportForDate(this.visiblePartnerId(userId), date);
    if (!report) throw new NotFoundException("Daily report not found.");
    return { report };
  }

  eventsForPartner(userId: string, limit?: number) {
    return { events: this.store.eventsForUser(this.visiblePartnerId(userId), limit) };
  }

  private visiblePartnerId(userId: string): string {
    const partnerId = this.store.getPartnerId(userId);
    if (!partnerId) {
      throw new ForbiddenException("No active pairing.");
    }
    const partner = this.store.findUser(partnerId);
    if (!partner) {
      throw new NotFoundException("Partner not found.");
    }
    if (partner.sharingPaused) {
      throw new ForbiddenException("Partner has paused sharing.");
    }
    return partnerId;
  }
}

