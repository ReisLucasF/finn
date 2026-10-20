import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/presentation/accounts/account_form_screen.dart';
import 'package:finan/presentation/categories/category_form_screen.dart';
import 'package:finan/presentation/ofx/ofx_import_screen.dart';
import 'package:finan/presentation/transactions/transaction_form_screen.dart';
import 'package:finan/presentation/transfers/transfer_form_screen.dart';
import 'package:flutter/material.dart';

class AppRouter {
  const AppRouter._();

  static Future<bool?> openAccountForm(
    BuildContext context, {
    Account? account,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AccountFormScreen(account: account),
      ),
    );
  }

  static Future<bool?> openTransactionForm(
    BuildContext context, {
    TransactionType? type,
    Transaction? transaction,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            TransactionFormScreen(type: type, transaction: transaction),
      ),
    );
  }

  static Future<bool?> openTransferForm(BuildContext context) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const TransferFormScreen()),
    );
  }

  static Future<bool?> openOfxImport(BuildContext context) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const OfxImportScreen()),
    );
  }

  static Future<bool?> openCategoryForm(
    BuildContext context, {
    Category? category,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CategoryFormScreen(category: category),
      ),
    );
  }
}
