import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/ofx_review.dart';
import 'package:finan/domain/services/duplicate_weights.dart';
import 'package:finan/domain/services/ofx_normalizer.dart';

class DuplicateCandidate {
  const DuplicateCandidate({
    required this.transactionId,
    required this.accountId,
    required this.amount,
    required this.date,
    this.description,
    this.externalId,
  });

  final String transactionId;
  final String accountId;
  final Money amount;
  final LocalDate date;
  final String? description;
  final String? externalId;
}

class DuplicateMatch {
  const DuplicateMatch({
    required this.score,
    required this.band,
    this.transactionId,
  });

  final double score;
  final DuplicateBand band;
  final String? transactionId;

  bool get isHighProbability => score >= highProbabilityThreshold;

  static const highProbabilityThreshold = 0.75;
  static const none = DuplicateMatch(score: 0, band: DuplicateBand.none);
}

class DuplicateDetectionService {
  const DuplicateDetectionService({this.weights = const DuplicateWeights()});

  final DuplicateWeights weights;

  DuplicateMatch evaluate({
    required String accountId,
    required Money absoluteAmount,
    required LocalDate date,
    required String normalizedDescription,
    required String? fitId,
    required List<DuplicateCandidate> candidates,
  }) {
    DuplicateMatch best = DuplicateMatch.none;
    for (final candidate in candidates) {
      if (candidate.accountId != accountId) continue;
      final score = _score(
        accountId: accountId,
        absoluteAmount: absoluteAmount,
        date: date,
        normalizedDescription: normalizedDescription,
        fitId: fitId,
        candidate: candidate,
      );
      if (score > best.score) {
        best = DuplicateMatch(
          score: score,
          band: bandFor(score),
          transactionId: candidate.transactionId,
        );
      }
    }
    return best;
  }

  double _score({
    required String accountId,
    required Money absoluteAmount,
    required LocalDate date,
    required String normalizedDescription,
    required String? fitId,
    required DuplicateCandidate candidate,
  }) {
    var score = 0.0;
    final sameFitId =
        fitId != null &&
        fitId.isNotEmpty &&
        candidate.externalId != null &&
        candidate.externalId == fitId;
    if (sameFitId) score += weights.fitId;
    if (candidate.amount.cents == absoluteAmount.cents) score += weights.amount;
    if (candidate.date == date) score += weights.date;
    final candidateDescription = normalizeDescription(
      candidate.description ?? '',
    );
    if (descriptionsAreSimilar(normalizedDescription, candidateDescription)) {
      score += weights.description;
    }
    if (candidate.accountId == accountId) score += weights.account;
    if (sameFitId && score < 0.95) score = 0.95;
    if (score > 1) return 1;
    return score;
  }

  static DuplicateBand bandFor(double score) {
    if (score >= 0.90) return DuplicateBand.veryLikely;
    if (score >= 0.75) return DuplicateBand.probable;
    if (score >= 0.50) return DuplicateBand.possible;
    return DuplicateBand.none;
  }
}
