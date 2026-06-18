import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../main.dart';
import 'full_screen_image_page.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    _initialized = true;

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
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

    BigPictureStyleInformation? bigPicture;
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      try {
        String raw = imageBase64;
        if (raw.contains(',')) {
          raw = raw.split(',').last;
        }
        final bytes = base64Decode(raw);
        bigPicture = BigPictureStyleInformation(
          ByteArrayAndroidBitmap(Uint8List.fromList(bytes)),
          contentTitle: title,
          summaryText: body,
          largeIcon: ByteArrayAndroidBitmap(Uint8List.fromList(bytes)),
        );
      } catch (_) {}
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

    final details = NotificationDetails(android: androidDetails);

    String? payloadStr;
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      payloadStr = jsonEncode({'title': title, 'image': imageBase64});
    }

    await _plugin.show(id, title, body, details, payload: payloadStr);
  }
}
