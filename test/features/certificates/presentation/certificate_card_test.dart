import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/certificates/domain/certificate.dart';
import 'package:onewifi_android/features/certificates/presentation/widgets/certificate_card.dart';

void main() {
  group('CertificateCard', () {
    late Certificate testCertificate;

    setUp(() {
      testCertificate = Certificate(
        id: 'test-id',
        commonName: 'example.com',
        issuer: 'Test CA',
        validFrom: DateTime(2024, 1, 1),
        validTo: DateTime(2027, 1, 1),
        fingerprint: 'AA:BB:CC',
        source: CertificateSource.custom,
        subjectAlternativeNames: ['example.com', 'www.example.com'],
        coversHost: true,
      );
    });

    testWidgets('renders certificate information', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CertificateCard(
              certificate: testCertificate,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('example.com'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('Test CA'), findsOneWidget);
    });

    testWidgets('shows expired status for expired certificate', (tester) async {
      final expiredCert = testCertificate.copyWith(
        validTo: DateTime(2020, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CertificateCard(
              certificate: expiredCert,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('shows warning for expiring soon certificate', (tester) async {
      final expiringSoonCert = testCertificate.copyWith(
        validTo: DateTime.now().add(const Duration(days: 15)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CertificateCard(
              certificate: expiringSoonCert,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.warning), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CertificateCard(
              certificate: testCertificate,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(CertificateCard));
      await tester.pump();

      expect(tapped, true);
    });

    testWidgets('displays days left for valid certificate', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CertificateCard(
              certificate: testCertificate,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.textContaining('Days Left:'), findsOneWidget);
    });
  });
}
