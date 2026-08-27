import 'attachment_storage_stub.dart'
    if (dart.library.io) 'attachment_storage_native.dart'
    if (dart.library.js_interop) 'attachment_storage_web.dart';
import 'attachment_storage_base.dart';

export 'attachment_storage_base.dart';

AttachmentStorage createAttachmentStorage() =>
    createPlatformAttachmentStorage();
