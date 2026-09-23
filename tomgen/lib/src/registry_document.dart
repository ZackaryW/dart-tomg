import 'package:toml/toml.dart';

/// A parse or reserved-metadata error independent of CLI/build_runner UI.
final class TomgDocumentException implements Exception {
  const TomgDocumentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Registry rows plus optional generator metadata removed from their document.
final class TomgRegistryDocument {
  TomgRegistryDocument({required this.rows, required this.obfuscatedFields});

  final Map<String, Map<String, dynamic>> rows;

  /// `null` means no `__tomg` table; an empty set is an explicit declaration.
  final Set<String>? obfuscatedFields;

  static TomgRegistryDocument parse(String content, {required String source}) {
    final Map<String, dynamic> document;
    try {
      document = TomlDocument.parse(content).toMap();
    } on Object catch (error) {
      throw TomgDocumentException(
        'Failed to parse TOML source "$source": $error',
      );
    }
    return fromMap(document, source: source);
  }

  static TomgRegistryDocument fromMap(
    Map<String, dynamic> parsed, {
    required String source,
  }) {
    final document = Map<String, dynamic>.of(parsed);
    final obfuscatedFields = _removeMetadata(document, source: source);
    final rows = <String, Map<String, dynamic>>{};
    for (final entry in document.entries) {
      if (entry.value is! Map) {
        throw TomgDocumentException(
          'Expected "${entry.key}" in "$source" to be a TOML table '
          '(a set of key = value pairs), got: ${entry.value}',
        );
      }
      final raw = entry.value as Map;
      if (raw.keys.any((key) => key is! String)) {
        throw TomgDocumentException(
          'Expected table "${entry.key}" in "$source" to use string keys.',
        );
      }
      rows[entry.key] = Map<String, dynamic>.from(raw);
    }
    return TomgRegistryDocument(
      rows: Map.unmodifiable(rows),
      obfuscatedFields: obfuscatedFields == null
          ? null
          : Set.unmodifiable(obfuscatedFields),
    );
  }

  static Set<String>? _removeMetadata(
    Map<String, dynamic> document, {
    required String source,
  }) {
    if (!document.containsKey('__tomg')) return null;
    final rawMetadata = document.remove('__tomg');
    if (rawMetadata is! Map) {
      throw TomgDocumentException(
        'Expected reserved metadata "__tomg" in "$source" to be a TOML table.',
      );
    }
    if (rawMetadata.keys.any((key) => key is! String)) {
      throw TomgDocumentException(
        'Reserved metadata "__tomg" in "$source" must use string keys.',
      );
    }
    final metadata = Map<String, dynamic>.from(rawMetadata);
    for (final key in metadata.keys) {
      if (key != 'obfuscate') {
        throw TomgDocumentException(
          'Unknown metadata key "__tomg.$key" in "$source"; the reserved '
          '"__tomg" table supports only "obfuscate".',
        );
      }
    }
    if (!metadata.containsKey('obfuscate')) {
      throw TomgDocumentException(
        'Reserved metadata table "__tomg" in "$source" is missing required '
        'key "obfuscate".',
      );
    }
    final rawFields = metadata['obfuscate'];
    if (rawFields is! List) {
      throw TomgDocumentException(
        'Expected "__tomg.obfuscate" in "$source" to be a TOML array of '
        'unique field-name strings.',
      );
    }
    final fields = <String>{};
    for (var index = 0; index < rawFields.length; index++) {
      final field = rawFields[index];
      if (field is! String) {
        throw TomgDocumentException(
          'Expected "__tomg.obfuscate[$index]" in "$source" to be a field '
          'name string.',
        );
      }
      if (!fields.add(field)) {
        throw TomgDocumentException(
          'Duplicate field "$field" at "__tomg.obfuscate[$index]" in '
          '"$source".',
        );
      }
    }
    return fields;
  }
}
