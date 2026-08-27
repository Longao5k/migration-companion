import 'dart:io';

String defaultWebBaseUrl() =>
    Platform.isAndroid ? 'http://10.0.2.2:53003' : 'http://127.0.0.1:53003';
