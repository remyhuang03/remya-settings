/// Display operations owned by the resident Rust service.
abstract class DisplayBackend {
  Future<Map<String, dynamic>> read();
  Future<Map<String, dynamic>> brightness();
  Future<Map<String, dynamic>> set(String id, String value);
  Future<Map<String, dynamic>> resolve(String source);
}
