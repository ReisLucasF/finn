import 'dart:math' as math;

import 'package:finan/core/date/business_calendar.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/entities/investment_yield.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/services/investment_tax_service.dart';
import 'package:finan/domain/services/yield_estimate_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calendar = BusinessCalendar();
  const taxes = InvestmentTaxService();
  const service = YieldEstimateService();

  group('BusinessCalendar', () {
    test('Páscoa e feriados móveis de 2026', () {
      expect(BusinessCalendar.easterSunday(2026), const LocalDate(2026, 4, 5));
      expect(BusinessCalendar.easterSunday(2025), const LocalDate(2025, 4, 20));
      final holidays = calendar.holidays(2026);
      expect(holidays, contains(const LocalDate(2026, 2, 16))); // Carnaval
      expect(holidays, contains(const LocalDate(2026, 2, 17))); // Carnaval
      expect(holidays, contains(const LocalDate(2026, 4, 3))); // Sexta Santa
      expect(holidays, contains(const LocalDate(2026, 6, 4))); // Corpus Christi
      expect(
        holidays,
        contains(const LocalDate(2026, 11, 20)),
      ); // Consciência Negra
      expect(
        calendar.holidays(2023),
        isNot(contains(const LocalDate(2023, 11, 20))),
      );
    });

    test('fim de semana e feriado não são dias úteis', () {
      expect(
        calendar.isBusinessDay(const LocalDate(2026, 10, 17)),
        isFalse,
      ); // sábado
      expect(
        calendar.isBusinessDay(const LocalDate(2026, 10, 12)),
        isFalse,
      ); // feriado
      expect(calendar.isBusinessDay(const LocalDate(2026, 10, 13)), isTrue);
      // Outubro/2026: 22 dias de semana, menos 12/10 = 21 dias úteis.
      expect(
        calendar.businessDaysBetween(
          const LocalDate(2026, 10, 1),
          const LocalDate(2026, 11, 1),
        ),
        21,
      );
    });
  });

  group('InvestmentTaxService', () {
    test('IR regressivo por faixa de prazo', () {
      expect(taxes.incomeTaxRate(180), 0.225);
      expect(taxes.incomeTaxRate(181), 0.20);
      expect(taxes.incomeTaxRate(360), 0.20);
      expect(taxes.incomeTaxRate(361), 0.175);
      expect(taxes.incomeTaxRate(720), 0.175);
      expect(taxes.incomeTaxRate(721), 0.15);
    });

    test('IOF regressivo zera no 30º dia', () {
      expect(taxes.iofRate(1), 0.96);
      expect(taxes.iofRate(10), 0.66);
      expect(taxes.iofRate(15), 0.50);
      expect(taxes.iofRate(29), 0.03);
      expect(taxes.iofRate(30), 0);
      expect(taxes.iofRate(400), 0);
    });
  });

  group('YieldEstimateService', () {
    final updated = DateTime.utc(2026);
    InvestmentYield config(
      YieldIndexer indexer,
      double rate, {
      TaxRegime regime = TaxRegime.regressive,
    }) => InvestmentYield(
      investmentId: 'i',
      indexer: indexer,
      rate: rate,
      taxRegime: regime,
      updatedAt: updated,
    );

    DatedInvestmentMovement move(
      InvestmentMovementType type,
      int cents,
      LocalDate date,
    ) => DatedInvestmentMovement(date: date, type: type, amount: Money(cents));

    // CDI de 0,05% ao dia em todos os dias úteis de 1 a 30/10/2026.
    final cdi = CdiSnapshot(
      daily: {
        for (
          var d = const LocalDate(2026, 10, 1);
          d <= const LocalDate(2026, 10, 30);
          d = d.addDays(1)
        )
          if (calendar.isBusinessDay(d)) d: 0.05,
      },
      annualPercent: 13.65,
    );

    test('100% do CDI com IOF e IR no 13º dia', () {
      final estimate = service.estimate(
        config: config(YieldIndexer.cdiPercent, 100),
        movements: [
          move(
            InvestmentMovementType.contribution,
            1000000,
            const LocalDate(2026, 10, 1),
          ),
        ],
        cdi: cdi,
        asOf: const LocalDate(2026, 10, 14),
      )!;
      // Dias úteis de 1 a 13/10 (sem 12/10): 1,2,5,6,7,8,9,13 = 8.
      expect(estimate.businessDays, 8);
      final gross = 1000000 * math.pow(1.0005, 8);
      expect(estimate.gross.cents, gross.round());
      final gain = gross - 1000000;
      final iof = gain * 0.56; // 13 dias corridos
      expect(estimate.iof.cents, iof.round());
      expect(estimate.incomeTax.cents, ((gain - iof) * 0.225).round());
      expect(estimate.cdiShare, closeTo(1, 1e-4));
      expect(estimate.projectedDays, 0);
    });

    test('110% do CDI rende mais que o CDI e isento não paga imposto', () {
      final estimate = service.estimate(
        config: config(YieldIndexer.cdiPercent, 110, regime: TaxRegime.exempt),
        movements: [
          move(
            InvestmentMovementType.contribution,
            1000000,
            const LocalDate(2026, 10, 1),
          ),
        ],
        cdi: cdi,
        asOf: const LocalDate(2026, 10, 31),
      )!;
      expect(estimate.cdiShare, closeTo(1.1, 0.002));
      expect(estimate.taxes, Money.zero);
      expect(estimate.net, estimate.gross);
    });

    test('aportes em datas diferentes a 100% do CDI dão 100% do CDI', () {
      final estimate = service.estimate(
        config: config(YieldIndexer.cdiPercent, 100),
        movements: [
          move(
            InvestmentMovementType.contribution,
            100000,
            const LocalDate(2026, 10, 1),
          ),
          move(
            InvestmentMovementType.contribution,
            900000,
            const LocalDate(2026, 10, 26),
          ),
        ],
        cdi: cdi,
        asOf: const LocalDate(2026, 10, 31),
      )!;
      expect(estimate.cdiShare, closeTo(1, 1e-3));
    });

    test('resgate sai do lote mais antigo (FIFO)', () {
      final estimate = service.estimate(
        config: config(YieldIndexer.cdiPercent, 100),
        movements: [
          move(
            InvestmentMovementType.contribution,
            100000,
            const LocalDate(2026, 10, 1),
          ),
          move(
            InvestmentMovementType.contribution,
            100000,
            const LocalDate(2026, 10, 15),
          ),
          // Resgata exatamente o valor bruto do primeiro lote em 15/10.
          move(
            InvestmentMovementType.withdrawal,
            (100000 * math.pow(1.0005, 9)).round(),
            const LocalDate(2026, 10, 15),
          ),
        ],
        cdi: cdi,
        asOf: const LocalDate(2026, 10, 15),
      )!;
      expect(estimate.principal.cents, closeTo(100000, 1));
      expect(estimate.gross.cents, closeTo(100000, 1));
    });

    test('resgate antes do primeiro aporte desconta do aporte', () {
      final estimate = service.estimate(
        config: config(YieldIndexer.cdiPercent, 100),
        movements: [
          move(
            InvestmentMovementType.withdrawal,
            39000,
            const LocalDate(2025, 7, 20),
          ),
          move(
            InvestmentMovementType.contribution,
            100000,
            const LocalDate(2026, 10, 1),
          ),
        ],
        cdi: cdi,
        asOf: const LocalDate(2026, 10, 1),
      )!;
      expect(estimate.principal, const Money(61000));
      expect(estimate.gross, const Money(61000));
    });

    test('dias sem publicação usam o CDI anualizado e o calendário', () {
      final estimate = service.estimate(
        config: config(YieldIndexer.cdiPercent, 100),
        movements: [
          move(
            InvestmentMovementType.contribution,
            1000000,
            const LocalDate(2026, 10, 26),
          ),
        ],
        cdi: cdi,
        // Publicado até 30/10; 2/11 é feriado; 3 a 6/11 projetados.
        asOf: const LocalDate(2026, 11, 7),
      )!;
      expect(estimate.projectedDays, 4);
      expect(estimate.businessDays, 9);
    });

    test('prefixado 12% a.a. rende 12% em 252 dias úteis', () {
      final estimate = service.estimate(
        config: config(YieldIndexer.prefixed, 12),
        movements: [
          move(
            InvestmentMovementType.contribution,
            1000000,
            const LocalDate(2026, 1, 2),
          ),
        ],
        cdi: CdiSnapshot.empty,
        asOf: const LocalDate(2027, 1, 4),
      )!;
      final expected = 1000000 * math.pow(1.12, estimate.businessDays / 252);
      expect(estimate.gross.cents, closeTo(expected, 1));
      // Mais de 1 ano: IR de 17,5%, sem IOF.
      expect(estimate.iof, Money.zero);
      expect(
        estimate.incomeTax.cents,
        closeTo(estimate.grossGain.cents * 0.175, 1),
      );
    });

    test('sem dados do CDI não estima indexado ao CDI', () {
      expect(
        service.estimate(
          config: config(YieldIndexer.cdiPercent, 100),
          movements: [
            move(
              InvestmentMovementType.contribution,
              1000,
              const LocalDate(2026, 10, 1),
            ),
          ],
          cdi: CdiSnapshot.empty,
          asOf: const LocalDate(2026, 10, 10),
        ),
        isNull,
      );
    });

    test('rendimento lançado à mão é ignorado e informado', () {
      final estimate = service.estimate(
        config: config(YieldIndexer.cdiPercent, 100),
        movements: [
          move(
            InvestmentMovementType.contribution,
            100000,
            const LocalDate(2026, 10, 1),
          ),
          move(
            InvestmentMovementType.income,
            500,
            const LocalDate(2026, 10, 5),
          ),
        ],
        cdi: cdi,
        asOf: const LocalDate(2026, 10, 6),
      )!;
      expect(estimate.ignoredIncome, const Money(500));
      expect(estimate.gross.cents, (100000 * math.pow(1.0005, 3)).round());
    });
  });
}
