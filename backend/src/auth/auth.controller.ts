import { Body, Controller, Get, Post, Req, UseGuards } from "@nestjs/common";
import { AuthenticatedRequest, AuthGuard } from "./auth.guard";
import { AuthService } from "./auth.service";

@Controller("auth")
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post("register")
  register(@Body() body: { displayName?: string; phone?: string; password?: string }) {
    return this.auth.register(body);
  }

  @Post("login")
  login(@Body() body: { phone?: string; password?: string }) {
    return this.auth.login(body);
  }

  @Post("refresh")
  refresh(@Body() body: { refreshToken?: string }) {
    return this.auth.refresh(body.refreshToken);
  }

  @Get("me")
  @UseGuards(AuthGuard)
  me(@Req() request: AuthenticatedRequest) {
    return { user: request.publicUser };
  }
}

