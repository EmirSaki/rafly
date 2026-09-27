import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import 'full_screen_image_page.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    _initialized = true;

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final title = data['title'] as String? ?? 'Duyuru';

      final imagesList = data['images'] as List?;
      final singleImage = data['image'] as String?;

      List<String>? images;
      if (imagesList != null && imagesList.isNotEmpty) {
        images = imagesList.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      } else if (singleImage != null && singleImage.isNotEmpty) {
        images = [singleImage];
      }

      if (images != null && images.isNotEmpty) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          Navigator.of(ctx).push(
            MaterialPageRoute(
              builder: (_) => FullScreenImagePage(
                imageList: images,
                title: title,
              ),
            ),
          );
        }
      }
    } catch (_) {}
  }

  static Future<void> showAnnouncementNotification({
    required int id,
    required String title,
    required String body,
    String? imageBase64,
  }) async {
    if (!_initialized) await init();

    Uint8List? imageBytes;
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      try {
        String raw = imageBase64;
        if (raw.contains(',')) {
          raw = raw.split(',').last;
        }
        imageBytes = base64Decode(raw);
      } catch (_) {}
    }

    BigPictureStyleInformation? bigPicture;
    if (imageBytes != null) {
      bigPicture = BigPictureStyleInformation(
        ByteArrayAndroidBitmap(imageBytes),
        contentTitle: title,
        summaryText: body,
        largeIcon: ByteArrayAndroidBitmap(imageBytes),
      );
    }

    final androidDetails = AndroidNotificationDetails(
      'announcements',
      'Bilgilendirmeler',
      channelDescription: 'Okul duyuruları ve bilgilendirmeler',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      styleInformation: bigPicture ??
          BigTextStyleInformation(
            body,
            contentTitle: title,
          ),
    );

    // iOS: gorseli gecici dosyaya yazip bildirime ek olarak baglariz.
    List<DarwinNotificationAttachment>? iosAttachments;
    if (imageBytes != null && Platform.isIOS) {
      try {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/rafly_notif_$id.jpg');
        await file.writeAsBytes(imageBytes);
        iosAttachments = [DarwinNotificationAttachment(file.path)];
      } catch (_) {}
    }

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      attachments: iosAttachments,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    String? payloadStr;
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      payloadStr = jsonEncode({'title': title, 'image': imageBase64});
    }

    await _plugin.show(id, title, body, details, payload: payloadStr);
  }
}
