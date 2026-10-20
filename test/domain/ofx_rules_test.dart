import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/entities/ofx_review.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/services/category_suggestion_service.dart';
import 'package:finan/domain/services/duplicate_detection_service.dart';
import 'package:finan/domain/services/duplicate_weights.dart';
import 'package:finan/domain/services/ofx_amount.dart';
import 'package:finan/domain/services/ofx_normalizer.dart';
import 'package:finan/domain/services/transfer_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normaliza descrição sem remover o texto de transferência', () {
    expect(
      normalizeDescription('PIX TRANSF.  JOAO DA SILVA'),
      'pix transf joao da silva',
    );
  });

  test('converte valor OFX para centavos sem ponto flutuante', () {
    expect(tryParseOfxAmount('-25.50')?.cents, -2550);
    expect(tryParseOfxAmount('1.005')?.cents, 101);
    expect(tryParseOfxAmount('1,50')?.cents, 150);
    expect(tryParseOfxAmount('0.00')?.cents, 0);
  });

  test('FITID na mesma conta tem prioridade e os pesos são configuráveis', () {
    const forced = DuplicateDetectionService(
      weights: DuplicateWeights(
        fitId: 0.01,
        amount: 0,
        date: 0,
        description: 0,
        account: 0,
      ),
    );
    final match = forced.evaluate(
      accountId: 'a',
      absoluteAmount: const Money(1000),
      date: const LocalDate(2026, 10, 6),
      normalizedDescription: 'uber',
      fitId: 'fit-1',
      candidates: const [
        DuplicateCandidate(
          transactionId: 't1',
          accountId: 'a',
          amount: Money(1000),
          date: LocalDate(2026, 10, 6),
          externalId: 'fit-1',
        ),
      ],
    );
    expect(match.score, greaterThanOrEqualTo(0.95));
    expect(match.band, DuplicateBand.veryLikely);
    expect(match.isHighProbability, isTrue);

    const weighted = DuplicateDetectionService(
      weights: DuplicateWeights(
        fitId: 0,
        amount: 0.40,
        date: 0.20,
        description: 0,
        account: 0.20,
      ),
    );
    final possible = weighted.evaluate(
      accountId: 'a',
      absoluteAmount: const Money(1000),
      date: const LocalDate(2026, 10, 6),
      normalizedDescription: 'uber',
      fitId: null,
      candidates: const [
        DuplicateCandidate(
          transactionId: 't2',
          accountId: 'a',
          amount: Money(1000),
          date: LocalDate(2026, 10, 1),
        ),
      ],
    );
    expect(possible.score, closeTo(0.60, 0.0001));
    expect(possible.band, DuplicateBand.possible);

    final otherAccount = weighted.evaluate(
      accountId: 'a',
      absoluteAmount: const Money(1000),
      date: const LocalDate(2026, 10, 6),
      normalizedDescription: 'uber',
      fitId: 'fit-1',
      candidates: const [
        DuplicateCandidate(
          transactionId: 't3',
          accountId: 'b',
          amount: Money(1000),
          date: LocalDate(2026, 10, 6),
          externalId: 'fit-1',
        ),
      ],
    );
    expect(otherAccount, DuplicateMatch.none);
  });

  test('transferência possível não cria lançamento e exige outra conta', () {
    const service = TransferDetectionService();
    final found = service.find(
      accountId: 'a',
      absoluteAmount: const Money(5000),
      date: const LocalDate(2026, 10, 6),
      normalizedDescription: 'pix transf joao',
      candidates: const [
        DuplicateCandidate(
          transactionId: 'same',
          accountId: 'a',
          amount: Money(5000),
          date: LocalDate(2026, 10, 6),
          description: 'PIX TRANSF JOAO',
        ),
        DuplicateCandidate(
          transactionId: 'other',
          accountId: 'b',
          amount: Money(5000),
          date: LocalDate(2026, 10, 6),
          description: 'PIX TRANSF JOAO',
        ),
      ],
    );
    expect(found?.accountId, 'b');
    expect(found?.confidence, closeTo(1, 0.0001));

    final far = service.find(
      accountId: 'a',
      absoluteAmount: const Money(5000),
      date: const LocalDate(2026, 10, 6),
      normalizedDescription: 'pix',
      candidates: const [
        DuplicateCandidate(
          transactionId: 'late',
          accountId: 'b',
          amount: Money(5000),
          date: LocalDate(2026, 10, 10),
        ),
      ],
    );
    expect(far, isNull);
  });

  test('classificação anterior prevalece sobre palavra-chave', () {
    const service = CategorySuggestionService();
    final categories = [
      _category('food', 'Alimentação', CategoryType.expense),
      _category('transport', 'Transporte', CategoryType.expense),
    ];
    final fromHistory = service.suggest(
      normalizedDescription: 'uber trip',
      categories: categories,
      history: const [
        ClassifiedDescription(description: 'UBER TRIP', categoryId: 'food'),
      ],
    );
    expect(fromHistory?.categoryId, 'food');
    expect(fromHistory?.confidence, 0.97);

    final fromKeyword = service.suggest(
      normalizedDescription: 'uber trip',
      categories: categories,
      history: const [],
    );
    expect(fromKeyword?.categoryId, 'transport');
    expect(fromKeyword?.confidence, 0.94);

    final word = service.suggest(
      normalizedDescription: 'corrida 99 centro',
      categories: categories,
      history: const [],
    );
    expect(word?.categoryId, 'transport');

    final notWord = service.suggest(
      normalizedDescription: 'pedido 1990',
      categories: categories,
      history: const [],
    );
    expect(notWord, isNull);
  });
}

Category _category(String id, String name, CategoryType type) {
  final now = DateTime.utc(2026, 10, 6);
  return Category(
    id: id,
    name: name,
    type: type,
    isSystem: true,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );
}
