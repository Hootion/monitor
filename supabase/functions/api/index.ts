import postgres from "npm:postgres@3.4.5";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-client-info, apikey",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS"
};

const databaseUrl = Deno.env.get("SUPABASE_DB_URL");
if (!databaseUrl) {
  throw new Error("SUPABASE_DB_URL is not configured.");
}

const sql = postgres(databaseUrl, {
  max: 3,
  idle_timeout: 20,
  connect_timeout: 10,
  prepare: false
});

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const ownAndroidPackageName = "com.mutualwatch.mutual_watch";
const maxAppUsageSessionMs = 4 * 60 * 60 * 1000;
const maxDailyUsageMs = 24 * 60 * 60 * 1000;
const maxAvatarBytes = 3 * 1024 * 1024;
const allowedAvatarTypes = new Set(["image/jpeg", "image/png", "image/webp"]);
const allowedGenders = new Set(["male", "female", "other", "unspecified"]);

class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string
  ) {
    super(message);
  }
}

type Db = any;
type DbUser = Record<string, unknown>;
type DbPairing = Record<string, unknown>;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    return await handleRequest(request);
  } catch (error) {
    if (error instanceof HttpError) {
      return json({ message: error.message }, error.status);
    }
    console.error(error);
    return json({ message: "Internal server error." }, 500);
  }
});

async function handleRequest(request: Request): Promise<Response> {
  const route = routePath(request);
  const method = request.method.toUpperCase();

  if (method === "GET" && route === "/health") {
    return json({ ok: true, service: "mutual-watch-api" });
  }
  if (method === "POST" && route === "/auth/register") {
    return register(await readJson(request));
  }
  if (method === "POST" && route === "/auth/login") {
    return login(await readJson(request));
  }
  if (method === "POST" && route === "/auth/refresh") {
    return refresh(await readJson(request));
  }

  const user = await authenticate(request);

  if (method === "GET" && route === "/auth/me") {
    return json({ user: publicUser(user) });
  }
  if (method === "POST" && route === "/pairing/invite") {
    return createInvite(String(user.id));
  }
  if (method === "POST" && route === "/pairing/accept") {
    return acceptInvite(String(user.id), await readJson(request));
  }
  if (method === "GET" && route === "/pairing/current") {
    return currentPairing(String(user.id));
  }
  if (method === "DELETE" && route === "/pairing/current") {
    return deletePairing(String(user.id));
  }
  if (method === "POST" && route === "/telemetry/batch") {
    return ingestTelemetry(user, await readJson(request));
  }
  if (method === "GET" && route === "/partner/overview") {
    return partnerOverview(String(user.id));
  }
  if (method === "GET" && route === "/partner/app-usage") {
    const date = new URL(request.url).searchParams.get("date") ?? today();
    return partnerAppUsage(String(user.id), date);
  }
  if (method === "GET" && route === "/partner/daily-report") {
    const date = new URL(request.url).searchParams.get("date") ?? today();
    return partnerDailyReport(String(user.id), date);
  }
  if (method === "GET" && route === "/partner/events") {
    const rawLimit = new URL(request.url).searchParams.get("limit");
    return partnerEvents(String(user.id), rawLimit ? Number(rawLimit) : undefined);
  }
  if (method === "POST" && route === "/sharing/pause") {
    return setSharingPaused(String(user.id), await readJson(request));
  }
  if (method === "POST" && route === "/account/profile") {
    return updateProfile(user, request);
  }
  if (method === "POST" && route === "/account/delete-data") {
    return deleteUserTelemetry(String(user.id));
  }
  if (method === "GET" && route === "/account/consent-log") {
    return consentLog(String(user.id));
  }

  throw new HttpError(404, "Route not found.");
}

async function register(body: Record<string, unknown>): Promise<Response> {
  const displayName = stringValue(body.displayName).trim();
  const phone = stringValue(body.phone).trim();
  const password = stringValue(body.password);
  if (!displayName || displayName.length > 40) {
    throw new HttpError(400, "Display name is required and must be at most 40 characters.");
  }
  if (!phone || phone.length > 32) {
    throw new HttpError(400, "Phone is required.");
  }
  if (password.length < 6) {
    throw new HttpError(400, "Password must be at least 6 characters.");
  }

  const existing = await findUserByPhone(phone);
  if (existing) {
    throw new HttpError(400, "Phone is already registered.");
  }

  const passwordRecord = await hashPassword(password);
  let user: DbUser;
  try {
    [user] = await sql`
      insert into mutual_watch.users (display_name, phone, password_hash, password_salt)
      values (${displayName}, ${phone}, ${passwordRecord.hash}, ${passwordRecord.salt})
      returning *
    `;
  } catch (error) {
    if (String(error).includes("users_phone_key")) {
      throw new HttpError(400, "Phone is already registered.");
    }
    throw error;
  }
  return json(await issueTokens(user), 201);
}

