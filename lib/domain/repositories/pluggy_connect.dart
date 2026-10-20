import 'package:finan/domain/pluggy/pluggy_models.dart';

abstract class PluggyConnect {
  Future<List<PluggyItem>> open({required String connectToken});

  void cancel();
}

class IdlePluggyConnect implements PluggyConnect {
  const IdlePluggyConnect();

  @override
  Future<List<PluggyItem>> open({required String connectToken}) async =>
      const [];

  @override
  void cancel() {}
}
