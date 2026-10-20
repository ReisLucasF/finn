enum ProvisionStatus {
  pending('pending'),
  due('due'),
  overdue('overdue'),
  settled('settled'),
  cancelled('cancelled');

  const ProvisionStatus(this.value);

  final String value;

  static ProvisionStatus fromValue(String value) {
    return ProvisionStatus.values.firstWhere((status) => status.value == value);
  }

  bool get isOpen =>
      this == ProvisionStatus.pending ||
      this == ProvisionStatus.due ||
      this == ProvisionStatus.overdue;
}