async function login(body: Record<string, unknown>): Promise<Response> {
  const phone = stringValue(body.phone).trim();
  const user = phone ? await findUserByPhone(phone) : undefined;
  if (!user || !(await verifyPassword(stringValue(body.password), String(user.password_salt), String(user.password_hash)))) {
    throw new HttpError(401, "Invalid phone or password.");
  }
  return json(await issueTokens(user), 201);
}

async function refresh(body: Record<string, unknown>): Promise<Response> {
  const refreshToken = stringValue(body.refreshToken);
  if (!refreshToken) {
    throw new HttpError(401, "Refresh token is required.");
  }

  const tokenHash = await hashToken(refreshToken);
  const user = await sql.begin(async (tx) => {
    const users = await tx`
      select u.*
      from mutual_watch.refresh_tokens rt
      join mutual_watch.users u on u.id = rt.user_id
      where rt.token_hash = ${tokenHash}
        and rt.expires_at > now()
      limit 1
    `;
    await tx`delete from mutual_watch.refresh_tokens where expires_at <= now()`;
    return users[0] as DbUser | undefined;
  });

  if (!user) {
    throw new HttpError(401, "Refresh token is invalid or expired.");
  }
  return json(await issueTokens(user), 201);
}

async function createInvite(userId: string): Promise<Response> {
  if (await getActivePairing(sql, userId)) {
    throw new HttpError(409, "Current user is already paired.");
  }

  await sql`
    delete from mutual_watch.pairing_invites
    where created_by_user_id = ${userId} and expires_at > now()
  `;

  let invite: Record<string, unknown> | undefined;
  for (let attempt = 0; attempt < 8 && !invite; attempt += 1) {
    const code = inviteCode();
    try {
      [invite] = await sql`
        insert into mutual_watch.pairing_invites (code, created_by_user_id, expires_at)
        values (${code}, ${userId}, now() + interval '10 minutes')
        returning *
      `;
    } catch (error) {
      if (!String(error).includes("pairing_invites_pkey")) throw error;
    }
  }
  if (!invite) {
    throw new HttpError(500, "Unable to create invite code.");
  }

  await addConsent(sql, userId, "invite_created", { code: invite.code });
  return json({ invite: pairingInvite(invite) }, 201);
}

async function acceptInvite(userId: string, body: Record<string, unknown>): Promise<Response> {
  const code = stringValue(body.code).trim();
  if (!code) {
    throw new HttpError(400, "Invite code is required.");
  }

  await sql.begin(async (tx) => {
    const invites = await tx`
      select *
      from mutual_watch.pairing_invites
      where code = ${code}
      for update
    `;
    const invite = invites[0];
    if (!invite) {
      throw new HttpError(404, "Invite code not found.");
    }
    if (new Date(String(invite.expires_at)).getTime() < Date.now()) {
      await tx`delete from mutual_watch.pairing_invites where code = ${code}`;
      throw new HttpError(400, "Invite code expired.");
    }

    const creatorId = String(invite.created_by_user_id);
    if (creatorId === userId) {
      throw new HttpError(400, "Cannot accept your own invite.");
    }

    for (const id of [creatorId, userId].sort()) {
      await tx`select id from mutual_watch.users where id = ${id} for update`;
    }

    if ((await getActivePairing(tx, creatorId)) || (await getActivePairing(tx, userId))) {
      throw new HttpError(409, "One of the users is already paired.");
    }

    const [pairing] = await tx`
      insert into mutual_watch.pairings (user_a_id, user_b_id)
      values (${creatorId}, ${userId})
      returning *
    `;
    await tx`delete from mutual_watch.pairing_invites where code = ${code}`;
    await addConsent(tx, creatorId, "pairing_accepted", { pairingId: pairing.id, partnerId: userId });
    await addConsent(tx, userId, "pairing_accepted", { pairingId: pairing.id, partnerId: creatorId });
  });

  return currentPairing(userId, 201);
}

async function currentPairing(userId: string, status = 200): Promise<Response> {
  const pairing = await getActivePairing(sql, userId);
  if (!pairing) {
    return json({ pairing: null, partner: null }, status);
  }
  const partnerId = String(pairing.user_a_id) === userId ? String(pairing.user_b_id) : String(pairing.user_a_id);
  const partner = await findUserById(partnerId);
  return json(
    {
      pairing: publicPairing(pairing),
      partner: partner ? publicUser(partner) : null
    },
    status
  );
}

async function deletePairing(userId: string): Promise<Response> {
  const pairing = await getActivePairing(sql, userId);
  if (!pairing) {
    return json({ deleted: false });
  }

  await sql.begin(async (tx) => {
    await tx`delete from mutual_watch.pairings where id = ${pairing.id}`;
    await addConsent(tx, String(pairing.user_a_id), "pairing_deleted", { pairingId: pairing.id });
    await addConsent(tx, String(pairing.user_b_id), "pairing_deleted", { pairingId: pairing.id });
  });
  return json({ deleted: true });
}

