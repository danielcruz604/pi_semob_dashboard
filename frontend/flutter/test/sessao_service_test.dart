import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:semob_dashboard/relatorio_api_service.dart';
import 'package:semob_dashboard/sessao_service.dart';

const _usuario = {
  'id': '603d2b4f9f1b2c3d4e5f6a7b',
  'nome': 'Diretoria Geral',
  'email': 'gestor@semob.sp.gov.br',
  'papel': 'gestor',
};

http.Response _json(Object corpo, int status) => http.Response(
      jsonEncode(corpo),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

MockClient _loginComSucesso() => MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/usuarios/login');
      final corpo = jsonDecode(request.body) as Map<String, dynamic>;
      expect(corpo['email'], 'gestor@semob.sp.gov.br');
      expect(corpo['senha'], 'semob2026');
      return _json({
        'access_token': 'token-valido',
        'token_type': 'bearer',
        'usuario': _usuario,
      }, 200);
    });

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RelatorioApiService.limparSessao();
    RelatorioApiService.configurarBaseUrl('http://api.teste');
  });

  tearDown(() {
    RelatorioApiService.limparSessao();
    RelatorioApiService.configurarBaseUrl(null);
  });

  group('SessaoService.entrar', () {
    test('com sucesso e "lembrar" marcado, salva token e usuário no dispositivo', () async {
      final usuario = await SessaoService.entrar(
        email: 'gestor@semob.sp.gov.br',
        senha: 'semob2026',
        lembrar: true,
        client: _loginComSucesso(),
      );

      expect(usuario?['nome'], 'Diretoria Geral');
      expect(RelatorioApiService.estaAutenticado, isTrue);
      expect(RelatorioApiService.tokenJwt, 'token-valido');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SessaoService.chaveToken), 'token-valido');
      final salvo = jsonDecode(prefs.getString(SessaoService.chaveUsuario)!);
      expect(salvo['email'], 'gestor@semob.sp.gov.br');
    });

    test('com sucesso e "lembrar" desmarcado, mantém a sessão só em memória', () async {
      SharedPreferences.setMockInitialValues({SessaoService.chaveToken: 'token-antigo'});

      await SessaoService.entrar(
        email: 'gestor@semob.sp.gov.br',
        senha: 'semob2026',
        lembrar: false,
        client: _loginComSucesso(),
      );

      expect(RelatorioApiService.estaAutenticado, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SessaoService.chaveToken), isNull);
      expect(prefs.getString(SessaoService.chaveUsuario), isNull);
    });

    test('com senha incorreta, lança erro 401 e não autentica', () async {
      final client = MockClient(
        (_) async => _json({'detail': 'E-mail ou senha incorretos.'}, 401),
      );

      Object? erro;
      try {
        await SessaoService.entrar(
          email: 'gestor@semob.sp.gov.br',
          senha: 'errada',
          lembrar: true,
          client: client,
        );
      } catch (e) {
        erro = e;
      }

      expect(erro, isA<RelatorioApiException>());
      expect((erro as RelatorioApiException).statusCode, 401);
      expect(SessaoService.mensagemDeErro(erro), 'E-mail ou senha incorretos.');
      expect(RelatorioApiService.estaAutenticado, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SessaoService.chaveToken), isNull);
    });

    test('com servidor fora do ar, informa falha de conexão', () async {
      final client = MockClient((_) async => throw http.ClientException('Connection refused'));

      Object? erro;
      try {
        await SessaoService.entrar(
          email: 'gestor@semob.sp.gov.br',
          senha: 'semob2026',
          lembrar: true,
          client: client,
        );
      } catch (e) {
        erro = e;
      }

      expect(erro, isA<RelatorioApiException>());
      expect((erro as RelatorioApiException).statusCode, isNull);
      expect(SessaoService.mensagemDeErro(erro), contains('Não foi possível conectar ao servidor'));
      expect(RelatorioApiService.estaAutenticado, isFalse);
    });
  });

  group('SessaoService.restaurar', () {
    test('sem token salvo, retorna semSessao', () async {
      final resultado = await SessaoService.restaurar(
        client: MockClient((_) async => fail('não deveria chamar a API')),
      );
      expect(resultado, ResultadoRestauracao.semSessao);
      expect(RelatorioApiService.estaAutenticado, isFalse);
    });

    test('com token válido, valida em /perfil e restaura a sessão', () async {
      SharedPreferences.setMockInitialValues({
        SessaoService.chaveToken: 'token-salvo',
        SessaoService.chaveUsuario: jsonEncode(_usuario),
      });
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/usuarios/perfil');
        expect(request.headers['Authorization'], 'Bearer token-salvo');
        return _json({'mensagem': 'ok', 'dados_do_usuario': {}}, 200);
      });

      final resultado = await SessaoService.restaurar(client: client);

      expect(resultado, ResultadoRestauracao.restaurada);
      expect(RelatorioApiService.tokenJwt, 'token-salvo');
      expect(RelatorioApiService.usuarioLogado?['nome'], 'Diretoria Geral');
      expect(
        RelatorioApiService.montarHeaders()['Authorization'],
        'Bearer token-salvo',
      );
    });

    test('com token expirado, retorna expirada e apaga a sessão salva', () async {
      SharedPreferences.setMockInitialValues({
        SessaoService.chaveToken: 'token-expirado',
        SessaoService.chaveUsuario: jsonEncode(_usuario),
      });
      final client = MockClient(
        (_) async => _json({'detail': 'Token expirado. Faça login novamente.'}, 401),
      );

      final resultado = await SessaoService.restaurar(client: client);

      expect(resultado, ResultadoRestauracao.expirada);
      expect(RelatorioApiService.estaAutenticado, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SessaoService.chaveToken), isNull);
      expect(prefs.getString(SessaoService.chaveUsuario), isNull);
    });

    test('com servidor fora do ar, não autentica mas mantém o token salvo', () async {
      SharedPreferences.setMockInitialValues({SessaoService.chaveToken: 'token-salvo'});
      final client = MockClient((_) async => throw http.ClientException('Connection refused'));

      final resultado = await SessaoService.restaurar(client: client);

      expect(resultado, ResultadoRestauracao.servidorIndisponivel);
      expect(RelatorioApiService.estaAutenticado, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SessaoService.chaveToken), 'token-salvo');
    });
  });

  test('SessaoService.sair limpa a memória e o dispositivo', () async {
    await SessaoService.entrar(
      email: 'gestor@semob.sp.gov.br',
      senha: 'semob2026',
      lembrar: true,
      client: _loginComSucesso(),
    );

    await SessaoService.sair();

    expect(RelatorioApiService.estaAutenticado, isFalse);
    expect(RelatorioApiService.usuarioLogado, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SessaoService.chaveToken), isNull);
    expect(prefs.getString(SessaoService.chaveUsuario), isNull);
  });
}
