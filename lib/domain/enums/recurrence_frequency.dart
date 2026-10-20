enum RecurrenceFrequency {
  daily('daily'),
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly'),
  custom('custom');

  const RecurrenceFrequency(this.value);

  final String value;

  static RecurrenceFrequency fromValue(String value) {
    return RecurrenceFrequency.values.firstWhere(
      (frequency) => frequency.value == value,
    );
  }

  String get label {
    return switch (this) {
      RecurrenceFrequency.daily => 'Diária',
      RecurrenceFrequency.weekly => 'Semanal',
      RecurrenceFrequency.monthly => 'Mensal',
      RecurrenceFrequency.yearly => 'Anual',
      RecurrenceFrequency.custom => 'Personalizada',
    };
  }
}
