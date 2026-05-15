import { Controller } from '@nestjs/common';
import { MessagePattern, Payload } from '@nestjs/microservices';
import {
  NotificationsService,
  NotificationType,
  NotificationPayload,
} from './notifications.service';

@Controller()
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @MessagePattern('notification.create')
  create(
    @Payload()
    payload: {
      userId: string;
      type: NotificationType;
      data: NotificationPayload;
    },
  ) {
    return this.notificationsService.createNotification(
      payload.userId,
      payload.type,
      payload.data,
    );
  }

  @MessagePattern('notification.list')
  list(
    @Payload()
    payload: { userId: string; cursor?: string; limit?: number },
  ) {
    return this.notificationsService.listNotifications(
      payload.userId,
      payload.cursor,
      payload.limit,
    );
  }

  @MessagePattern('notification.markRead')
  markRead(@Payload() payload: { notificationId: string; userId: string }) {
    return this.notificationsService.markRead(
      payload.notificationId,
      payload.userId,
    );
  }

  @MessagePattern('notification.markAllRead')
  markAllRead(@Payload() payload: { userId: string }) {
    return this.notificationsService.markAllRead(payload.userId);
  }

  @MessagePattern('notification.sendFcm')
  sendFcm(
    @Payload()
    payload: {
      fcmToken: string;
      title: string;
      body: string;
      data: Record<string, string>;
    },
  ) {
    return this.notificationsService.sendFcm(
      payload.fcmToken,
      payload.title,
      payload.body,
      payload.data,
    );
  }
}
