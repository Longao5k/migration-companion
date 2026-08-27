import 'local_repository_base.dart';
import 'local_repository_web.dart'
    if (dart.library.io) 'local_repository_native.dart'
    as implementation;

export 'local_repository_base.dart';

LocalRepository createLocalRepository() =>
    implementation.createLocalRepository();