async function ingestTelemetry(user: DbUser, body: Record<string, unknown>): Promise<Response> {
  const userId = String(user.id);
  if (Boolean(user.sharing_paused)) {
    return json({ accepted: true, paused: true, appUsageCount: 0, eventCount: 0 }, 201);
  }

  const result = await sql.begin(async (tx) => {
    let snapshot: Record<string, unknown> | undefined;
    let location: Record<string, unknown> | undefined;
    let report: Record<string, unknown> | undefined;
    let appUsageCount = 0;
    let eventCount = 0;

    if (isObject(body.deviceSnapshot)) {
      const input = body.deviceSnapshot;
      [snapshot] = await tx`
        insert into mutual_watch.device_snapshots (
          user_id, platform, captured_at, wifi_bytes_today, mobile_bytes_today, network_speed_kbps,
          network_type, network_name, bluetooth_state, volume_percent, battery_percent, battery_charging,
          model, os_version, storage_used_bytes, storage_total_bytes, unsupported
        )
        values (
          ${userId}, ${stringValue(input.platform) || "android"}, ${timestampValue(input.capturedAt)},
          ${numberOrNull(input.wifiBytesToday)}, ${numberOrNull(input.mobileBytesToday)},
          ${numberOrNull(input.networkSpeedKbps)}, ${nullableString(input.networkType)},
          ${nullableString(input.networkName)}, ${nullableString(input.bluetoothState)},
          ${numberOrNull(input.volumePercent)}, ${numberOrNull(input.batteryPercent)},
          ${booleanOrNull(input.batteryCharging)}, ${nullableString(input.model)}, ${nullableString(input.osVersion)},
          ${numberOrNull(input.storageUsedBytes)}, ${numberOrNull(input.storageTotalBytes)},
          ${JSON.stringify(arrayOfStrings(input.unsupported))}::jsonb
        )
        returning *
      `;
    }

    if (isObject(body.locationSnapshot)) {
      const input = body.locationSnapshot;
      [location] = await tx`
        insert into mutual_watch.device_locations (
          user_id, platform, captured_at, status, latitude, longitude, accuracy_meters
        )
        values (
          ${userId}, ${stringValue(input.platform) || "android"}, ${timestampValue(input.capturedAt)},
          ${stringValue(input.status) || "unknown"}, ${numberOrNull(input.latitude)},
          ${numberOrNull(input.longitude)}, ${numberOrNull(input.accuracyMeters)}
        )
        returning *
      `;
    }

    if (isObject(body.dailyReport)) {
      const input = body.dailyReport;
      const reportDate = dateValue(input.date);
      const screenTimeMs = safeDailyUsageDurationMs(numberValue(input.screenTimeMs));
      const longestContinuousMs = Math.min(
        safeAppUsageDurationMs(numberValue(input.longestContinuousMs)),
        screenTimeMs
      );
      [report] = await tx`
        insert into mutual_watch.daily_usage_reports (
          user_id, report_date, platform, screen_time_ms, pickup_count, first_use_at,
          longest_continuous_ms, unsupported, updated_at
        )
        values (
          ${userId}, ${reportDate}, ${stringValue(input.platform) || "android"},
          ${screenTimeMs}, ${numberValue(input.pickupCount)},
          ${nullableTimestamp(input.firstUseAt)}, ${longestContinuousMs},
          ${JSON.stringify(arrayOfStrings(input.unsupported))}::jsonb, now()
        )
        on conflict (user_id, report_date)
        do update set
          platform = excluded.platform,
          screen_time_ms = excluded.screen_time_ms,
          pickup_count = excluded.pickup_count,
          first_use_at = excluded.first_use_at,
          longest_continuous_ms = excluded.longest_continuous_ms,
          unsupported = excluded.unsupported,
          updated_at = now()
        returning *
      `;
    }

    if (Array.isArray(body.appUsageSessions)) {
      for (const item of body.appUsageSessions) {
        if (!isObject(item)) continue;
        const session = normalizeAppUsageInput(item);
        if (!session) continue;
        await tx`
          insert into mutual_watch.app_usage_sessions (
            user_id, package_name, app_name, client_session_id, started_at, ended_at, duration_ms, open_count, platform
          )
          values (
            ${userId}, ${session.packageName}, ${session.appName},
            ${session.clientSessionId},
            ${session.startedAt}, ${session.endedAt}, ${session.durationMs},
            ${session.openCount}, ${session.platform}
          )
          on conflict (user_id, client_session_id) where client_session_id is not null
          do update set
            app_name = coalesce(excluded.app_name, app_usage_sessions.app_name),
            ended_at = greatest(app_usage_sessions.ended_at, excluded.ended_at),
            duration_ms = greatest(app_usage_sessions.duration_ms, excluded.duration_ms),
            open_count = greatest(coalesce(app_usage_sessions.open_count, 0), coalesce(excluded.open_count, 0)),
            platform = excluded.platform
        `;
        appUsageCount += 1;
      }
    }

    if (Array.isArray(body.events)) {
      for (const item of body.events) {
        if (!isObject(item)) continue;
        const inserted = await tx`
          insert into mutual_watch.operation_events (
            user_id, client_event_id, event_type, occurred_at, platform, details
          )
          values (
            ${userId}, ${nullableString(item.clientEventId)}, ${stringValue(item.type) || "app_opened"},
            ${timestampValue(item.occurredAt)}, ${stringValue(item.platform) || "android"},
            ${item.details == null ? null : JSON.stringify(item.details)}::jsonb
          )
          on conflict do nothing
          returning *
        `;
        eventCount += inserted.length;
      }
    }

    await cleanupTelemetry(tx, userId);
    return { snapshot, location, report, appUsageCount, eventCount };
  });

  return json(
    {
      accepted: true,
      snapshot: result.snapshot ? deviceSnapshot(result.snapshot) : undefined,
      location: result.location ? deviceLocation(result.location) : undefined,
      dailyReport: result.report ? dailyUsageReport(result.report) : undefined,
      appUsageCount: result.appUsageCount,
      eventCount: result.eventCount
    },
    201
  );
}

