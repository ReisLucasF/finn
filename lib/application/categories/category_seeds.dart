import 'package:finan/domain/enums/category_type.dart';

class CategorySeed {
  const CategorySeed({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
  });

  final String id;
  final String name;
  final CategoryType type;
  final String icon;
  final String color;
}

class CategorySeeds {
  const CategorySeeds._();

  static const all = <CategorySeed>[
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000001',
      name: 'Salário',
      type: CategoryType.income,
      icon: 'payments',
      color: '1F6B4A',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000002',
      name: 'Pró-labore',
      type: CategoryType.income,
      icon: 'work',
      color: '1F6B4A',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000003',
      name: 'Freelance',
      type: CategoryType.income,
      icon: 'handshake',
      color: '2E7D6F',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000004',
      name: 'Dividendos',
      type: CategoryType.income,
      icon: 'trending_up',
      color: '3D6B4F',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000005',
      name: 'Juros',
      type: CategoryType.income,
      icon: 'percent',
      color: '3D6B4F',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000006',
      name: 'Outros',
      type: CategoryType.income,
      icon: 'more_horiz',
      color: '5C6B64',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000007',
      name: 'Moradia',
      type: CategoryType.expense,
      icon: 'home',
      color: '7A342C',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000008',
      name: 'Alimentação',
      type: CategoryType.expense,
      icon: 'restaurant',
      color: '8A4B2F',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000009',
      name: 'Transporte',
      type: CategoryType.expense,
      icon: 'directions_car',
      color: '6E4A32',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-00000000000a',
      name: 'Saúde',
      type: CategoryType.expense,
      icon: 'favorite',
      color: '8C3A4A',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-00000000000b',
      name: 'Educação',
      type: CategoryType.expense,
      icon: 'school',
      color: '3E4C7A',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-00000000000c',
      name: 'Lazer',
      type: CategoryType.expense,
      icon: 'local_activity',
      color: '6A4C7A',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-00000000000d',
      name: 'Assinaturas',
      type: CategoryType.expense,
      icon: 'subscriptions',
      color: '4A5A78',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-00000000000e',
      name: 'Compras',
      type: CategoryType.expense,
      icon: 'shopping_bag',
      color: '7A4E32',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-00000000000f',
      name: 'Impostos',
      type: CategoryType.expense,
      icon: 'account_balance',
      color: '5C5346',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000010',
      name: 'Serviços',
      type: CategoryType.expense,
      icon: 'build',
      color: '4E5C56',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000011',
      name: 'Viagens',
      type: CategoryType.expense,
      icon: 'flight',
      color: '2F5E6E',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000012',
      name: 'Outros',
      type: CategoryType.expense,
      icon: 'more_horiz',
      color: '5C6B64',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000013',
      name: 'Aplicação em investimento',
      type: CategoryType.investmentApplication,
      icon: 'savings',
      color: '3E4C7A',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000014',
      name: 'Resgate de investimento',
      type: CategoryType.investmentRedemption,
      icon: 'account_balance',
      color: '2E7D6F',
    ),
    CategorySeed(
      id: '019a0000-0000-7000-8000-000000000015',
      name: 'Transferências internas',
      type: CategoryType.internalTransfer,
      icon: 'swap_horiz',
      color: '4E5C56',
    ),
  ];

}
