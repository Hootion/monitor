import { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import request from "supertest";
import { AppModule } from "../src/app.module";

const auth = (token: string) => ({ Authorization: `Bearer ${token}` });
const today = () => new Date().toISOString().slice(0, 10);

describe("Mutual Watch API", () => {
  let app: INestApplication;
  // Nest returns the underlying HTTP adapter instance here; supertest accepts it directly.
  // Keeping this broad avoids coupling tests to Express' concrete server type.
  let server: any;

  beforeEach(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    await app.init();
    server = app.getHttpServer();
  });

  afterEach(async () => {
    await app.close();
  });

  async function register(phone: string, displayName: string) {
    const response = await request(server)
      .post("/auth/register")
      .send({ phone, displayName, password: "secret123" })
      .expect(201);
    return response.body as { accessToken: string; refreshToken: string; user: { id: string; displayName: string } };
  }

  async function pair(aToken: string, bToken: string) {
    const invite = await request(server).post("/pairing/invite").set(auth(aToken)).send().expect(201);
    return request(server)
      .post("/pairing/accept")
      .set(auth(bToken))
      .send({ code: invite.body.invite.code })
      .expect(201);
  }

  it("registers, logs in, refreshes, and returns the current user", async () => {
    const alice = await register("10000000001", "Alice");
    await request(server).get("/auth/me").set(auth(alice.accessToken)).expect(200).expect(({ body }) => {
      expect(body.user.displayName).toBe("Alice");
    });

    await request(server)
      .post("/auth/login")
      .send({ phone: "10000000001", password: "secret123" })
      .expect(201)
      .expect(({ body }) => expect(body.accessToken).toBeTruthy());

    await request(server)
      .post("/auth/refresh")
      .send({ refreshToken: alice.refreshToken })
      .expect(201)
      .expect(({ body }) => expect(body.refreshToken).toBeTruthy());
  });

  it("creates a one-to-one pairing and blocks a second pairing", async () => {
    const alice = await register("10000000002", "Alice");
    const bob = await register("10000000003", "Bob");
    const chris = await register("10000000004", "Chris");
    await pair(alice.accessToken, bob.accessToken);

    await request(server).get("/pairing/current").set(auth(alice.accessToken)).expect(200).expect(({ body }) => {
      expect(body.partner.displayName).toBe("Bob");
    });

    await request(server).post("/pairing/invite").set(auth(alice.accessToken)).send().expect(409);
    const invite = await request(server).post("/pairing/invite").set(auth(chris.accessToken)).send().expect(201);
    await request(server)
      .post("/pairing/accept")
      .set(auth(bob.accessToken))
      .send({ code: invite.body.invite.code })
      .expect(409);
  });

  it("stores telemetry and exposes it only to the paired partner", async () => {
    const reportDate = today();
    const alice = await register("10000000005", "Alice");
    const bob = await register("10000000006", "Bob");
    await request(server).get("/partner/overview").set(auth(bob.accessToken)).expect(403);
    await pair(alice.accessToken, bob.accessToken);

    await request(server)
      .post("/telemetry/batch")
      .set(auth(alice.accessToken))
      .send({
        deviceSnapshot: {
          platform: "android",
          capturedAt: "2026-06-22T02:00:00.000Z",
          batteryPercent: 82,
          model: "Pixel Test"
        },
        dailyReport: {
          platform: "android",
          date: reportDate,
          screenTimeMs: 3600000,
          pickupCount: 9,
          firstUseAt: `${reportDate}T00:12:00.000Z`,
          longestContinuousMs: 900000
        },
        appUsageSessions: [
          {
            platform: "android",
            packageName: "com.example.chat",
            appName: "Chat",
            startedAt: `${reportDate}T00:12:00.000Z`,
            endedAt: `${reportDate}T00:22:00.000Z`,
            durationMs: 600000,
            openCount: 1
          }
        ],
        events: [
          {
            platform: "android",
            clientEventId: "evt-1",
            type: "app_opened",
            occurredAt: `${reportDate}T00:12:00.000Z`,
            details: { packageName: "com.example.chat" }
          }
        ]
      })
      .expect(201)
      .expect(({ body }) => {
        expect(body.appUsageCount).toBe(1);
        expect(body.eventCount).toBe(1);
      });

    await request(server).get("/partner/overview").set(auth(bob.accessToken)).expect(200).expect(({ body }) => {
      expect(body.partner.displayName).toBe("Alice");
      expect(body.latestSnapshot.batteryPercent).toBe(82);
      expect(body.dailyReport.screenTimeMs).toBe(3600000);
    });
    await request(server).get(`/partner/app-usage?date=${reportDate}`).set(auth(bob.accessToken)).expect(200).expect(({ body }) => {
      expect(body.sessions).toHaveLength(1);
    });
    await request(server).get("/partner/events").set(auth(bob.accessToken)).expect(200).expect(({ body }) => {
      expect(body.events[0].type).toBe("app_opened");
    });
  });

  it("honors pause sharing and delete data controls", async () => {
    const reportDate = today();
    const alice = await register("10000000007", "Alice");
    const bob = await register("10000000008", "Bob");
    await pair(alice.accessToken, bob.accessToken);

    await request(server)
      .post("/telemetry/batch")
      .set(auth(alice.accessToken))
      .send({
        dailyReport: {
          platform: "android",
          date: reportDate,
          screenTimeMs: 120000,
          pickupCount: 2,
          longestContinuousMs: 60000
        }
      })
      .expect(201);

    await request(server).post("/sharing/pause").set(auth(alice.accessToken)).send({ paused: true }).expect(201);
    await request(server).get("/partner/overview").set(auth(bob.accessToken)).expect(403);

    await request(server).post("/sharing/pause").set(auth(alice.accessToken)).send({ paused: false }).expect(201);
    await request(server).post("/account/delete-data").set(auth(alice.accessToken)).send().expect(201);
    await request(server).get(`/partner/daily-report?date=${reportDate}`).set(auth(bob.accessToken)).expect(404);
  });
});
