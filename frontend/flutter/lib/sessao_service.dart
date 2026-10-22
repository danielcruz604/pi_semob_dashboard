import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'relatorio_api_service.dart';

/// Resultado da tentativa de restaurar uma sessão salva no dispositivo.
enum ResultadoRestauracao {
  /// Token salvo e aceito pelo backend: o usuário pode ir direto ao dashboard.
  restaurada,

  /// Não havia sessão salva neste dispositivo.
  semSessao,

  /// Havia token salvo, mas o backend o rejeitou (expirado ou inválido).
  expirada,

  /// Não foi possível falar com o backend para validar o token.
  servidorIndisponivel,
}

/// Gerencia o ciclo de vida da sessão do operador: login, persistência
/// opcional do token JWT ("Lembrar neste dispositivo"), restauração ao abrir
/// o app e logout.
///
/// O token em memória continua sendo mantido pelo [RelatorioApiService], que
/// já o injeta no cabeçalho `Authorization` das requisições.
class SessaoService {
  static const String chaveToken = 'semob.sessao.token';
  static const String chaveUsuario = 'semob.sessao.usuario';

  static const String _endpointPerfil = '/api/usuarios/perfil';

  /// Autentica no backend e, se [lembrar] for verdadeiro, salva a sessão no
  /// dispositivo. Propaga [RelatorioApiException] em caso de falha.
  static Future<Map<String, dynamic>?> entrar({
    required String email,
    required String senha,
    required bool lembrar,
    http.Client? client,
  }) async {
    await RelatorioApiService.autenticarUsuario(
      email: email,
      senha: senha,
      client: client,
    );

    final prefs = await SharedPreferences.getInstance();
    if (lembrar && RelatorioApiService.estaAutenticado) {
      await prefs.setString(chaveToken, RelatorioApiService.tokenJwt!);
      final usuario = RelatorioApiService.usuarioLogado;
      if (usuario != null) {
        await prefs.setString(chaveUsuario, jsonEncode(usuario));
      }
    } else {
      await _apagarDoDispositivo(prefs);
    }
    return RelatorioApiService.usuarioLogado;
  }

  /// Tenta restaurar a sessão salva, validando o token em `/api/usuarios/perfil`.
  static Future<ResultadoRestauracao> restaurar({http.Client? client}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(chaveToken);
    if (token == null || token.trim().isEmpty) {
      return ResultadoRestauracao.semSessao;
    }

    Map<String, dynamic>? usuario;
    final usuarioJson = prefs.getString(chaveUsuario);
    if (usuarioJson != null) {
      try {
        final decodificado = jsonDecode(usuarioJson);
        if (decodificado is Map) {
          usuario = Map<String, dynamic>.from(decodificado);
        }
      } catch (_) {
        usuario = null;
      }
    }

    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(
            Uri.parse('${RelatorioApiService.baseUrl}$_endpointPerfil'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        RelatorioApiService.definirToken(token, usuario: usuario);
        return ResultadoRestauracao.restaurada;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        await _apagarDoDispositivo(prefs);
        RelatorioApiService.limparSessao();
        return ResultadoRestauracao.expirada;
      }
      return ResultadoRestauracao.servidorIndisponivel;
    } catch (_) {
      // Mantém o token salvo: o servidor pode só estar fora do ar agora.
      return ResultadoRestauracao.servidorIndisponivel;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Encerra a sessão em memória e no dispositivo.
  static Future<void> sair() async {
    RelatorioApiService.limparSessao();
    final prefs = await SharedPreferences.getInstance();
    await _apagarDoDispositivo(prefs);
  }

  /// Converte uma falha de login em uma mensagem clara para o operador.
  static String mensagemDeErro(Object erro) {
    if (erro is RelatorioApiException) {
      final status = erro.statusCode;
      if (status == null) {
        return 'Não foi possível conectar ao servidor. '
            'Verifique sua conexão ou se a API está em execução.';
      }
      if (status == 401) {
        return 'E-mail ou senha incorretos.';
      }
      if (status == 422) {
        return 'Dados de login inválidos. Confira o e-mail informado.';
      }
      if (status >= 500) {
        return 'O servidor encontrou um erro. Tente novamente em instantes.';
      }
      return erro.message;
    }
    return 'Ocorreu um erro inesperado ao entrar. Tente novamente.';
  }

  static Future<void> _apagarDoDispositivo(SharedPreferences prefs) async {
    await prefs.remove(chaveToken);
    await prefs.remove(chaveUsuario);
  }
}
