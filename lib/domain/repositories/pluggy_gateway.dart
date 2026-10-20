import 'package:finan/domain/pluggy/pluggy_models.dart';

abstract class PluggyGateway {
  Future<PluggyItemListing> listItems({
    required String clientId,
    required String clientSecret,
  });

  Future<String> connectToken({
    required String clientId,
    required String clientSecret,
    required String clientUserId,
  });

  Future<List<PluggyRemoteAccount>> accounts({
    required String clientId,
    required String clientSecret,
    required String itemId,
  });

  Future<List<PluggyRemoteTransaction>> transactions({
    required String clientId,
    required String clientSecret,
    required String accountId,
    required DateTime from,
    required DateTime to,
  });
}
