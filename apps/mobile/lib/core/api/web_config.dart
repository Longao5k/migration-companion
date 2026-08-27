import 'web_config_stub.dart' if (dart.library.io) 'web_config_mobile.dart';

const configuredWebBaseUrl = String.fromEnvironment('WEB_BASE_URL');

String publicWebBaseUrl() =>
    configuredWebBaseUrl.isEmpty ? defaultWebBaseUrl() : configuredWebBaseUrl;
