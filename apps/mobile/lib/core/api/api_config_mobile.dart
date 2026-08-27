import 'dart:io';

String defaultApiBaseUrl() => Platform.isAndroid
    ? 'http://10.0.2.2:53001/v1'
    : 'http://127.0.0.1:53001/v1';
