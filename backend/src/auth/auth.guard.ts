import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from "@nestjs/common";
import { Request } from "express";
import { InMemoryStore } from "../domain/in-memory.store";
import { PublicUser, User } from "../domain/types";
import { TokenService } from "./token.service";

export interface AuthenticatedRequest extends Request {
  authUser: User;
  publicUser: PublicUser;
}

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly tokens: TokenService,
    private readonly store: InMemoryStore
  ) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const authHeader = request.headers.authorization;
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice("Bearer ".length) : undefined;
    if (!token) {
      throw new UnauthorizedException("Missing bearer token.");
    }
    const payload = this.tokens.verifyAccessToken(token);
    const user = this.store.findUser(payload.sub);
    if (!user) {
      throw new UnauthorizedException("User no longer exists.");
    }
    request.authUser = user;
    request.publicUser = this.store.toPublicUser(user);
    return true;
  }
}

