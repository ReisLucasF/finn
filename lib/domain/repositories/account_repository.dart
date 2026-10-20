import 'package:finan/domain/entities/account.dart';

abstract class AccountRepository {
  Future<void> save(Account account);

  Future<Account?> findById(String id);

  Future<List<Account>> listByUser(
    String userId, {
    bool includeInactive = true,
  });
}
