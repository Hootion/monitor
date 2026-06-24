export type Platform = "android" | "ios";

export type OperationEventType =
  | "screen_on"
  | "screen_off"
  | "boot_completed"
  | "shutdown_detected"
  | "network_connected"
  | "network_disconnected"
  | "app_opened"
  | "charge_started"
  | "charge_ended"
  | "call_started"
  | "call_ended";

export interface PublicUser {
  id: string;
  displayName: string;
  phone?: string;
  sharingPaused: boolean;
  createdAt: string;
}

export interface User extends PublicUser {
  passwordHash: string;
  passwordSalt: string;
  updatedAt: string;
}

export interface Pairing {
  id: string;
  userAId: string;
  userBId: string;
  createdAt: string;
}

export interface PairingInvite {
  code: string;
  createdByUserId: string;
  expiresAt: string;
  createdAt: string;
}

export interface ConsentLog {
  id: string;
  userId: string;
  action: "invite_created" | "pairing_accepted" | "sharing_paused" | "sharing_resumed" | "pairing_deleted" | "data_deleted";
  createdAt: string;
  metadata?: Record<string, unknown>;
}

export interface DeviceSnapshot {
  id?: string;
  userId?: string;
  platform: Platform;
  capturedAt: string;
  wifiBytesToday?: number | null;
  mobileBytesToday?: number | null;
  networkSpeedKbps?: number | null;
  networkType?: string | null;
  bluetoothState?: "on" | "off" | "unauthorized" | "unsupported" | "unknown" | null;
  volumePercent?: number | null;
  batteryPercent?: number | null;
  batteryCharging?: boolean | null;
  model?: string | null;
  osVersion?: string | null;
  storageUsedBytes?: number | null;
  storageTotalBytes?: number | null;
  unsupported?: string[];
}

export interface AppUsageSession {
  id?: string;
  userId?: string;
  packageName: string;
  appName?: string | null;
  startedAt: string;
  endedAt: string;
  durationMs: number;
  openCount?: number;
  platform: Platform;
}

export interface DailyUsageReport {
  id?: string;
  userId?: string;
  date: string;
  platform: Platform;
  screenTimeMs: number;
  pickupCount: number;
  firstUseAt?: string | null;
  longestContinuousMs: number;
  unsupported?: string[];
}

export interface OperationEvent {
  id?: string;
  userId?: string;
  clientEventId?: string;
  type: OperationEventType;
  occurredAt: string;
  platform: Platform;
  details?: Record<string, unknown>;
}

export interface TelemetryBatch {
  deviceSnapshot?: DeviceSnapshot;
  appUsageSessions?: AppUsageSession[];
  dailyReport?: DailyUsageReport;
  events?: OperationEvent[];
}

export interface PartnerOverview {
  partner: PublicUser;
  latestSnapshot?: DeviceSnapshot;
  dailyReport?: DailyUsageReport;
  latestEvents: OperationEvent[];
}

