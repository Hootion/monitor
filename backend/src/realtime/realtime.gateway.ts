import { Injectable } from "@nestjs/common";
import {
  ConnectedSocket,
  OnGatewayConnection,
  WebSocketGateway,
  WebSocketServer
} from "@nestjs/websockets";
import { Server, Socket } from "socket.io";
import { InMemoryStore } from "../domain/in-memory.store";
import { TokenService } from "../auth/token.service";

@Injectable()
@WebSocketGateway({ cors: { origin: "*" } })
export class RealtimeGateway implements OnGatewayConnection {
  @WebSocketServer()
  server?: Server;

  constructor(
    private readonly tokens: TokenService,
    private readonly store: InMemoryStore
  ) {}

  handleConnection(@ConnectedSocket() client: Socket): void {
    const token = client.handshake.auth?.token ?? client.handshake.query?.token;
    if (typeof token !== "string") {
      client.disconnect(true);
      return;
    }
    try {
      const payload = this.tokens.verifyAccessToken(token);
      if (!this.store.findUser(payload.sub)) {
        client.disconnect(true);
        return;
      }
      client.join(this.userRoom(payload.sub));
      client.data.userId = payload.sub;
    } catch {
      client.disconnect(true);
    }
  }

  notifyUser(userId: string, event: string, payload: Record<string, unknown>): void {
    this.server?.to(this.userRoom(userId)).emit(event, payload);
  }

  private userRoom(userId: string): string {
    return `user:${userId}`;
  }
}

