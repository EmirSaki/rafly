import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/book.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl =
      "https://library-api-346058361420.europe-west1.run.app";

  static const MethodChannel _channel = MethodChannel('library_export_channel');

  static String normalizeIsbn(String value) {
    return value.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase().trim();
  }

  static List<String> normalizeStringList(dynamic value) {
    if (value == null) return [];

    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    if (value is String && value
        .trim()
        .isNotEmpty) {
      return value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return [];
  }

  static String normalizeTurkishText(String text) {
    return text
        .trim()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'i')
        .replaceAll('ı', 'i')
        .replaceAll('Ş', 's')
        .replaceAll('ş', 's')
        .replaceAll('Ğ', 'g')
        .replaceAll('ğ', 'g')
        .replaceAll('Ü', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('Ö', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('Ç', 'c')
        .replaceAll('ç', 'c')
        .toLowerCase();
  }

  static Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    final rawBody = response.body.trim();

    if (rawBody.isEmpty) {
      throw Exception("Sunucudan boş yanıt geldi");
    }

    try {
      final decoded = jsonDecode(rawBody);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }

      throw Exception("Sunucudan beklenmeyen veri formatı geldi");
    } catch (_) {
      throw Exception(
          "Sunucudan geçersiz yanıt geldi (${response.statusCode})");
    }
  }

  static String _extractErrorMessage(http.Response response,
      Map<String, dynamic>? decoded,) {
    final message = decoded?["message"]?.toString().trim();

    if (message != null && message.isNotEmpty) {
      return message;
    }

    switch (response.statusCode) {
      case 400:
        return "Geçersiz istek";
      case 401:
        return "Yetkisiz işlem";
      case 403:
        return "Bu işlem için izin yok";
      case 404:
        return "Kayıt bulunamadı";
      case 409:
        return "Çakışan kayıt bulundu";
      case 422:
        return "Gönderilen veri işlenemedi";
      case 500:
        return "Sunucu hatası oluştu";
      case 502:
      case 503:
      case 504:
        return "Sunucuya şu an ulaşılamıyor";
      default:
        return "İşlem başarısız (${response.statusCode})";
    }
  }

  static Map<String, dynamic> _validateSuccessResponse(http.Response response) {
    final decoded = _decodeJsonResponse(response);

    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        decoded["success"] == true) {
      return decoded;
    }

    throw Exception(_extractErrorMessage(response, decoded));
  }

  static Future<Map<String, dynamic>> fetchBookByIsbn(String isbn) async {
    final normalizedIsbn = normalizeIsbn(isbn);
    final url = Uri.parse("$baseUrl/api/books/isbn/$normalizedIsbn");

    final response = await http.get(url);
    final decoded = _validateSuccessResponse(response);
    final data = Map<String, dynamic>.from(decoded["data"] ?? {});

    return {
      "title": (data["title"] ?? "").toString(),
      "authors": normalizeStringList(data["authors"]),
      "publisher": (data["publisher"] ?? "").toString(),
      "categories": normalizeStringList(data["categories"]),
      "isbn": normalizeIsbn((data["isbn"] ?? normalizedIsbn).toString()),
      "isbn10": (data["isbn10"] ?? "").toString(),
      "isbn13": (data["isbn13"] ?? "").toString(),
      "pageCount": int.tryParse('${data["pageCount"] ?? 0}') ?? 0,
      "volumeCount": int.tryParse('${data["volumeCount"] ?? 0}') ?? 0,
      "physicalDescription": (data["physicalDescription"] ?? "").toString(),
      "source": (data["source"] ?? "").toString(),
    };
  }

  static Future<List<Map<String, dynamic>>> getStudents({
    required String schoolCode,
    String? schoolLevel,
  }) async {
    final query = schoolLevel == null || schoolLevel.trim().isEmpty
        ? "schoolCode=$schoolCode"
        : "schoolCode=$schoolCode&school_level=${Uri.encodeComponent(schoolLevel.trim().toLowerCase())}";

    final url = Uri.parse("$baseUrl/api/students?$query");

    final response = await http.get(url);
    final decoded = _validateSuccessResponse(response);

    final List data = decoded["data"] ?? [];

    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> importStudentsFromExcel({
    required String schoolCode,
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    final url = Uri.parse("$baseUrl/api/students/import?schoolCode=$schoolCode");

    final request = http.MultipartRequest("POST", url);

    request.files.add(
      http.MultipartFile.fromBytes(
        "file",
        fileBytes,
        filename: fileName,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    return _validateSuccessResponse(response);
  }

  static Future<Map<String, dynamic>> addManualStudent({
    required String schoolCode,
    required String studentNumber,
    required String fullName,
    required String className,
    required String schoolLevel,
  }) async {
    final url = Uri.parse("$baseUrl/api/students");

    final normalizedClassName = className.trim().toUpperCase();

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "schoolCode": schoolCode,
        "student_number": studentNumber.trim(),
        "full_name": fullName.trim(),
        "class_name": normalizedClassName,
        "class_code": normalizedClassName,
        "school_level": schoolLevel.trim().toLowerCase(),
      }),
    );

    final decoded = _decodeJsonResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw Exception(_extractErrorMessage(response, decoded));
  }

  static Future<Map<String, dynamic>> fetchSchoolBookByIsbn({
    required String schoolCode,
    required String isbn,
  }) async {
    final normalizedIsbn = normalizeIsbn(isbn);

    final url = Uri.parse(
      "$baseUrl/api/schools/$schoolCode/books/isbn/$normalizedIsbn",
    );

    final response = await http.get(url);

    if (response.statusCode == 404) {
      throw Exception("Bu kitap okul envanterinde bulunamadı");
    }

    final decoded = _validateSuccessResponse(response);
    final data = Map<String, dynamic>.from(decoded["data"] ?? {});

    return {
      "title": (data["title"] ?? data["book_name"] ?? "").toString(),
      "authors": normalizeStringList(
        data["authors"] ?? data["book_writer"],
      ),
      "publisher": (data["publisher"] ?? "").toString(),
      "categories": normalizeStringList(
        data["categories"] ?? data["book_genre"],
      ),
      "isbn": normalizeIsbn((data["isbn"] ?? normalizedIsbn).toString()),
      "isbn10": (data["isbn10"] ?? "").toString(),
      "isbn13": (data["isbn13"] ?? "").toString(),
      "pageCount": int.tryParse('${data["pageCount"] ?? data["page_count"] ?? 0}') ?? 0,
      "volumeCount": int.tryParse('${data["volumeCount"] ?? data["volume_count"] ?? 0}') ?? 0,
      "physicalDescription": (data["physicalDescription"] ?? "").toString(),
      "quantity": int.tryParse('${data["quantity"] ?? 0}') ?? 0,
      "available_quantity": int.tryParse(
        '${data["available_quantity"] ?? data["availableQuantity"] ?? 0}',
      ) ?? 0,
      "source": (data["source"] ?? "school_db").toString(),
    };
  }

  static Future<Map<String, dynamic>> saveBook({
    required Map<String, dynamic> bookData,
    bool increaseQuantity = false,
  }) async {
    final schoolCode = (bookData["schoolCode"] ?? "").toString();
    final url = Uri.parse("$baseUrl/api/schools/$schoolCode/books");

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "title": (bookData["title"] ?? "").toString().trim(),
        "authors": normalizeStringList(bookData["authors"]),
        "publisher": (bookData["publisher"] ?? "").toString().trim(),
        "categories": normalizeStringList(bookData["categories"]),
        "isbn": normalizeIsbn((bookData["isbn"] ?? "").toString()),
        "quantity": int.tryParse('${bookData["quantity"] ?? 1}') ?? 1,
        "increaseQuantity": increaseQuantity,
        "pageCount": int.tryParse('${bookData["pageCount"] ?? 0}') ?? 0,
        "volumeCount": (() {
          final count = int.tryParse('${bookData["volumeCount"] ?? 0}') ?? 0;
          return count > 1 ? count : 0;
        })(),
        "physicalDescription":
        (bookData["physicalDescription"] ?? "").toString(),
      }),
    );

    final decoded = _decodeJsonResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw Exception(_extractErrorMessage(response, decoded));
  }

  static Future<Map<String, dynamic>> loginUser({
    required String schoolCode,
    required String email,
    required String password,
  }) async {
    final url = Uri.parse("$baseUrl/api/users/login");

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "schoolCode": schoolCode,
        "email": email,
        "password": password,
      }),
    );

    final decoded = _validateSuccessResponse(response);
    return Map<String, dynamic>.from(decoded["data"] ?? {});
  }

  static Future<Map<String, dynamic>> getSchoolBooks({
    required String schoolCode,
    int page = 1,
    int limit = 30,
    String search = "",
  }) async {
    final normalizedSearch = normalizeTurkishText(search);

    final url = Uri.parse(
      "$baseUrl/api/schools/$schoolCode/books?page=$page&limit=$limit&search=${Uri.encodeComponent(normalizedSearch)}",
    );

    final response = await http.get(url);
    final decoded = _validateSuccessResponse(response);

    final List data = decoded["data"] ?? [];
    final summary = Map<String, dynamic>.from(decoded["summary"] ?? {});

    return {
      "books": data.map((e) => Book.fromJson(e)).toList(),
      "pagination": Map<String, dynamic>.from(decoded["pagination"] ?? {}),
      "summary": summary,
      "totalQuantity": int.tryParse('${summary["totalQuantity"] ?? 0}') ?? 0,
    };
  }

  static Future<Book> getSchoolBookDetail(String schoolCode, int bookId) async {
    final url = Uri.parse("$baseUrl/api/schools/$schoolCode/books/$bookId");

    final response = await http.get(url);
    final decoded = _validateSuccessResponse(response);

    return Book.fromJson(
      Map<String, dynamic>.from(decoded["data"] ?? {}),
    );
  }
  static Future<Map<String, dynamic>> updateSchoolBookQuantity({
    required String schoolCode,
    required int bookId,
    required int quantity,
    List<String>? authors,
    String? publisher,
    List<String>? categories,
    int? pageCount,
  }) async {
    final url = Uri.parse("$baseUrl/api/schools/$schoolCode/books/$bookId");

    final body = <String, dynamic>{
      "quantity": quantity,
    };

    if (authors != null) body["authors"] = authors;
    if (publisher != null) body["publisher"] = publisher;
    if (categories != null) body["categories"] = categories;
    if (pageCount != null) body["page_count"] = pageCount;

    final response = await http.patch(
      url,
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode(body),
    );

    final decoded = _decodeJsonResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw Exception(_extractErrorMessage(response, decoded));
  }

  static Future<Map<String, dynamic>> deleteSchoolBook({
    required String schoolCode,
    required int bookId,
  }) async {
    final url = Uri.parse("$baseUrl/api/schools/$schoolCode/books/$bookId");

    final response = await http.delete(
      url,
      headers: {
        "Content-Type": "application/json",
      },
    );

    final decoded = _decodeJsonResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw Exception(_extractErrorMessage(response, decoded));
  }

  static Future<Map<String, dynamic>> loanBookByStudent({
    required String schoolCode,
    required String isbn,
    required String studentNumber,
    required String schoolLevel,
    String? dueDate,
  }) async {
    final url = Uri.parse("$baseUrl/api/reservations/loan-by-student");

    final body = {
      "schoolCode": schoolCode,
      "isbn": normalizeIsbn(isbn),
      "student_number": studentNumber.trim(),
      "school_level": schoolLevel.trim().toLowerCase(),
      if (dueDate != null && dueDate
          .trim()
          .isNotEmpty)
        "due_date": dueDate.trim(),
    };

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode(body),
    );

    final decoded = _decodeJsonResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw Exception(_extractErrorMessage(response, decoded));
  }

  static Future<List<String>> getClasses({
    required String schoolCode,
  }) async {
    final students = await getStudents(schoolCode: schoolCode);

    final classes = students
        .map((s) => s["class_name"]?.toString().trim().toUpperCase() ?? "")
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();

    classes.sort();
    return classes;
  }

  static Future<List<Map<String, dynamic>>> getReservations({
    required String schoolCode,
    String? status,
    String? studentNumber,
  }) async {
    final params = <String>["schoolCode=$schoolCode"];

    if (status != null && status.trim().isNotEmpty) {
      params.add("status=${Uri.encodeComponent(status.trim().toLowerCase())}");
    }

    if (studentNumber != null && studentNumber.trim().isNotEmpty) {
      params.add("studentNumber=${Uri.encodeComponent(studentNumber.trim())}");
    }

    final url = Uri.parse("$baseUrl/api/reservations?${params.join('&')}");

    final response = await http.get(url);
    final decoded = _validateSuccessResponse(response);

    final List data = decoded["data"] ?? [];

    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> returnReservation({
    required String schoolCode,
    required int reservationId,
  }) async {
    final url = Uri.parse("$baseUrl/api/reservations/$reservationId/return");

    final response = await http.patch(
      url,
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "schoolCode": schoolCode,
      }),
    );

    final decoded = _decodeJsonResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw Exception(_extractErrorMessage(response, decoded));
  }

  static Future<String?> getSchoolLogo({
    required String schoolCode,
  }) async {
    final url = Uri.parse("$baseUrl/api/schools/$schoolCode/logo");

    final response = await http.get(url);

    if (response.statusCode != 200) return null;

    try {
      final decoded = jsonDecode(response.body);
      if (decoded["success"] == true && decoded["data"] != null) {
        return decoded["data"]["logo_url"]?.toString();
      }
    } catch (_) {}

    return null;
  }

  static Future<Map<String, dynamic>> uploadSchoolLogo({
    required String schoolCode,
    required Uint8List imageBytes,
    required String fileName,
  }) async {
    final url = Uri.parse("$baseUrl/api/schools/$schoolCode/logo");

    final request = http.MultipartRequest("POST", url);

    request.files.add(
      http.MultipartFile.fromBytes(
        "logo",
        imageBytes,
        filename: fileName,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    return _validateSuccessResponse(response);
  }

  static Future<Map<String, dynamic>> deleteSchoolLogo({
    required String schoolCode,
  }) async {
    final url = Uri.parse("$baseUrl/api/schools/$schoolCode/logo");

    final response = await http.delete(url);

    final decoded = _decodeJsonResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw Exception(_extractErrorMessage(response, decoded));
  }

  static Future<Map<String, dynamic>> deleteStudent({
    required String schoolCode,
    required String studentNumber,
    required String schoolLevel,
  }) async {
    final url = Uri.parse(
      "$baseUrl/api/students?schoolCode=$schoolCode&student_number=${Uri.encodeComponent(studentNumber)}&school_level=${Uri.encodeComponent(schoolLevel)}",
    );

    final response = await http.delete(
      url,
      headers: {"Content-Type": "application/json"},
    );

    final decoded = _decodeJsonResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw Exception(_extractErrorMessage(response, decoded));
  }

  // ─── Student API Methods ───

  static Future<String?> _getStudentToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('student_token');
  }

  static Future<Map<String, String>> _studentHeaders({bool auth = false}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = await _getStudentToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Future<Map<String, dynamic>> studentLogin({
    required String schoolCode,
    required String studentNumber,
    required String password,
    String? schoolLevel,
  }) async {
    final url = Uri.parse('$baseUrl/api/students/login');
    final response = await http.post(
      url,
      headers: await _studentHeaders(),
      body: jsonEncode({
        'schoolCode': schoolCode,
        'student_number': studentNumber,
        'password': password,
        if (schoolLevel != null) 'school_level': schoolLevel,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> studentRegister({
    required String schoolCode,
    required String userName,
    required String userSurname,
    required String studentNumber,
    required String password,
    required String userClass,
    required String userClassCode,
    required String schoolLevel,
  }) async {
    final url = Uri.parse('$baseUrl/api/students/register');
    final response = await http.post(
      url,
      headers: await _studentHeaders(),
      body: jsonEncode({
        'schoolCode': schoolCode,
        'user_name': userName,
        'user_surname': userSurname,
        'student_number': studentNumber,
        'password': password,
        'user_class': userClass,
        'user_class_code': userClassCode,
        'school_level': schoolLevel,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getStudentProfile() async {
    final url = Uri.parse('$baseUrl/api/students/profile');
    final response = await http.get(
      url,
      headers: await _studentHeaders(auth: true),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> updateStudentProfile({
    String? email,
    String? phone,
    String? password,
  }) async {
    final body = <String, dynamic>{};
    if (email != null) body['email'] = email;
    if (phone != null) body['phone'] = phone;
    if (password != null) body['password'] = password;

    final url = Uri.parse('$baseUrl/api/students/profile');
    final response = await http.patch(
      url,
      headers: await _studentHeaders(auth: true),
      body: jsonEncode(body),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getStudentReservations() async {
    final url = Uri.parse('$baseUrl/api/students/reservations');
    final response = await http.get(
      url,
      headers: await _studentHeaders(auth: true),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> createStudentReservation({
    required int bookId,
  }) async {
    final url = Uri.parse('$baseUrl/api/students/reservations');
    final response = await http.post(
      url,
      headers: await _studentHeaders(auth: true),
      body: jsonEncode({'book_id': bookId}),
    );
    return jsonDecode(response.body);
  }

  static Future<String> exportBooks({
    required String schoolCode,
    required String format,
  }) async {
    final normalizedFormat = format.toLowerCase();
    final extension = normalizedFormat == "pdf" ? "pdf" : "xlsx";
    final mimeType = normalizedFormat == "pdf"
        ? "application/pdf"
        : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    final url = Uri.parse(
      "$baseUrl/api/schools/$schoolCode/books/export?format=$normalizedFormat",
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      Map<String, dynamic>? decoded;

      try {
        decoded = _decodeJsonResponse(response);
      } catch (_) {
        decoded = null;
      }

      throw Exception(_extractErrorMessage(response, decoded));
    }

    final Uint8List bytes = response.bodyBytes;
    final fileName = "kitap-listesi-$schoolCode.$extension";

    final savedPath = await _channel.invokeMethod<String>(
      'saveFileToDownloads',
      {
        'fileName': fileName,
        'mimeType': mimeType,
        'bytes': bytes,
      },
    );

    if (savedPath == null || savedPath.isEmpty) {
      throw Exception("Dosya kaydedilemedi");
    }

    return savedPath;
  }

  static Future<List<Map<String, dynamic>>> getAnnouncements({
    required String schoolCode,
  }) async {
    final url = Uri.parse('$baseUrl/api/announcements?schoolCode=$schoolCode');
    final response = await http.get(
      url,
      headers: await _studentHeaders(auth: true),
    );
    final decoded = jsonDecode(response.body);
    if (decoded['success'] == true) {
      return List<Map<String, dynamic>>.from(decoded['data'] ?? []);
    }
    return [];
  }

  static Future<List<String>> getAnnouncementImages({
    required int id,
  }) async {
    final url = Uri.parse('$baseUrl/api/announcements/$id/images');
    final response = await http.get(
      url,
      headers: await _studentHeaders(auth: true),
    );
    final decoded = jsonDecode(response.body);
    if (decoded['success'] == true && decoded['data'] is List) {
      return List<String>.from(decoded['data']);
    }
    return [];
  }

  static Future<Map<String, dynamic>> createAnnouncement({
    required String schoolCode,
    required String title,
    required String content,
    required String targetType,
    required List<String> targetValues,
    required String startDate,
    required String endDate,
    List<String>? imageBase64List,
  }) async {
    final url = Uri.parse('$baseUrl/api/announcements');
    final body = <String, dynamic>{
      'schoolCode': schoolCode,
      'title': title,
      'content': content,
      'target_type': targetType,
      'target_values': targetValues,
      'start_date': startDate,
      'end_date': endDate,
    };

    if (imageBase64List != null && imageBase64List.isNotEmpty) {
      if (imageBase64List.length == 1) {
        body['image_url'] = imageBase64List.first;
      } else {
        body['image_urls'] = imageBase64List;
      }
    }

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    throw Exception(decoded['message'] ?? 'Bildirim gönderilemedi');
  }
}