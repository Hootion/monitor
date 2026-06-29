import { Injectable } from "@nestjs/common";
import { randomInt, randomUUID } from "crypto";
import {
  AppUsageSession,
  ConsentLog,
  DailyUsageReport,
  DeviceLocation,
  DeviceSnapshot,
  OperationEvent,
  Pairing,
  PairingInvite,
  PublicUser,
  TelemetryBatch,
  User
} from "./types";

const now = () => new Date().toISOString();
const datePart = (value: string) => value.slice(0, 10);

@Injectable()
export class InMemoryStore {
  private users = new Map<string, User>();
  private usersByPhone = new Map<string, string>();
  private refreshTokens = new Map<string, { userId: string; expiresAt: string }>();
  private invites = new Map<string, PairingInvite>();
  private pairings = new Map<string, Pairing>();
  private consentLogs: ConsentLog[] = [];
  private snapshots = new Map<string, DeviceSnapshot[]>();
  private locations = new Map<string, DeviceLocation[]>();
  private appUsage = new Map<string, AppUsageSession[]>();
  private dailyReports = new Map<string, DailyUsageReport>();
  private events = new Map<string, OperationEvent[]>();
  private eventKeys = new Set<string>();

  createUser(input: { displayName: string; phone?: string; passwordHash: string; passwordSalt: string }): User {
    const id = randomUUID();
    const user: User = {
      id,
      displayName: input.displayName,
      phone: input.phone,
      passwordHash: input.passwordHash,
      passwordSalt: input.passwordSalt,
      sharingPaused: false,
      createdAt: now(),
      updatedAt: now()
    };
    this.users.set(id, user);
    if (input.phone) {
      this.usersByPhone.set(input.phone, id);
    }
    return user;
  }

  findUser(id: string): User | undefined {
    return this.users.get(id);
  }

  findUserByPhone(phone: string): User | undefined {
    const id = this.usersByPhone.get(phone);
    return id ? this.users.get(id) : undefined;
  }

  toPublicUser(user: User): PublicUser {
    return {
      id: user.id,
      displayName: user.displayName,
      phone: user.phone,
      sharingPaused: user.sharingPaused,
      createdAt: user.createdAt
    };
  }

  saveRefreshToken(tokenHash: string, userId: string, expiresAt: string): void {
    this.refreshTokens.set(tokenHash, { userId, expiresAt });
  }

  consumeRefreshToken(tokenHash: string): User | undefined {
    const record = this.refreshTokens.get(tokenHash);
    if (!record) return undefined;
    this.refreshTokens.delete(tokenHash);
    if (new Date(record.expiresAt).getTime() < Date.now()) return undefined;
    return this.users.get(record.userId);
  }

  createInvite(userId: string): PairingInvite {
    for (const invite of this.invites.values()) {
      if (invite.createdByUserId === userId && new Date(invite.expiresAt).getTime() > Date.now()) {
        this.invites.delete(invite.code);
      }
    }
    const code = String(randomInt(100000, 999999));
    const invite: PairingInvite = {
      code,
      createdByUserId: userId,
      createdAt: now(),
      expiresAt: new Date(Date.now() + 10 * 60 * 1000).toISOString()
    };
    this.invites.set(code, invite);
    this.addConsent(userId, "invite_created", { code });
    return invite;
  }

  acceptInvite(code: string, accepterUserId: string): Pairing | "not_found" | "expired" | "self" | "already_paired" {
    const invite = this.invites.get(code);
    if (!invite) return "not_found";
    if (new Date(invite.expiresAt).getTime() < Date.now()) {
      this.invites.delete(code);
      return "expired";
    }
    if (invite.createdByUserId === accepterUserId) return "self";
    if (this.getActivePairing(invite.createdByUserId) || this.getActivePairing(accepterUserId)) {
      return "already_paired";
    }
    const pairing: Pairing = {
      id: randomUUID(),
      userAId: invite.createdByUserId,
      userBId: accepterUserId,
      createdAt: now()
    };
    this.pairings.set(pairing.id, pairing);
    this.invites.delete(code);
    this.addConsent(invite.createdByUserId, "pairing_accepted", { pairingId: pairing.id, partnerId: accepterUserId });
    this.addConsent(accepterUserId, "pairing_accepted", { pairingId: pairing.id, partnerId: invite.createdByUserId });
    return pairing;
  }

  getActivePairing(userId: string): Pairing | undefined {
    return [...this.pairings.values()].find((pairing) => pairing.userAId === userId || pairing.userBId === userId);
  }

  getPartnerId(userId: string): string | undefined {
    const pairing = this.getActivePairing(userId);
    if (!pairing) return undefined;
    return pairing.userAId === userId ? pairing.userBId : pairing.userAId;
  }

  deletePairing(userId: string): boolean {
    const pairing = this.getActivePairing(userId);
    if (!pairing) return false;
    this.pairings.delete(pairing.id);
    this.addConsent(pairing.userAId, "pairing_deleted", { pairingId: pairing.id });
    this.addConsent(pairing.userBId, "pairing_deleted", { pairingId: pairing.id });
    return true;
  }

