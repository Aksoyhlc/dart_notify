import 'package:http/http.dart' as http;

/// Inject http.Client in OneSignalProvider for mock network testing.
typedef OneSignalHttpClient = http.Client;