async function partnerOverview(userId: string): Promise<Response> {
  const partner = await visiblePartner(userId);
  const partnerId = String(partner.id);
  const [snapshot] = await sql`
    select * from mutual_watch.device_snapshots
    where user_id = ${partnerId}
    order by captured_at desc
    limit 1
  `;
  const [location] = await sql`
    select * from mutual_watch.device_locations
    where user_id = ${partnerId}
    order by captured_at desc
    limit 1
  `;
  const [report] = await sql`
    select * from mutual_watch.daily_usage_reports
    where user_id = ${partnerId} and report_date = ${today()}
    limit 1
  `;
  const events = await sql`
    select * from mutual_watch.operation_events
    where user_id = ${partnerId}
    order by occurred_at desc
    limit 10
  `;

  return json({
    partner: publicUser(partner),
    latestSnapshot: snapshot ? deviceSnapshot(snapshot) : undefined,
    latestLocation: location ? deviceLocation(location) : undefined,
    dailyReport: report ? dailyUsageReport(report) : undefined,
    latestEvents: events.map(operationEvent)
  });
}

async function partnerAppUsage(userId: string, date: string): Promise<Response> {
  const partner = await visiblePartner(userId);
  const partnerId = String(partner.id);
  const start = `${date}T00:00:00.000Z`;
  const end = new Date(new Date(start).getTime() + 24 * 60 * 60 * 1000).toISOString();
  const sessions = await sql`
    select * from mutual_watch.app_usage_sessions
    where user_id = ${partnerId}
      and started_at >= ${start}
      and started_at < ${end}
      and package_name <> ${ownAndroidPackageName}
      and duration_ms > 0
    order by duration_ms desc
  `;
  return json({ date, sessions: sessions.map(appUsageSession) });
}

async function partnerDailyReport(userId: string, date: string): Promise<Response> {
  const partner = await visiblePartner(userId);
  const partnerId = String(partner.id);
  const [report] = await sql`
    select * from mutual_watch.daily_usage_reports
    where user_id = ${partnerId} and report_date = ${date}
    limit 1
  `;
  if (!report) {
    throw new HttpError(404, "Daily report not found.");
  }
  return json({ report: dailyUsageReport(report) });
}

async function partnerEvents(userId: string, limit?: number): Promise<Response> {
  const partner = await visiblePartner(userId);
  const partnerId = String(partner.id);
  const cappedLimit = Math.max(1, Math.min(Number.isFinite(limit ?? NaN) ? Number(limit) : 50, 200));
  const events = await sql`
    select * from mutual_watch.operation_events
    where user_id = ${partnerId}
    order by occurred_at desc
    limit ${cappedLimit}
  `;
  return json({ events: events.map(operationEvent) });
}

async function setSharingPaused(userId: string, body: Record<string, unknown>): Promise<Response> {
  const paused = Boolean(body.paused);
  const [user] = await sql`
    update mutual_watch.users
    set sharing_paused = ${paused}, updated_at = now()
    where id = ${userId}
    returning *
  `;
  await addConsent(sql, userId, paused ? "sharing_paused" : "sharing_resumed");
  return json({ user: publicUser(user) }, 201);
}

async function updateProfile(user: DbUser, request: Request): Promise<Response> {
  const userId = String(user.id);
  const input = await profileInput(userId, request);
  const [updated] = await sql`
    update mutual_watch.users
    set display_name = ${input.displayName},
        mood_status = ${input.moodStatus},
        gender = ${input.gender},
        avatar_url = coalesce(${input.avatarUrl}, avatar_url),
        updated_at = now()
    where id = ${userId}
    returning *
  `;
  await addConsent(sql, userId, "profile_updated");
  return json({ user: publicUser(updated) }, 201);
}