  setSharingPaused(userId: string, paused: boolean): User | undefined {
    const user = this.users.get(userId);
    if (!user) return undefined;
    user.sharingPaused = paused;
    user.updatedAt = now();
    this.addConsent(userId, paused ? "sharing_paused" : "sharing_resumed");
    return user;
  }

  addTelemetry(userId: string, batch: TelemetryBatch): {
    snapshot?: DeviceSnapshot;
    location?: DeviceLocation;
    dailyReport?: DailyUsageReport;
    appUsageCount: number;
    eventCount: number;
  } {
    let snapshot: DeviceSnapshot | undefined;
    if (batch.deviceSnapshot) {
      snapshot = { ...batch.deviceSnapshot, id: randomUUID(), userId };
      const list = this.snapshots.get(userId) ?? [];
      list.push(snapshot);
      this.snapshots.set(userId, list.slice(-500));
    }

    let location: DeviceLocation | undefined;
    if (batch.locationSnapshot) {
      location = { ...batch.locationSnapshot, id: randomUUID(), userId };
      const list = this.locations.get(userId) ?? [];
      list.push(location);
      this.locations.set(userId, list.slice(-500));
    }

    let dailyReport: DailyUsageReport | undefined;
    if (batch.dailyReport) {
      dailyReport = { ...batch.dailyReport, id: randomUUID(), userId };
      this.dailyReports.set(this.reportKey(userId, dailyReport.date), dailyReport);
    }

    let appUsageCount = 0;
    if (batch.appUsageSessions?.length) {
      const list = this.appUsage.get(userId) ?? [];
      for (const session of batch.appUsageSessions) {
        const existingIndex = session.clientSessionId
          ? list.findIndex((item) => item.clientSessionId === session.clientSessionId)
          : -1;
        if (existingIndex >= 0) {
          const existing = list[existingIndex];
          list[existingIndex] = {
            ...existing,
            ...session,
            id: existing.id,
            userId,
            appName: session.appName ?? existing.appName,
            startedAt: existing.startedAt,
            endedAt: new Date(session.endedAt).getTime() > new Date(existing.endedAt).getTime()
              ? session.endedAt
              : existing.endedAt,
            durationMs: Math.max(existing.durationMs, session.durationMs),
            openCount: Math.max(existing.openCount ?? 0, session.openCount ?? 0)
          };
        } else {
          list.push({ ...session, id: randomUUID(), userId });
        }
        appUsageCount += 1;
      }
      this.appUsage.set(userId, list.slice(-5000));
    }

    let eventCount = 0;
    if (batch.events?.length) {
      const list = this.events.get(userId) ?? [];
      for (const event of batch.events) {
        const key = event.clientEventId ? `${userId}:${event.clientEventId}` : `${userId}:${event.type}:${event.occurredAt}`;
        if (this.eventKeys.has(key)) continue;
        this.eventKeys.add(key);
        list.push({ ...event, id: randomUUID(), userId });
        eventCount += 1;
      }
      list.sort((a, b) => new Date(b.occurredAt).getTime() - new Date(a.occurredAt).getTime());
      this.events.set(userId, list.slice(0, 5000));
    }

    return { snapshot, location, dailyReport, appUsageCount, eventCount };
  }

  latestSnapshot(userId: string): DeviceSnapshot | undefined {
    const list = this.snapshots.get(userId) ?? [];
    return list[list.length - 1];
  }

  latestLocation(userId: string): DeviceLocation | undefined {
    const list = this.locations.get(userId) ?? [];
    return list[list.length - 1];
  }

  reportForDate(userId: string, date: string): DailyUsageReport | undefined {
    return this.dailyReports.get(this.reportKey(userId, date));
  }

  appUsageForDate(userId: string, date: string): AppUsageSession[] {
    return (this.appUsage.get(userId) ?? [])
      .filter((session) => datePart(session.startedAt) === date)
      .sort((a, b) => b.durationMs - a.durationMs);
  }

  eventsForUser(userId: string, limit = 50): OperationEvent[] {
    return (this.events.get(userId) ?? []).slice(0, Math.min(limit, 200));
  }

  deleteUserTelemetry(userId: string): void {
    this.snapshots.delete(userId);
    this.locations.delete(userId);
    this.appUsage.delete(userId);
    this.events.delete(userId);
    for (const key of [...this.dailyReports.keys()]) {
      if (key.startsWith(`${userId}:`)) {
        this.dailyReports.delete(key);
      }
    }
    for (const key of [...this.eventKeys]) {
      if (key.startsWith(`${userId}:`)) {
        this.eventKeys.delete(key);
      }
    }
    this.addConsent(userId, "data_deleted");
  }

  consentLogForUser(userId: string): ConsentLog[] {
    return this.consentLogs.filter((log) => log.userId === userId);
  }

  private addConsent(userId: string, action: ConsentLog["action"], metadata?: Record<string, unknown>): void {
    this.consentLogs.push({ id: randomUUID(), userId, action, createdAt: now(), metadata });
  }

  private reportKey(userId: string, date: string): string {
    return `${userId}:${date}`;
  }
}
