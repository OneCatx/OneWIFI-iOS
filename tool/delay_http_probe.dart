import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    stdout.writeln('RAW-URI: ${request.uri}');
    stdout.writeln('RAW-PATH: ${request.uri.path}');
    stdout.writeln('DECODED-PATH: ${Uri.decodeComponent(request.uri.path)}');
    stdout.writeln('SEGMENTS: ${request.uri.pathSegments}');
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"delay":88}');
    await request.response.close();
  });

  final origin = Uri.parse('http://127.0.0.1:${server.port}');
  const name = 'MESL | 香港 家宽 01';
  final viaSegments = origin.replace(
    pathSegments: <String>['proxies', name, 'delay'],
    queryParameters: const <String, String>{
      'timeout': '5000',
      'url': 'https://www.gstatic.com/generate_204',
    },
  );
  final viaEncode = Uri.parse(
    '${origin.toString()}/proxies/${Uri.encodeComponent(name)}/delay',
  ).replace(
    queryParameters: const <String, String>{
      'timeout': '5000',
      'url': 'https://www.gstatic.com/generate_204',
    },
  );
  stdout.writeln('CLIENT-SEGMENTS: $viaSegments');
  stdout.writeln('CLIENT-ENCODE: $viaEncode');

  final client = http.Client();
  try {
    stdout.writeln('--- send segments ---');
    await client.get(viaSegments);
    stdout.writeln('--- send encodeComponent ---');
    await client.get(viaEncode);
  } finally {
    client.close();
    await server.close(force: true);
  }
}