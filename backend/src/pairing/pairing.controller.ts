import { Body, Controller, Delete, Get, Post, Req, UseGuards } from "@nestjs/common";
import { AuthenticatedRequest, AuthGuard } from "../auth/auth.guard";
import { PairingService } from "./pairing.service";

@Controller("pairing")
@UseGuards(AuthGuard)
export class PairingController {
  constructor(private readonly pairing: PairingService) {}

  @Post("invite")
  createInvite(@Req() request: AuthenticatedRequest) {
    return { invite: this.pairing.createInvite(request.authUser.id) };
  }

  @Post("accept")
  acceptInvite(@Req() request: AuthenticatedRequest, @Body() body: { code?: string }) {
    return this.pairing.acceptInvite(request.authUser.id, body.code);
  }

  @Get("current")
  current(@Req() request: AuthenticatedRequest) {
    return this.pairing.current(request.authUser.id);
  }

  @Delete("current")
  delete(@Req() request: AuthenticatedRequest) {
    return this.pairing.delete(request.authUser.id);
  }
}