async function profileInput(
  userId: string,
  request: Request
): Promise<{ displayName: string; moodStatus: string | null; gender: string; avatarUrl: string | null }> {
  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  if (contentType.includes("multipart/form-data")) {
    const form = await request.formData();
    const avatar = form.get("avatar");
    return normalizeProfileInput({
      displayName: textValue(form.get("displayName")),
      moodStatus: textValue(form.get("moodStatus")),
      gender: textValue(form.get("gender")),
      avatarUrl: avatar instanceof File ? await uploadAvatar(userId, avatar) : null
    });
  }

  const body = await readJson(request);
  return normalizeProfileInput({
    displayName: stringValue(body.displayName),
    moodStatus: stringValue(body.moodStatus),
    gender: stringValue(body.gender),
    avatarUrl: null
  });
}

function normalizeProfileInput(input: {
  displayName: string;
  moodStatus: string;
  gender: string;
  avatarUrl: string | null;
}): { displayName: string; moodStatus: string | null; gender: string; avatarUrl: string | null } {
  const displayName = input.displayName.trim();
  const moodStatus = input.moodStatus.trim();
  const gender = input.gender.trim() || "unspecified";

  if (!displayName || displayName.length > 40) {
    throw new HttpError(400, "Display name is required and must be at most 40 characters.");
  }
  if (moodStatus.length > 20) {
    throw new HttpError(400, "Mood status must be at most 20 characters.");
  }
  if (!allowedGenders.has(gender)) {
    throw new HttpError(400, "Gender is invalid.");
  }

  return {
    displayName,
    moodStatus: moodStatus || null,
    gender,
    avatarUrl: input.avatarUrl
  };
}

