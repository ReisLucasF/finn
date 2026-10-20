import 'package:finan/domain/entities/user.dart';

abstract class UserRepository {
  Future<AppUser?> findCurrent();

  Future<void> save(AppUser user);
}
