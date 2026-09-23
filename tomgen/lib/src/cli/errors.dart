/// An actionable error caused by invalid input or an unsafe CLI operation.
final class TomgenException implements Exception {
  const TomgenException(this.message);

  final String message;

  @override
  String toString() => message;
}
