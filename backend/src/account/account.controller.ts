import { Body, Controller, Get, Post, Req, UseGuards } from "@nestjs/common";
import { AuthenticatedRequest, AuthGuard } from "../auth/auth.guard";
import { InMemoryStore } from "../domain/in-memory.store";

@Controller()
@UseGuards(AuthGuard)
export class AccountController {
  constructor(private readonly store: InMemoryStore) {}

  @Post("sharing/pause")
  pauseSharing(@Req() request: AuthenticatedRequest, @Body() body: { paused?: boolean }) {
    const user = this.store.setSharingPaused(request.authUser.id, Boolean(body.paused));
    return { user: user ? this.store.toPublicUser(user) : request.publicUser };
  }

  @Post("account/delete-data")
  deleteData(@Req() request: AuthenticatedRequest) {
    this.store.deleteUserTelemetry(request.authUser.id);
    return { deleted: true };
  }

  @Get("account/consent-log")
  consentLog(@Req() request: AuthenticatedRequest) {
    return { logs: this.store.consentLogForUser(request.authUser.id) };
  }
}

