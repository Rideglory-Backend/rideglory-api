import {
  HttpStatus,
  Injectable,
  Logger,
  OnModuleInit,
} from '@nestjs/common';
import { RpcException } from '@nestjs/microservices';
import { PrismaClient } from '../generated/prisma';
import { PrismaPg } from '@prisma/adapter-pg';
import { App, cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { envs } from '../config';

export type NotificationType =
  | 'NEW_REGISTRATION'
  | 'REGISTRATION_APPROVED'
  | 'REGISTRATION_REJECTED'
  | 'SOAT_30D'
  | 'SOAT_7D'
  | 'SOAT_DAY_OF'
  | 'MAINTENANCE_DATE_REMINDER'
  | 'EVENT_REMINDER'
  | 'SOS_ALERT'
  | 'TRACKING_ENDED';

export interface NotificationPayload {
  [key: string]: string | number | boolean;
}

@Injectable()
export class NotificationsService extends PrismaClient implements OnModuleInit {
  private readonly logger = new Logger(NotificationsService.name);
  private readonly firebaseApp: App;

  constructor() {
    const url = process.env.DATABASE_URL;
    if (!url) {
      throw new Error('DATABASE_URL is not set for notifications-ms');
    }
    super({ adapter: new PrismaPg({ connectionString: url }) });
    this.firebaseApp = this.initFirebase();
  }

  async onModuleInit() {
    await this.$connect();
  }

  // ── Notification CRUD ────────────────────────────────────────────────────────

  async createNotification(
    userId: string,
    type: NotificationType,
    payload: NotificationPayload,
  ) {
    return this.notification.create({
      data: { userId, type, payload },
    });
  }

  async listNotifications(
    userId: string,
    cursor?: string,
    limit = 20,
  ): Promise<{ data: object[]; nextCursor: string | null }> {
    const take = Math.min(limit, 50);

    const items = await this.notification.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: take + 1,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    });

    const hasMore = items.length > take;
    const data = hasMore ? items.slice(0, take) : items;
    const nextCursor = hasMore ? data[data.length - 1].id : null;

    return { data, nextCursor };
  }

  async markRead(notificationId: string, userId: string): Promise<void> {
    const notification = await this.notification.findUnique({
      where: { id: notificationId },
    });

    if (!notification) {
      throw new RpcException({
        status: HttpStatus.NOT_FOUND,
        message: `Notification ${notificationId} not found`,
      });
    }

    if (notification.userId !== userId) {
      throw new RpcException({
        status: HttpStatus.FORBIDDEN,
        message: "Cannot mark another user's notification as read",
      });
    }

    await this.notification.update({
      where: { id: notificationId },
      data: { isRead: true },
    });
  }

  async markAllRead(userId: string): Promise<void> {
    await this.notification.updateMany({
      where: { userId, isRead: false },
      data: { isRead: true },
    });
  }

  // ── FCM ──────────────────────────────────────────────────────────────────────

  async sendFcm(
    fcmToken: string,
    title: string,
    body: string,
    data: Record<string, string>,
  ): Promise<void> {
    try {
      await getMessaging(this.firebaseApp).send({
        token: fcmToken,
        notification: { title, body },
        data,
      });
    } catch (err: unknown) {
      // Non-fatal: log and continue — a bad FCM token should not fail the caller
      this.logger.warn(`FCM send failed: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  private initFirebase(): App {
    const existing = getApps();
    if (existing.length > 0) {
      return existing[0];
    }

    const rawJson = envs.firebaseServiceAccountJson;
    if (rawJson) {
      try {
        const serviceAccount = JSON.parse(rawJson) as Record<string, string>;
        return initializeApp({ credential: cert(serviceAccount) });
      } catch {
        throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON');
      }
    }

    const projectId = envs.firebaseProjectId;
    if (!projectId) {
      throw new Error(
        'Firebase misconfigured: set FIREBASE_PROJECT_ID or FIREBASE_SERVICE_ACCOUNT_JSON',
      );
    }

    return initializeApp({ projectId });
  }
}
