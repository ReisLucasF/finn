/// Seeds de despesa que não entram na reserva por padrão.
const emergencyDiscretionaryCategoryIds = <String>{
  '019a0000-0000-7000-8000-00000000000c', // Lazer
  '019a0000-0000-7000-8000-00000000000e', // Compras
  '019a0000-0000-7000-8000-000000000011', // Viagens
};

/// Seeds essenciais padrão (moradia, alimentação, transporte, saúde,
/// educação, assinaturas, impostos, serviços, outros).
const emergencyDefaultCategoryIds = <String>[
  '019a0000-0000-7000-8000-000000000007',
  '019a0000-0000-7000-8000-000000000008',
  '019a0000-0000-7000-8000-000000000009',
  '019a0000-0000-7000-8000-00000000000a',
  '019a0000-0000-7000-8000-00000000000b',
  '019a0000-0000-7000-8000-00000000000d',
  '019a0000-0000-7000-8000-00000000000f',
  '019a0000-0000-7000-8000-000000000010',
  '019a0000-0000-7000-8000-000000000012',
];
