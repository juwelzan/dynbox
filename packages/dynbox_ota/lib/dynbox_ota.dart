/// DynBox OTA (Over-The-Air) Update SDK.
///
/// Provides a safe, first-party, schema-driven Dynamic UI update system
/// for Flutter applications without Shorebird or arbitrary code execution.
library dynbox_ota;

export 'src/models/ota_manifest.dart';
export 'src/security/ota_verifier.dart';
export 'src/provider/ota_provider.dart';
export 'src/provider/supabase_ota_provider.dart';
export 'src/cache/ota_cache.dart';
export 'src/client/dynbox_ota_client.dart';
export 'src/service/dynbox_ota_service.dart';
