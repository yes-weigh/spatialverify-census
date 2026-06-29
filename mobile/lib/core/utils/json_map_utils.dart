/// Recursively normalizes Hive/JSON maps to [Map<String, dynamic>].
Map<String, dynamic> deepJsonMap(dynamic value) {
  if (value is! Map) {
    throw ArgumentError('Expected a Map, got ${value.runtimeType}');
  }
  return {
    for (final entry in value.entries)
      entry.key.toString(): _deepJsonValue(entry.value),
  };
}

dynamic _deepJsonValue(dynamic value) {
  if (value is Map) return deepJsonMap(value);
  if (value is List) return value.map(_deepJsonValue).toList();
  return value;
}