async function uploadAvatar(userId: string, avatar: File): Promise<string> {
  if (!allowedAvatarTypes.has(avatar.type)) {
    throw new HttpError(400, "Avatar must be a JPG, PNG, or WebP image.");
  }
  if (avatar.size <= 0 || avatar.size > maxAvatarBytes) {
    throw new HttpError(400, "Avatar must be 3MB or smaller.");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const secretKey = serviceKey();
  if (!supabaseUrl || !secretKey) {
    throw new HttpError(503, "Avatar storage is not configured.");
  }

  const bucket = Deno.env.get("PROFILE_AVATAR_BUCKET")?.trim() || "profile-avatars";
  const extension = avatarExtension(avatar.type);
  const random = crypto.getRandomValues(new Uint32Array(1))[0].toString(16);
  const objectPath = `${userId}/${Date.now()}-${random}.${extension}`;
  const uploadUrl = `${supabaseUrl}/storage/v1/object/${bucket}/${objectPath}`;
  const headers: Record<string, string> = {
    apikey: secretKey,
    "content-type": avatar.type,
    "cache-control": "3600",
    "x-upsert": "false"
  };
  if (!secretKey.startsWith("sb_secret_")) {
    headers.authorization = `Bearer ${secretKey}`;
  }

  const uploadResponse = await fetch(uploadUrl, {
    method: "POST",
    headers,
    body: avatar
  });
  if (!uploadResponse.ok) {
    const message = await uploadResponse.text();
    throw new HttpError(502, `Avatar upload failed: ${message || uploadResponse.statusText}`);
  }

  const publicPath = objectPath.split("/").map(encodeURIComponent).join("/");
  return `${supabaseUrl}/storage/v1/object/public/${bucket}/${publicPath}`;
}

function avatarExtension(contentType: string): "jpg" | "png" | "webp" {
  if (contentType === "image/png") return "png";
  if (contentType === "image/webp") return "webp";
  return "jpg";
}

async function deleteUserTelemetry(userId: string): Promise<Response> {
  await sql.begin(async (tx) => {
    await tx`delete from mutual_watch.device_snapshots where user_id = ${userId}`;
    await tx`delete from mutual_watch.device_locations where user_id = ${userId}`;
    await tx`delete from mutual_watch.app_usage_sessions where user_id = ${userId}`;
    await tx`delete from mutual_watch.daily_usage_reports where user_id = ${userId}`;
    await tx`delete from mutual_watch.operation_events where user_id = ${userId}`;
    await addConsent(tx, userId, "data_deleted");
  });
  return json({ deleted: true }, 201);
}

async function consentLog(userId: string): Promise<Response> {
  const logs = await sql`
    select * from mutual_watch.consent_logs
    where user_id = ${userId}
    order by created_at desc
  `;
  return json({ logs: logs.map(consentLogEntry) });
}

async function authenticate(request: Request): Promise<DbUser> {
  const authHeader = request.headers.get("authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice("Bearer ".length) : "";
  if (!token) {
    throw new HttpError(401, "Missing bearer token.");
  }
  const payload = await verifyAccessToken(token);
  const user = await findUserById(payload.sub);
  if (!user) {
    throw new HttpError(401, "User no longer exists.");
  }
  return user;
}

async function issueTokens(user: DbUser): Promise<Record<string, unknown>> {
  const refresh = await createRefreshToken();
  await sql`
    insert into mutual_watch.refresh_tokens (token_hash, user_id, expires_at)
    values (${refresh.hash}, ${user.id}, ${refresh.expiresAt})
  `;
  await sql`
    delete from mutual_watch.refresh_tokens
    where user_id = ${user.id}
      and expires_at <= now()
  `;
  return {
    user: publicUser(user),
    accessToken: await signAccessToken(String(user.id)),
    refreshToken: refresh.token
  };
}

async function visiblePartner(userId: string): Promise<DbUser> {
  const pairing = await getActivePairing(sql, userId);
  if (!pairing) {
    throw new HttpError(403, "No active pairing.");
  }
  const partnerId = String(pairing.user_a_id) === userId ? String(pairing.user_b_id) : String(pairing.user_a_id);
  const partner = await findUserById(partnerId);
  if (!partner) {
    throw new HttpError(404, "Partner not found.");
  }
  if (Boolean(partner.sharing_paused)) {
    throw new HttpError(403, "Partner has paused sharing.");
  }
  return partner;
}

async function findUserById(id: string): Promise<DbUser | undefined> {
  const rows = await sql`select * from mutual_watch.users where id = ${id} limit 1`;
  return rows[0] as DbUser | undefined;
}

async function findUserByPhone(phone: string): Promise<DbUser | undefined> {
  const rows = await sql`select * from mutual_watch.users where phone = ${phone} limit 1`;
  return rows[0] as DbUser | undefined;
}

async function getActivePairing(db: Db, userId: string): Promise<DbPairing | undefined> {
  const rows = await db`
    select *
    from mutual_watch.pairings
    where user_a_id = ${userId} or user_b_id = ${userId}
    order by created_at desc
    limit 1
  `;
  return rows[0] as DbPairing | undefined;
}

async function addConsent(db: Db, userId: string, action: string, metadata?: Record<string, unknown>) {
  await db`
    insert into mutual_watch.consent_logs (user_id, action, metadata)
    values (${userId}, ${action}, ${metadata ? JSON.stringify(metadata) : null}::jsonb)
  `;
}

async function cleanupTelemetry(db: Db, userId: string) {
  const detailDays = Math.max(1, Math.min(numberFromEnv("RETENTION_DETAIL_DAYS", 30), 365));
  const dailyDays = Math.max(1, Math.min(numberFromEnv("RETENTION_DAILY_DAYS", 180), 730));
  await db`delete from mutual_watch.device_snapshots where user_id = ${userId} and captured_at < now() - (${detailDays}::int * interval '1 day')`;
  await db`delete from mutual_watch.device_locations where user_id = ${userId} and captured_at < now() - (${detailDays}::int * interval '1 day')`;
  await db`delete from mutual_watch.app_usage_sessions where user_id = ${userId} and started_at < now() - (${detailDays}::int * interval '1 day')`;
  await db`delete from mutual_watch.operation_events where user_id = ${userId} and occurred_at < now() - (${detailDays}::int * interval '1 day')`;
  await db`delete from mutual_watch.daily_usage_reports where user_id = ${userId} and report_date < current_date - ${dailyDays}::int`;
}

async function hashPassword(password: string): Promise<{ hash: string; salt: string }> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  return {
    salt: hex(salt),
    hash: hex(await pbkdf2(password, salt))
  };
}

async function verifyPassword(password: string, saltHex: string, expectedHash: string): Promise<boolean> {
  const actual = hex(await pbkdf2(password, bytesFromHex(saltHex)));
  return constantEqual(actual, expectedHash);
}

async function pbkdf2(password: string, salt: Uint8Array): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt, iterations: 120000, hash: "SHA-256" },
    key,
    256
  );
  return new Uint8Array(bits);
}

async function signAccessToken(userId: string): Promise<string> {
  const iat = Math.floor(Date.now() / 1000);
  const exp = iat + numberFromEnv("ACCESS_TOKEN_TTL_SECONDS", 86400);
  const header = base64urlJson({ alg: "HS256", typ: "JWT" });
  const payload = base64urlJson({ sub: userId, typ: "access", iat, exp });
  const signature = base64urlBytes(await hmacBytes(`${header}.${payload}`));
  return `${header}.${payload}.${signature}`;
}

async function verifyAccessToken(token: string): Promise<{ sub: string; exp: number; typ: string }> {
  const [header, payload, signature] = token.split(".");
  if (!header || !payload || !signature) {
    throw new HttpError(401, "Invalid access token.");
  }
  const expected = base64urlBytes(await hmacBytes(`${header}.${payload}`));
  if (!constantEqual(signature, expected)) {
    throw new HttpError(401, "Invalid access token signature.");
  }
  const decoded = JSON.parse(decoder.decode(bytesFromBase64url(payload))) as { sub?: string; exp?: number; typ?: string };
  if (!decoded.sub || decoded.typ !== "access" || !decoded.exp || decoded.exp < Math.floor(Date.now() / 1000)) {
    throw new HttpError(401, "Access token expired.");
  }
  return { sub: decoded.sub, exp: decoded.exp, typ: decoded.typ };
}

