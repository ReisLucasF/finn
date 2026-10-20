import 'package:uuid/uuid.dart';

abstract class IdGenerator {
  String next();
}

class UuidGenerator implements IdGenerator {
  UuidGenerator({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  @override
  String next() => _uuid.v4();
}
