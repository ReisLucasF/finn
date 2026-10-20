import 'package:finan/core/date/local_date.dart';
import 'package:finan/domain/enums/provision_status.dart';
import 'package:finan/domain/enums/recurrence_frequency.dart';

LocalDate advanceOccurrence(
  LocalDate current,
  RecurrenceFrequency frequency,
  int interval,
) {
  return switch (frequency) {
    RecurrenceFrequency.daily => current.addDays(interval),
    RecurrenceFrequency.weekly => current.addDays(7 * interval),
    RecurrenceFrequency.monthly => current.addMonths(interval),
    RecurrenceFrequency.yearly => current.addMonths(12 * interval),
    RecurrenceFrequency.custom => current.addDays(interval),
  };
}

ProvisionStatus provisionStatusOn(LocalDate dueDate, LocalDate today) {
  if (dueDate < today) return ProvisionStatus.overdue;
  if (dueDate == today) return ProvisionStatus.due;
  return ProvisionStatus.pending;
}