async function createRefreshToken(): Promise<{ token: string; hash: string; expiresAt: string }> {
  const random = crypto.getRandomValues(new Uint8Array(48));
  const token = base64urlBytes(random);
  const expiresAt = new Date(Date.now() + numberFromEnv("REFRESH_TOKEN_TTL_DAYS", 180) * 24 * 60 * 60 * 1000).toISOString();
  return { token, hash: await hashToken(token), expiresAt };
}

async function hashToken(token: string): Promise<string> {
  return hex(await hmacBytes(token));
}

async function hmacBytes(value: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secretValue()), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign"
  ]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(value)));
}

function secretValue(): string {
  const explicit = Deno.env.get("MW_JWT_SECRET") ?? Deno.env.get("JWT_SECRET");
  if (explicit) return explicit;
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (serviceRole) return serviceRole;
  const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (secretKeys) {
    const parsed = JSON.parse(secretKeys) as Record<string, string>;
    if (parsed.default) return parsed.default;
  }
  throw new Error("No JWT secret is available.");
}

function serviceKey(): string {
  const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (secretKeys) {
    const parsed = JSON.parse(secretKeys) as Record<string, string>;
    if (parsed.default) return parsed.default;
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
}

function routePath(request: Request): string {
  const pathname = new URL(request.url).pathname.replace(/\/+$/, "") || "/";
  return pathname.replace(/^\/api(?=\/|$)/, "") || "/";
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  const text = await request.text();
  if (!text.trim()) return {};
  try {
    const parsed = JSON.parse(text);
    return isObject(parsed) ? parsed : {};
  } catch {
    throw new HttpError(400, "Request body must be valid JSON.");
  }
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" }
  });
}

function publicUser(row: DbUser): Record<string, unknown> {
  return {
    id: row.id,
    displayName: row.display_name,
    avatarUrl: row.avatar_url ?? undefined,
    moodStatus: row.mood_status ?? undefined,
    gender: row.gender ?? "unspecified",
    phone: row.phone ?? undefined,
    sharingPaused: Boolean(row.sharing_paused),
    createdAt: iso(row.created_at)
  };
}

function publicPairing(row: DbPairing): Record<string, unknown> {
  return {
    id: row.id,
    userAId: row.user_a_id,
    userBId: row.user_b_id,
    createdAt: iso(row.created_at)
  };
}

function pairingInvite(row: Record<string, unknown>): Record<string, unknown> {
  return {
    code: row.code,
    createdByUserId: row.created_by_user_id,
    expiresAt: iso(row.expires_at),
    createdAt: iso(row.created_at)
  };
}

function deviceSnapshot(row: Record<string, unknown>): Record<string, unknown> {
  return {
    id: row.id,
    userId: row.user_id,
    platform: row.platform,
    capturedAt: iso(row.captured_at),
    wifiBytesToday: row.wifi_bytes_today,
    mobileBytesToday: row.mobile_bytes_today,
    networkSpeedKbps: row.network_speed_kbps,
    networkType: row.network_type,
    networkName: row.network_name,
    bluetoothState: row.bluetooth_state,
    volumePercent: row.volume_percent,
    batteryPercent: row.battery_percent,
    batteryCharging: row.battery_charging,
    model: row.model,
    osVersion: row.os_version,
    storageUsedBytes: row.storage_used_bytes,
    storageTotalBytes: row.storage_total_bytes,
    unsupported: arrayOfStrings(row.unsupported)
  };
}

function deviceLocation(row: Record<string, unknown>): Record<string, unknown> {
  return {
    id: row.id,
    userId: row.user_id,
    platform: row.platform,
    capturedAt: iso(row.captured_at),
    status: row.status,
    latitude: row.latitude,
    longitude: row.longitude,
    accuracyMeters: row.accuracy_meters
  };
}

function dailyUsageReport(row: Record<string, unknown>): Record<string, unknown> {
  const screenTimeMs = safeDailyUsageDurationMs(numberValue(row.screen_time_ms));
  return {
    id: row.id,
    userId: row.user_id,
    date: dateOnly(row.report_date),
    platform: row.platform,
    screenTimeMs,
    pickupCount: row.pickup_count,
    firstUseAt: row.first_use_at == null ? null : iso(row.first_use_at),
    longestContinuousMs: Math.min(safeAppUsageDurationMs(numberValue(row.longest_continuous_ms)), screenTimeMs),
    unsupported: arrayOfStrings(row.unsupported)
  };
}

function appUsageSession(row: Record<string, unknown>): Record<string, unknown> {
  const durationMs = safeStoredAppUsageDurationMs(row);
  return {
    id: row.id,
    userId: row.user_id,
    packageName: row.package_name,
    appName: row.app_name,
    clientSessionId: row.client_session_id,
    startedAt: iso(row.started_at),
    endedAt: iso(row.ended_at),
    durationMs,
    openCount: row.open_count,
    platform: row.platform
  };
}

