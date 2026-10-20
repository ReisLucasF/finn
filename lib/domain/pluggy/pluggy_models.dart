import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';

class PluggyConnection {
  const PluggyConnection({
    required this.userId,
    required this.clientId,
    required this.clientSecret,
    this.itemId = '',
  });

  final String userId;
  final String clientId;
  final String clientSecret;
  final String itemId;
}

class PluggyItem {
  const PluggyItem({
    required this.id,
    required this.connectorName,
    this.status,
  });

  final String id;
  final String connectorName;
  final String? status;
}

class PluggyItemListing {
  const PluggyItemListing({
    required this.items,
    required this.listingEnabled,
  });

  final List<PluggyItem> items;
  final bool listingEnabled;
}

class PluggyAccountLink {
  const PluggyAccountLink({
    required this.pluggyAccountId,
    required this.userId,
    required this.name,
    required this.kind,
    this.itemId,
    this.accountId,
    this.creditCardId,
  });

  final String pluggyAccountId;
  final String userId;
  final String name;
  final String kind;
  final String? itemId;
  final String? accountId;
  final String? creditCardId;

  bool get isLinked => accountId != null || creditCardId != null;
}

class PluggyRemoteAccount {
  const PluggyRemoteAccount({
    required this.id,
    required this.name,
    required this.kind,
    this.itemId,
    this.creditLimit,
    this.brand,
    this.lastFourDigits,
    this.closingDay,
    this.dueDay,
  });

  final String id;
  final String name;
  final String kind;
  final String? itemId;
  final Money? creditLimit;
  final String? brand;
  final String? lastFourDigits;
  final int? closingDay;
  final int? dueDay;
}

class PluggyBankConnection {
  const PluggyBankConnection({
    required this.item,
    required this.links,
  });

  final PluggyItem item;
  final List<PluggyAccountLink> links;
}

class PluggyRemoteTransaction {
  const PluggyRemoteTransaction({
    required this.id,
    required this.accountId,
    required this.description,
    required this.date,
    required this.amount,
    required this.type,
    required this.status,
    this.operationType,
    this.category,
  });

  final String id;
  final String accountId;
  final String description;
  final LocalDate date;
  final Money amount;
  final String type;
  final String status;
  final String? operationType;
  final String? category;

  String get externalId => 'pluggy:$id';
}

enum PluggyPosting {
  bankIncome,
  bankExpense,
  cardExpense,
  investmentApplication,
  investmentRedemption,
  cardBill,
  pending,
  ignored,
}

class PluggyReviewLine {
  const PluggyReviewLine({
    required this.remoteId,
    required this.externalId,
    required this.description,
    required this.date,
    required this.absoluteAmount,
    required this.posting,
    required this.alreadyImported,
    required this.pluggyAccountId,
    required this.accountId,
    required this.creditCardId,
    this.pluggyCategory,
    this.categoryId,
    this.matchTransactionId,
    this.matchDescription,
    this.namesSimilar = false,
  });

  final String remoteId;
  final String externalId;
  final String description;
  final LocalDate date;
  final Money absoluteAmount;
  final PluggyPosting posting;
  final bool alreadyImported;
  final String pluggyAccountId;
  final String? accountId;
  final String? creditCardId;
  final String? pluggyCategory;
  final String? categoryId;
  final String? matchTransactionId;
  final String? matchDescription;
  final bool namesSimilar;

  bool get canImport =>
      !alreadyImported &&
      posting != PluggyPosting.cardBill &&
      posting != PluggyPosting.pending &&
      posting != PluggyPosting.ignored;

  bool get selectedByDefault => canImport && matchTransactionId == null;

  /// Mesmo valor, mesma conta e nome parecido com um lançamento já confirmado.
  bool get suggestReconcile =>
      canImport && matchTransactionId != null && namesSimilar;

  PluggyReviewLine withCategory(String? categoryId) {
    return PluggyReviewLine(
      remoteId: remoteId,
      externalId: externalId,
      description: description,
      date: date,
      absoluteAmount: absoluteAmount,
      posting: posting,
      alreadyImported: alreadyImported,
      pluggyAccountId: pluggyAccountId,
      accountId: accountId,
      creditCardId: creditCardId,
      pluggyCategory: pluggyCategory,
      categoryId: categoryId,
      matchTransactionId: matchTransactionId,
      matchDescription: matchDescription,
      namesSimilar: namesSimilar,
    );
  }
}

class PluggyImportResult {
  const PluggyImportResult({required this.imported, required this.reconciled});

  final int imported;
  final int reconciled;
}
