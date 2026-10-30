import 'package:flutter_test/flutter_test.dart';
import 'package:laafi_ma/features/carnet/domain/health_calc.dart';

void main() {
  group('Estimation du cycle', () {
    test('aucune date : pas d\'estimation', () {
      expect(estimateCycle(const [], DateTime(2026, 10, 29)), isNull);
    });

    test('une seule date : pas de moyenne', () {
      final estimate = estimateCycle([DateTime(2026, 10, 1)], DateTime(2026, 10, 5))!;
      expect(estimate.averageLength, isNull);
      expect(estimate.nextStart, isNull);
      expect(estimate.isLate, isFalse);
    });

    test('moyenne arrondie des écarts entre débuts consécutifs', () {
      // Écarts : 28, 30, 29 -> moyenne 29.
      final starts = [DateTime(2026, 7, 1), DateTime(2026, 7, 29), DateTime(2026, 8, 28), DateTime(2026, 9, 26)];
      final estimate = estimateCycle(starts.reversed, DateTime(2026, 10, 1))!;
      expect(estimate.averageLength, 29);
      expect(estimate.nextStart, DateTime(2026, 10, 25));
      expect(estimate.isLate, isFalse);
      expect(estimate.daysLate, 0);
    });

    test('retard signalé après la date estimée', () {
      final starts = [DateTime(2026, 8, 1), DateTime(2026, 8, 29)]; // 28 jours
      final estimate = estimateCycle(starts, DateTime(2026, 10, 1))!;
      expect(estimate.nextStart, DateTime(2026, 9, 26));
      expect(estimate.isLate, isTrue);
      expect(estimate.daysLate, 5);
    });

    test('pas de retard le jour même de la date estimée', () {
      final starts = [DateTime(2026, 8, 1), DateTime(2026, 8, 29)];
      expect(estimateCycle(starts, DateTime(2026, 9, 26))!.isLate, isFalse);
    });

    test('doublons ignorés', () {
      final starts = [DateTime(2026, 8, 1), DateTime(2026, 8, 1, 15), DateTime(2026, 8, 31)];
      expect(estimateCycle(starts, DateTime(2026, 9, 1))!.averageLength, 30);
    });
  });

  group('Grossesse (règle de Naegele)', () {
    test('DDR 1er janvier -> DPA 8 octobre', () {
      expect(naegeleDueDate(DateTime(2026, 1, 1)), DateTime(2026, 10, 8));
    });

    test('DDR 31 mai -> 7 mars de l\'année suivante (+7 j d\'abord)', () {
      expect(naegeleDueDate(DateTime(2026, 5, 31)), DateTime(2027, 3, 7));
    });

    test('jour ramené à la fin du mois si besoin', () {
      // 24 décembre + 7 j = 31 décembre ; − 3 mois -> septembre (30 jours).
      expect(naegeleDueDate(DateTime(2025, 12, 24)), DateTime(2026, 9, 30));
    });

    test('semaines et jours depuis la DDR', () {
      final estimate = pregnancyFromLmp(DateTime(2026, 6, 1), DateTime(2026, 10, 29))!;
      // 150 jours = 21 semaines et 3 jours.
      expect(estimate.totalDays, 150);
      expect(estimate.weeks, 21);
      expect(estimate.days, 3);
      expect(estimate.dueDate, DateTime(2027, 3, 8));
    });

    test('DDR dans le futur : pas d\'estimation', () {
      expect(pregnancyFromLmp(DateTime(2026, 11, 1), DateTime(2026, 10, 29)), isNull);
    });
  });

  test('jour du suivi après l\'accouchement', () {
    expect(postpartumDay(DateTime(2026, 10, 1), DateTime(2026, 10, 29)), 28);
    expect(postpartumFollowUpDays, 42);
  });
}