function operationEvent(row: Record<string, unknown>): Record<string, unknown> {
  return {
    id: row.id,
    userId: row.user_id,
    clientEventId: row.client_event_id,
    type: row.event_type,
    occurredAt: iso(row.occurred_at),
    platform: row.platform,
    details: row.details ?? undefined
  };
}

function consentLogEntry(row: Record<string, unknown>): Record<string, unknown> {
  return {
    id: row.id,
    userId: row.user_id,
    action: row.action,
    createdAt: iso(row.created_at),
    metadata: row.metadata ?? undefined
  };
}

function inviteCode(): string {
  const value = crypto.getRandomValues(new Uint32Array(1))[0] % 900000;
  return String(100000 + value);
}

function timestampValue(value: unknown): string {
  const text = stringValue(value);
  return text || new Date().toISOString();
}

function normalizeAppUsageInput(item: Record<string, unknown>) {
  const packageName = stringValue(item.packageName).trim() || "unknown";
  if (packageName.toLowerCase() === ownAndroidPackageName) {
    return null;
  }

  const startedAt = dateFromUnknown(item.startedAt);
  const endedAt = dateFromUnknown(item.endedAt);
  if (!startedAt || !endedAt || endedAt.getTime() <= startedAt.getTime()) {
    return null;
  }

  const now = Date.now();
  const safeEnd = new Date(Math.min(endedAt.getTime(), now + 5 * 60 * 1000));
  const clockDuration = safeEnd.getTime() - startedAt.getTime();
  const rawDuration = numberValue(item.durationMs);
  const durationMs = Math.min(
    safeAppUsageDurationMs(rawDuration > 0 ? rawDuration : clockDuration),
    safeAppUsageDurationMs(clockDuration)
  );
  if (durationMs <= 0) {
    return null;
  }

  return {
    packageName,
    appName: nullableString(item.appName),
    clientSessionId: nullableString(item.clientSessionId),
    startedAt: startedAt.toISOString(),
    endedAt: new Date(startedAt.getTime() + durationMs).toISOString(),
    durationMs,
    openCount: numberOrNull(item.openCount),
    platform: stringValue(item.platform) || "android"
  };
}

function safeStoredAppUsageDurationMs(row: Record<string, unknown>): number {
  const startedAt = dateFromUnknown(row.started_at);
  const endedAt = dateFromUnknown(row.ended_at);
  const rawDuration = safeAppUsageDurationMs(numberValue(row.duration_ms));
  if (!startedAt || !endedAt || endedAt.getTime() <= startedAt.getTime()) {
    return rawDuration;
  }
  const clockDuration = endedAt.getTime() - startedAt.getTime();
  return Math.min(rawDuration, safeAppUsageDurationMs(clockDuration));
}

function safeDailyUsageDurationMs(value: number): number {
  return Math.max(0, Math.min(value, maxDailyUsageMs));
}

function safeAppUsageDurationMs(value: number): number {
  return Math.max(0, Math.min(value, maxAppUsageSessionMs));
}

function dateFromUnknown(value: unknown): Date | undefined {
  if (value instanceof Date) return value;
  const text = stringValue(value);
  if (!text) return undefined;
  const date = new Date(text);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

function nullableTimestamp(value: unknown): string | null {
  const text = stringValue(value);
  return text || null;
}

function dateValue(value: unknown): string {
  const text = stringValue(value);
  return /^\d{4}-\d{2}-\d{2}$/.test(text) ? text : today();
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

function iso(value: unknown): string | undefined {
  if (value == null) return undefined;
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

function dateOnly(value: unknown): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function textValue(value: FormDataEntryValue | null): string {
  return typeof value === "string" ? value.trim() : "";
}

function nullableString(value: unknown): string | null {
  const text = stringValue(value);
  return text || null;
}

function numberValue(value: unknown): number {
  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) ? number : 0;
}

function numberOrNull(value: unknown): number | null {
  if (value == null) return null;
  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) ? number : null;
}

function booleanOrNull(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

function numberFromEnv(name: string, fallback: number): number {
  const value = Number(Deno.env.get(name));
  return Number.isFinite(value) ? value : fallback;
}

function arrayOfStrings(value: unknown): string[] {
  return Array.isArray(value) ? value.map((item) => String(item)) : [];
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function base64urlJson(value: unknown): string {
  return base64urlBytes(encoder.encode(JSON.stringify(value)));
}

function base64urlBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function bytesFromBase64url(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
}

function hex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function bytesFromHex(value: string): Uint8Array {
  const bytes = new Uint8Array(value.length / 2);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(value.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

function constantEqual(left: string, right: string): boolean {
  const leftBytes = encoder.encode(left);
  const rightBytes = encoder.encode(right);
  let diff = leftBytes.length ^ rightBytes.length;
  const length = Math.max(leftBytes.length, rightBytes.length);
  for (let index = 0; index < length; index += 1) {
    diff |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }
  return diff === 0;
}
