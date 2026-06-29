import postgres from "postgres";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-release-token",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const databaseUrl = Deno.env.get("SUPABASE_DB_URL");
if (!databaseUrl) {
  throw new Error("Missing SUPABASE_DB_URL");
}

const sql = postgres(databaseUrl, {
  max: 2,
  idle_timeout: 20,
  prepare: false,
});

type ReleaseRow = {
  version_code: number;
  version_name: string;
  apk_url: string;
  release_notes: string | null;
  required: boolean;
  published_at?: Date | string | null;
};

type ReleaseInput = {
  platform: "android" | "ios";
  versionCode: number;
  versionName: string;
  apkUrl: string;
  releaseNotes: string;
  required: boolean;
  publishedAt: string;
  apkFile?: File;
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function textValue(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function releaseToken(request: Request): string {
  const authorization = request.headers.get("authorization") ?? "";
  if (authorization.toLowerCase().startsWith("bearer ")) {
    return authorization.slice("bearer ".length).trim();
  }
  return request.headers.get("x-release-token")?.trim() ?? "";
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function requireReleaseAdmin(request: Request): Promise<Response | null> {
  const token = releaseToken(request);
  const expected = Deno.env.get("APP_RELEASE_ADMIN_TOKEN")?.trim() ?? "";
  if (!token) {
    return jsonResponse({ message: "Unauthorized" }, 401);
  }

  if (expected && token === expected) {
    return null;
  }

  try {
    const tokenHash = await sha256Hex(token);
    const rows = await sql<{ id: string }[]>`
      select id
      from mutual_watch.app_release_admin_tokens
      where token_hash = ${tokenHash}
        and revoked_at is null
      limit 1
    `;
    const tokenRow = rows[0];
    if (tokenRow) {
      await sql`
        update mutual_watch.app_release_admin_tokens
        set last_used_at = now()
        where id = ${tokenRow.id}
      `;
      return null;
    }
  } catch (error) {
    console.error("Release token check failed", error);
  }
  return jsonResponse({ message: "Unauthorized" }, 401);
}

function releaseJson(release: ReleaseRow): Record<string, unknown> {
  return {
    updateAvailable: true,
    versionCode: release.version_code,
    versionName: release.version_name,
    apkUrl: release.apk_url,
    releaseNotes: release.release_notes ?? "",
    required: release.required,
    publishedAt: release.published_at ? new Date(release.published_at).toISOString() : null,
  };
}

async function publishRelease(request: Request): Promise<Response> {
  const unauthorized = await requireReleaseAdmin(request);
  if (unauthorized) return unauthorized;

  const input = await releaseInput(request);
  const release = await saveRelease(input);
  return jsonResponse({ published: true, release: releaseJson(release) }, 201);
}

async function releaseInput(request: Request): Promise<ReleaseInput> {
  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  if (contentType.includes("multipart/form-data")) {
    const form = await request.formData();
    const platform = parsePlatform(textValue(form.get("platform")) || "android");
    const versionCode = Number(form.get("versionCode"));
    const versionName = textValue(form.get("versionName"));
    let apkUrl = textValue(form.get("apkUrl"));
    const apkFileValue = form.get("apk");
    const apkFile = apkFileValue instanceof File ? apkFileValue : undefined;
    if (!apkUrl && apkFile) {
      apkUrl = await uploadReleaseApk({
        platform,
        versionCode,
        versionName,
        apkFile,
      });
    }
    return normalizeReleaseInput({
      platform,
      versionCode,
      versionName,
      apkUrl,
      releaseNotes: textValue(form.get("releaseNotes")),
      required: textValue(form.get("required")).toLowerCase() === "true",
      publishedAt: textValue(form.get("publishedAt")) || new Date().toISOString(),
      apkFile,
    });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch (_) {
    throw new HttpError("Invalid JSON body", 400);
  }

  return normalizeReleaseInput({
    platform: parsePlatform(textValue(body.platform) || "android"),
    versionCode: Number(body.versionCode),
    versionName: textValue(body.versionName),
    apkUrl: textValue(body.apkUrl),
    releaseNotes: textValue(body.releaseNotes),
    required: body.required === true,
    publishedAt: textValue(body.publishedAt) || new Date().toISOString(),
  });
}

function parsePlatform(value: string): "android" | "ios" {
  const platform = value.toLowerCase();
  if (platform !== "android" && platform !== "ios") {
    throw new HttpError("Unsupported platform", 400);
  }
  return platform;
}

function normalizeReleaseInput(input: ReleaseInput): ReleaseInput {
  if (!Number.isInteger(input.versionCode) || input.versionCode <= 0) {
    throw new HttpError("versionCode must be a positive integer", 400);
  }
  if (!input.versionName) {
    throw new HttpError("versionName is required", 400);
  }
  if (!input.apkUrl.startsWith("https://")) {
    throw new HttpError("apkUrl must be an HTTPS URL", 400);
  }
  if (Number.isNaN(Date.parse(input.publishedAt))) {
    throw new HttpError("publishedAt must be a valid date", 400);
  }
  return input;
}

async function saveRelease(input: ReleaseInput): Promise<ReleaseRow> {
  const [release] = await sql<ReleaseRow[]>`
    insert into mutual_watch.app_releases (
      platform, version_code, version_name, apk_url, release_notes, required, published_at
    )
    values (
      ${input.platform}, ${input.versionCode}, ${input.versionName}, ${input.apkUrl},
      ${input.releaseNotes}, ${input.required}, ${input.publishedAt}
    )
    on conflict (platform, version_code)
    do update set
      version_name = excluded.version_name,
      apk_url = excluded.apk_url,
      release_notes = excluded.release_notes,
      required = excluded.required,
      published_at = excluded.published_at
    returning version_code, version_name, apk_url, release_notes, required, published_at
  `;
  return release;
}

async function uploadReleaseApk(input: {
  platform: "android" | "ios";
  versionCode: number;
  versionName: string;
  apkFile: File;
}): Promise<string> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const secretKey = serviceKey();
  if (!supabaseUrl || !secretKey) {
    throw new HttpError("Storage publishing is not configured", 503);
  }

  const bucket = Deno.env.get("APP_RELEASE_BUCKET")?.trim() || "app-releases";
  const extension = input.platform === "ios" ? "ipa" : "apk";
  const safeVersion = input.versionName.replace(/[^A-Za-z0-9._-]/g, "-");
  const objectPath = `${input.platform}/mutual-watch-${safeVersion}-${input.versionCode}.${extension}`;
  const uploadUrl = `${supabaseUrl}/storage/v1/object/${bucket}/${objectPath}`;
  const headers: Record<string, string> = {
    apikey: secretKey,
    "content-type": input.apkFile.type || "application/vnd.android.package-archive",
    "x-upsert": "true",
  };
  if (!secretKey.startsWith("sb_secret_")) {
    headers.authorization = `Bearer ${secretKey}`;
  }

  const uploadResponse = await fetch(uploadUrl, {
    method: "POST",
    headers,
    body: input.apkFile,
  });
  if (!uploadResponse.ok) {
    const message = await uploadResponse.text();
    throw new HttpError(`APK upload failed: ${message || uploadResponse.statusText}`, 502);
  }

  const publicPath = objectPath.split("/").map(encodeURIComponent).join("/");
  return `${supabaseUrl}/storage/v1/object/public/${bucket}/${publicPath}`;
}

function serviceKey(): string {
  const secretKeysJson = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (secretKeysJson) {
    try {
      const keys = JSON.parse(secretKeysJson) as Record<string, string>;
      const key = keys.default?.trim();
      if (key) return key;
    } catch (_) {
      // Fall back to the legacy service role key below.
    }
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
}

class HttpError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method === "POST") {
    try {
      return await publishRelease(request);
    } catch (error) {
      if (error instanceof HttpError) {
        return jsonResponse({ message: error.message }, error.status);
      }
      console.error(error);
      return jsonResponse({ message: "Release publish failed" }, 500);
    }
  }
  if (request.method !== "GET") {
    return jsonResponse({ message: "Method not allowed" }, 405);
  }

  try {
    const url = new URL(request.url);
    const platform = (url.searchParams.get("platform") ?? "android").toLowerCase();
    if (platform !== "android" && platform !== "ios") {
      return jsonResponse({ message: "Unsupported platform" }, 400);
    }

    const parsedVersionCode = Number.parseInt(
      url.searchParams.get("currentVersionCode") ?? "0",
      10,
    );
    const currentVersionCode = Number.isFinite(parsedVersionCode)
      ? parsedVersionCode
      : 0;

    const rows = await sql<ReleaseRow[]>`
      select version_code, version_name, apk_url, release_notes, required, published_at
      from mutual_watch.app_releases
      where platform = ${platform}
        and published_at is not null
        and published_at <= now()
      order by version_code desc
      limit 1
    `;
    const release = rows[0];

    if (
      !release ||
      release.version_code <= currentVersionCode ||
      release.apk_url.trim().length === 0
    ) {
      return jsonResponse({ updateAvailable: false });
    }

    return jsonResponse(releaseJson(release));
  } catch (error) {
    console.error(error);
    return jsonResponse({ message: "Update check failed" }, 500);
  }
});
