import 'package:finan/application/planning/planning_actions.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/planning.dart';
import 'package:finan/domain/enums/investment_kind.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/repositories/finance_repository.dart';
import 'package:finan/domain/repositories/investment_yield_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/services/investment_position_service.dart';

Future<Investment> _owned(
  FinanceRepository finance,
  String userId,
  String investmentId,
) async {
  final investment = await finance.findInvestment(investmentId);
  if (investment == null ||
      investment.isDeleted ||
      investment.userId != userId) {
    throw const ValidationException('Investimento não encontrado.');
  }
  return investment;
}

class UpdateInvestment {
  const UpdateInvestment({
    required FinanceRepository finance,
    required Clock clock,
  }) : _finance = finance,
       _clock = clock;

  final FinanceRepository _finance;
  final Clock _clock;

  Future<void> call({
    required String userId,
    required String investmentId,
    required String name,
    required InvestmentKind kind,
    String? institution,
    String? accountId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Informe o nome do investimento.');
    }
    final current = await _owned(_finance, userId, investmentId);
    final cleanInstitution = institution?.trim();
    await _finance.updateInvestment(
      Investment(
        id: current.id,
        userId: current.userId,
        name: trimmed,
        institution: cleanInstitution == null || cleanInstitution.isEmpty
            ? null
            : cleanInstitution,
        accountId: accountId == null || accountId.isEmpty ? null : accountId,
        kind: kind,
        currency: current.currency,
        currentValue: current.currentValue,
        isActive: current.isActive,
        createdAt: current.createdAt,
        updatedAt: _clock.nowUtc(),
      ),
    );
  }
}

/// Exclui o investimento. Lançamentos vinculados voltam a "não vinculados"
/// (continuam no extrato e no patrimônio) **nada do extrato é apagado**.
class DeleteInvestment {
  const DeleteInvestment({
    required FinanceRepository finance,
    required TransactionRepository transactions,
    required InvestmentYieldRepository yields,
    required UnlinkInvestmentCash unlink,
    required Clock clock,
  }) : _finance = finance,
       _transactions = transactions,
       _yields = yields,
       _unlink = unlink,
       _clock = clock;

  final FinanceRepository _finance;
  final TransactionRepository _transactions;
  final InvestmentYieldRepository _yields;
  final UnlinkInvestmentCash _unlink;
  final Clock _clock;

  /// Retorna quantos lançamentos foram desvinculados.
  Future<int> call({
    required String userId,
    required String investmentId,
  }) async {
    final current = await _owned(_finance, userId, investmentId);
    final linked = await _transactions.list(
      TransactionQuery(
        userId: userId,
        investmentId: investmentId,
        limit: 100000,
      ),
    );
    for (final transaction in linked.items) {
      await _unlink(userId: userId, transactionId: transaction.id);
    }
    await _yields.delete(investmentId);
    final now = _clock.nowUtc();
    await _finance.updateInvestment(
      Investment(
        id: current.id,
        userId: current.userId,
        name: current.name,
        institution: current.institution,
        accountId: current.accountId,
        kind: current.kind,
        currency: current.currency,
        currentValue: current.currentValue,
        isActive: false,
        createdAt: current.createdAt,
        updatedAt: now,
        deletedAt: now,
      ),
    );
    return linked.items.length;
  }
}

/// Remove movimentações que ficaram sem lançamento (ex.: lançamento excluído
/// antes da correção que desfaz o vínculo) e recalcula a posição.
class RemoveOrphanMovements {
  const RemoveOrphanMovements({
    required FinanceRepository finance,
    required Clock clock,
    InvestmentPositionService positions = const InvestmentPositionService(),
  }) : _finance = finance,
       _clock = clock,
       _positions = positions;

  final FinanceRepository _finance;
  final Clock _clock;
  final InvestmentPositionService _positions;

  Future<List<OrphanInvestmentMovement>> list(String investmentId) =>
      _finance.orphanMovements(investmentId);

  Future<void> call({
    required String userId,
    required String investmentId,
  }) async {
    await _owned(_finance, userId, investmentId);
    final orphans = await _finance.orphanMovements(investmentId);
    if (orphans.isEmpty) return;
    final removed = {for (final item in orphans) item.id};
    final all = await _finance.movementsByInvestment(userId);
    // Recalcula pelo que sobra (movementsByInvestment não traz ids; filtra
    // pelas órfãs via contagem por tipo/valor/data).
    final remaining = [...?all[investmentId]];
    for (final orphan in orphans) {
      final index = remaining.indexWhere(
        (m) =>
            m.type == orphan.type &&
            m.amount == orphan.amount &&
            m.date == orphan.date,
      );
      if (index >= 0) remaining.removeAt(index);
    }
    final value = _positions.valueOf([
      for (final m in remaining) (type: m.type, amount: m.amount),
    ]);
    await _finance.removeInvestmentMovements(
      investmentId: investmentId,
      movementIds: removed.toList(),
      currentValue: Money(value.cents < 0 ? 0 : value.cents),
      updatedAt: _clock.nowUtc(),
    );
  }
}

/// Resgate total: registra o valor que caiu na conta e zera a posição.
/// A diferença para a posição lançada vira rendimento (ou perda) real.
class RedeemInvestment {
  const RedeemInvestment({
    required FinanceRepository finance,
    required MoveInvestment move,
    InvestmentPositionService positions = const InvestmentPositionService(),
  }) : _finance = finance,
       _move = move,
       _positions = positions;

  final FinanceRepository _finance;
  final MoveInvestment _move;
  final InvestmentPositionService _positions;

  /// Retorna o ajuste aplicado (positivo = rendimento, negativo = perda).
  Future<Money> call({
    required String userId,
    required String investmentId,
    required Money received,
    required LocalDate date,
    required String accountId,
    String? description,
  }) async {
    final investment = await _owned(_finance, userId, investmentId);
    if (received.cents <= 0) {
      throw const ValidationException('Informe o valor recebido no resgate.');
    }
    final position = _positions.valueOf(
      await _finance.movementsFor(investmentId),
    );
    final diff = received.cents - position.cents;
    final label = description ?? investment.name;
    // Rendimento entra antes, para o resgate caber na posição.
    if (diff > 0) {
      await _move(
        userId: userId,
        investmentId: investmentId,
        movement: InvestmentMovementType.income,
        amount: Money(diff),
        date: date,
        description: 'Rendimento do resgate total · $label',
      );
    }
    await _move(
      userId: userId,
      investmentId: investmentId,
      movement: InvestmentMovementType.withdrawal,
      amount: received,
      date: date,
      accountId: accountId,
      description: 'Resgate total · $label',
    );
    if (diff < 0) {
      await _move(
        userId: userId,
        investmentId: investmentId,
        movement: InvestmentMovementType.loss,
        amount: Money(-diff),
        date: date,
        description: 'Ajuste do resgate total · $label',
      );
    }
    return Money(diff);
  }
}
