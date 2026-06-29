import { Injectable, UnauthorizedException } from "@nestjs/common";
import { createHmac, randomBytes } from "crypto";

interface JwtPayload {
  sub: string;
  typ: "access";
  iat: number;
  exp: number;
}

const base64url = (input: Buffer | string) =>
  Buffer.from(input).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

const decodeBase64url = (input: string) => {
  const padded = input.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(input.length / 4) * 4, "=");
  return Buffer.from(padded, "base64").toString("utf8");
};

@Injectable()
export class TokenService {
  private readonly secret = process.env.JWT_SECRET ?? "dev-only-change-me";
  private readonly accessTtlSeconds = Number(process.env.ACCESS_TOKEN_TTL_SECONDS ?? 86400);
  private readonly refreshTtlDays = Number(process.env.REFRESH_TOKEN_TTL_DAYS ?? 180);

  signAccessToken(userId: string): string {
    const iat = Math.floor(Date.now() / 1000);
    const payload: JwtPayload = {
      sub: userId,
      typ: "access",
      iat,
      exp: iat + this.accessTtlSeconds
    };
    const header = base64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
    const body = base64url(JSON.stringify(payload));
    const signature = this.signature(`${header}.${body}`);
    return `${header}.${body}.${signature}`;
  }

  verifyAccessToken(token: string): JwtPayload {
    const [header, body, signature] = token.split(".");
    if (!header || !body || !signature) {
      throw new UnauthorizedException("Invalid access token.");
    }
    if (this.signature(`${header}.${body}`) !== signature) {
      throw new UnauthorizedException("Invalid access token signature.");
    }
    const payload = JSON.parse(decodeBase64url(body)) as JwtPayload;
    if (payload.typ !== "access" || payload.exp < Math.floor(Date.now() / 1000)) {
      throw new UnauthorizedException("Access token expired.");
    }
    return payload;
  }

  createRefreshToken(): { token: string; hash: string; expiresAt: string } {
    const token = base64url(randomBytes(48));
    const hash = this.hashToken(token);
    const expiresAt = new Date(Date.now() + this.refreshTtlDays * 24 * 60 * 60 * 1000).toISOString();
    return { token, hash, expiresAt };
  }

  hashToken(token: string): string {
    return createHmac("sha256", this.secret).update(token).digest("hex");
  }

  private signature(value: string): string {
    return base64url(createHmac("sha256", this.secret).update(value).digest());
  }
}
