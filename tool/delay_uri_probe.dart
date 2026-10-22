void main() {
  const origin = 'http://192.168.1.88:9090';
  const name = 'MESL | 香港 家宽 01';
  final base = Uri.parse(origin);
  final viaSegments = base.replace(
    pathSegments: <String>['proxies', name, 'delay'],
    queryParameters: const <String, String>{
      'timeout': '5000',
      'url': 'https://www.gstatic.com/generate_204',
    },
  );
  final viaEncode = Uri.parse(
    '$origin/proxies/${Uri.encodeComponent(name)}/delay',
  ).replace(
    queryParameters: const <String, String>{
      'timeout': '5000',
      'url': 'https://www.gstatic.com/generate_204',
    },
  );
  final selectLike = Uri.parse(
    '$origin/proxies/${Uri.encodeComponent('HK-WIFI')}',
  );
  stdout('SEGMENTS toString: $viaSegments');
  stdout('SEGMENTS path: ${viaSegments.path}');
  stdout('ENCODE  toString: $viaEncode');
  stdout('ENCODE  path: ${viaEncode.path}');
  stdout('select group: $selectLike');
  stdout('encodeComponent(name): ${Uri.encodeComponent(name)}');
  stdout('pipe in segments toString: ${viaSegments.toString().contains('|')}');
  stdout('percent-7C in segments: ${viaSegments.toString().contains('%7C')}');
}

void stdout(String line) {
  // ignore: avoid_print
  print(line);
}