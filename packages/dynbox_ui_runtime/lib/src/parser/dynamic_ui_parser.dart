import 'dart:convert';

import '../models/dynamic_ui_models.dart';

/// Parser that validates raw JSON into typed DynamicUiDocument with security limits.
class DynamicUiParser {
  /// Maximum raw JSON string size: 512 KB
  static const int maxJsonLengthBytes = 512 * 1024;

  const DynamicUiParser();

  /// Parses a raw JSON string into a validated [DynamicUiDocument].
  DynamicUiDocument parseJsonString(String jsonContent) {
    if (jsonContent.length > maxJsonLengthBytes) {
      throw DynamicUiException(
        'Document size (${jsonContent.length} bytes) exceeds maximum limit of $maxJsonLengthBytes bytes.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(jsonContent);
    } catch (e) {
      throw DynamicUiException('Malformed JSON: $e');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const DynamicUiException(
        'Dynamic UI document root must be a JSON object.',
      );
    }

    return DynamicUiDocument.fromJson(decoded);
  }
}
