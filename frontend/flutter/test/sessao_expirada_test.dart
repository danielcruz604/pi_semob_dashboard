import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:semob_dashboard/relatorio_api_service.dart';

void main() {
  late int disparos;

  setUp(() {
    disparos = 0;
    RelatorioApiService.limparSessao();
    RelatorioApiService.configurarBaseUrl('http://api.teste');
    RelatorioApiService.aoSessaoExpirar = () {
      disparos++;
      // Simula o app encerrando a sessão, como faz o handler registrado no main.dart.
      RelatorioApiService.limparSessao();
    };
  });

  tearDown(() {
    RelatorioApiService.aoSessaoExpirar = null;
    RelatorioApiService.limparSessao();
    RelatorioApiService.configurarBaseUrl(null);
  });

  group('RelatorioApiService.notificarRespostaNaoAutorizada', () {
    test('dispara quando a API recusa o token de uma sessão ativa', () {
      RelatorioApiService.definirToken('token-expirado');

      RelatorioApiService.notificarRespostaNaoAutorizada(401, endpoint: '/api/dashboard/filtros');

      expect(disparos, 1);
      expect(RelatorioApiService.estaAutenticado, isFalse);
    });

    test('não dispara para 401 do login (senha incorreta)', () {
      RelatorioApiService.definirToken('token-valido');

      RelatorioApiService.notificarRespostaNaoAutorizada(401, endpoint: '/api/usuarios/login');

      expect(disparos, 0);
      expect(RelatorioApiService.estaAutenticado, isTrue);
    });

    test('não dispara sem sessão ativa', () {
      RelatorioApiService.notificarRespostaNaoAutorizada(401, endpoint: '/api/dashboard/filtros');

      expect(disparos, 0);
    });

    test('não dispara para outros códigos de status', () {
      RelatorioApiService.definirToken('token-valido');

      for (final status in [200, 400, 403, 404, 422, 500, 503]) {
        RelatorioApiService.notificarRespostaNaoAutorizada(status, endpoint: '/api/dashboard/filtros');
      }

      expect(disparos, 0);
      expect(RelatorioApiService.estaAutenticado, isTrue);
    });

    test('várias respostas 401 seguidas disparam uma única vez', () {
      RelatorioApiService.definirToken('token-expirado');

      RelatorioApiService.notificarRespostaNaoAutorizada(401, endpoint: '/api/dashboard/filtros');
      RelatorioApiService.notificarRespostaNaoAutorizada(401, endpoint: '/api/dashboard/horarios');
      RelatorioApiService.notificarRespostaNaoAutorizada(401);

      expect(disparos, 1);
    });
  });

  test('uma requisição recusada com 401 encerra a sessão e propaga o erro', () async {
    RelatorioApiService.definirToken('token-expirado');
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer token-expirado');
      return http.Response(
        jsonEncode({'detail': 'Token expirado. Faça login novamente.'}),
        401,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    Object? erro;
    try {
      await RelatorioApiService.gerarRelatorioConsolidado(client: client);
    } catch (e) {
      erro = e;
    }

    expect(erro, isA<RelatorioApiException>());
    expect((erro as RelatorioApiException).statusCode, 401);
    expect(disparos, 1);
    expect(RelatorioApiService.estaAutenticado, isFalse);
  });
}
