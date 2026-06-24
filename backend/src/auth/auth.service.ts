import { BadRequestException, Injectable, UnauthorizedException } from "@nestjs/common";
import { InMemoryStore } from "../domain/in-memory.store";
import { PublicUser, User } from "../domain/types";
import { hashPassword, verifyPassword } from "./password";
import { TokenService } from "./token.service";

export interface AuthResponse {
  user: PublicUser;
  accessToken: string;
  refreshToken: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly store: InMemoryStore,
    private readonly tokens: TokenService
  ) {}

  register(input: { displayName?: string; phone?: string; password?: string }): AuthResponse {
    const displayName = input.displayName?.trim();
    const phone = input.phone?.trim();
    const password = input.password ?? "";
    if (!displayName || displayName.length > 40) {
      throw new BadRequestException("Display name is required and must be at most 40 characters.");
    }
    if (!phone || phone.length > 32) {
      throw new BadRequestException("Phone is required.");
    }
    if (password.length < 6) {
      throw new BadRequestException("Password must be at least 6 characters.");
    }
    if (this.store.findUserByPhone(phone)) {
      throw new BadRequestException("Phone is already registered.");
    }
    const { hash, salt } = hashPassword(password);
    const user = this.store.createUser({ displayName, phone, passwordHash: hash, passwordSalt: salt });
    return this.issueTokens(user);
  }

  login(input: { phone?: string; password?: string }): AuthResponse {
    const phone = input.phone?.trim();
    const user = phone ? this.store.findUserByPhone(phone) : undefined;
    if (!user || !verifyPassword(input.password ?? "", user.passwordSalt, user.passwordHash)) {
      throw new UnauthorizedException("Invalid phone or password.");
    }
    return this.issueTokens(user);
  }

  refresh(refreshToken?: string): AuthResponse {
    if (!refreshToken) {
      throw new UnauthorizedException("Refresh token is required.");
    }
    const user = this.store.consumeRefreshToken(this.tokens.hashToken(refreshToken));
    if (!user) {
      throw new UnauthorizedException("Refresh token is invalid or expired.");
    }
    return this.issueTokens(user);
  }

  issueTokens(user: User): AuthResponse {
    const refresh = this.tokens.createRefreshToken();
    this.store.saveRefreshToken(refresh.hash, user.id, refresh.expiresAt);
    return {
      user: this.store.toPublicUser(user),
      accessToken: this.tokens.signAccessToken(user.id),
      refreshToken: refresh.token
    };
  }
}

