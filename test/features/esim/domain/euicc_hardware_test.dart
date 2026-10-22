import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/esim/domain/euicc_catalog.dart';
import 'package:onewifi_android/features/esim/domain/euicc_hardware.dart';

const String _gsmaIsdrAid = 'A0000005591010FFFFFFFF8900000100';
const String _estkSe0Aid = 'A06573746B6D65FFFF4953442D522030';

void main() {
  test(
    'labels G+D SAS + GSMA ISD-R as G+D天联, not a backwards D+G nameplate',
    () {
      expect(
        resolveEuiccNameplate(
          aids: const <String>[_gsmaIsdrAid],
          eids: const <String>['8904903200000001'],
          sasList: const <String>['GD-NG-UP-1227'],
        ),
        'G+D天联',
      );
    },
  );

  test(
    'does not call an ESTK SE0 card G+D天联 even when the EIN is G+D silicon',
    () {
      expect(
        resolveEuiccNameplate(
          aids: const <String>[_estkSe0Aid],
          eids: const <String>['89049032'],
          firmware: '32.33.0',
        ),
        'Estk.me C beta',
      );
    },
  );

  test('labels GSMA ISD-R + G+D EIN without SAS as G+D天联', () {
    expect(
      resolveEuiccNameplate(
        aids: const <String>[_gsmaIsdrAid],
        eids: const <String>['8904903200000001'],
      ),
      'G+D天联',
    );
  });

  test('labels 9eSIM B1 from the Eastcompeace EIN and its SAS', () {
    expect(
      resolveEuiccNameplate(
        aids: const <String>[_gsmaIsdrAid],
        eids: const <String>['89086030202200000025000015085962'],
        sasList: const <String>['ED-ZI-UP-0828'],
      ),
      '9eSIM B1',
    );
  });

  test('a synced catalog names a card the built-in rules do not know', () {
    addTearDown(clearEuiccCatalog);
    replaceEuiccCatalog(<String, Object>{
      'rules': <Object>[
        <String, Object>{
          'nameplate': '海豚卡',
          'eidPrefixes': <String>['89012345'],
        },
      ],
    });
    expect(
      resolveEuiccNameplate(
        aids: const <String>[_gsmaIsdrAid],
        eids: const <String>['8901234500000001'],
      ),
      '海豚卡',
    );
  });
}
