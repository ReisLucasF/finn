final pluggyItemIdPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool isPluggyItemId(String? value) {
  final id = value?.trim() ?? '';
  return id.isNotEmpty && pluggyItemIdPattern.hasMatch(id);
}
