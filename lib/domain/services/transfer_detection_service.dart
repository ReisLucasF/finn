import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/ofx_review.dart';
import 'package:finan/domain/services/duplicate_detection_service.dart';
import 'package:finan/domain/services/ofx_normalizer.dart';

class TransferDetectionService {
  const TransferDetectionService();

  PossibleTransfer? find({
    required String accountId,
    required Money absoluteAmount,
    required LocalDate date,
    required String normalizedDescription,
    required List<DuplicateCandidate> candidates,
  }) {
    PossibleTransfer? best;
    for (final candidate in candidates) {
      if (candidate.accountId == accountId) continue;
      if (candidate.amount.cents != absoluteAmount.cents) continue;
      final distance = _daysBetween(candidate.date, date);
      if (distance > 2) continue;
      var confidence = 0.70;
      if (distance == 0) confidence += 0.15;
      final candidateDescription = normalizeDescription(
        candidate.description ?? '',
      );
      if (descriptionsAreSimilar(normalizedDescription, candidateDescription)) {
        confidence += 0.15;
      }
      if (confidence > 1) confidence = 1;
      if (best == null || confidence > best.confidence) {
        best = PossibleTransfer(
          accountId: candidate.accountId,
          transactionId: candidate.transactionId,
          date: candidate.date,
          confidence: confidence,
        );
      }
    }
    return best;
  }

  int _daysBetween(LocalDate left, LocalDate right) {
    final start = DateTime.utc(left.year, left.month, left.day);
    final end = DateTime.utc(right.year, right.month, right.day);
    return start.difference(end).inDays.abs();
  }
}
