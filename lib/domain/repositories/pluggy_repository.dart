import 'package:finan/domain/pluggy/pluggy_models.dart';

abstract class PluggyRepository {
  Future<PluggyConnection?> find(String userId);

  Future<void> save(PluggyConnection connection, DateTime updatedAt);

  Future<void> saveLink(PluggyAccountLink link);

  Future<List<PluggyAccountLink>> links(String userId);

  Future<Map<String, String?>> categoryLinks(String userId);

  Future<void> saveCategoryLink({
    required String userId,
    required String pluggyCategory,
    required String? categoryId,
  });

  Future<void> rememberItem(PluggyItem item, String userId, DateTime updatedAt);

  Future<List<PluggyItem>> items(String userId);

  Future<void> forgetItem(String itemId, String userId);

  Future<void> deleteLink(String pluggyAccountId, String userId);

  Future<void> deleteLinksForItem(String itemId, String userId);

  Future<void> purgeInvalidItems(String userId);
}
