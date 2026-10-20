import 'package:finan/domain/enums/transaction_type.dart';

enum CategoryType {
  income('income'),
  expense('expense'),
  both('both'),
  investmentApplication('investment_application'),
  investmentRedemption('investment_redemption'),
  internalTransfer('internal_transfer');

  const CategoryType(this.value);

  final String value;

  static CategoryType fromValue(String value) {
    return CategoryType.values.firstWhere((type) => type.value == value);
  }

  bool accepts(TransactionType type) {
    return switch (this) {
      CategoryType.both => true,
      CategoryType.income =>
        type == TransactionType.income ||
            type == TransactionType.investmentWithdrawal,
      CategoryType.expense =>
        type == TransactionType.expense ||
            type == TransactionType.investmentContribution,
      CategoryType.investmentApplication =>
        type == TransactionType.expense ||
            type == TransactionType.investmentContribution,
      CategoryType.investmentRedemption =>
        type == TransactionType.income ||
            type == TransactionType.investmentWithdrawal,
      CategoryType.internalTransfer =>
        type == TransactionType.income ||
            type == TransactionType.expense ||
            type == TransactionType.transfer,
    };
  }

  /// Tipo gravado. Aplicação, resgate e transferência interna saem de receita/despesa.
  TransactionType storedType(TransactionType requested) {
    return switch (this) {
      CategoryType.investmentApplication =>
        TransactionType.investmentContribution,
      CategoryType.investmentRedemption => TransactionType.investmentWithdrawal,
      CategoryType.internalTransfer => TransactionType.transfer,
      _ => requested,
    };
  }

  String get label {
    return switch (this) {
      CategoryType.income => 'Receita',
      CategoryType.expense => 'Despesa',
      CategoryType.both => 'Ambas',
      CategoryType.investmentApplication => 'Aplicação em investimento',
      CategoryType.investmentRedemption => 'Resgate de investimento',
      CategoryType.internalTransfer => 'Transferência interna',
    };
  }
}
