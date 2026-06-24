import { BadRequestException, ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import { InMemoryStore } from "../domain/in-memory.store";

@Injectable()
export class PairingService {
  constructor(private readonly store: InMemoryStore) {}

  createInvite(userId: string) {
    if (this.store.getActivePairing(userId)) {
      throw new ConflictException("Current user is already paired.");
    }
    return this.store.createInvite(userId);
  }

  acceptInvite(userId: string, code?: string) {
    if (!code) {
      throw new BadRequestException("Invite code is required.");
    }
    const result = this.store.acceptInvite(code.trim(), userId);
    if (result === "not_found") throw new NotFoundException("Invite code not found.");
    if (result === "expired") throw new BadRequestException("Invite code expired.");
    if (result === "self") throw new BadRequestException("Cannot accept your own invite.");
    if (result === "already_paired") throw new ConflictException("One of the users is already paired.");
    return this.current(userId);
  }

  current(userId: string) {
    const pairing = this.store.getActivePairing(userId);
    if (!pairing) {
      return { pairing: null, partner: null };
    }
    const partnerId = pairing.userAId === userId ? pairing.userBId : pairing.userAId;
    const partner = this.store.findUser(partnerId);
    return {
      pairing,
      partner: partner ? this.store.toPublicUser(partner) : null
    };
  }

  delete(userId: string) {
    return { deleted: this.store.deletePairing(userId) };
  }
}

