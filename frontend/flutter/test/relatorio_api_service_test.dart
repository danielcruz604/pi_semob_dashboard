import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:semob_dashboard/local_data_loader.dart';

Map<String, dynamic> _mockRelatorioJson() => {
      'gerado_em': '2026-10-21T12:00:00Z',
      'periodo': {
        'data_inicio': '2026-08-01',
        'data_fim': '2026-08-31',
        'agrupamento': 'diario',
        'linha': null,
      },
      'resumo_operacional': {
        'periodo': {
          'data_inicio': '2026-08-01',
          'data_fim': '2026-08-31',
          'agrupamento': null,
          'linha': null,
        },
        'quilometragem': {
          'km_total': 19884.45,
          'km_produtivo': 18500.0,
          'km_improdutivo': 1384.45,
          'taxa_improdutiva_percentual': 6.96,
          'media_diaria_km': 6628.15,
        },
        'viagens': {
          'programadas': 2724,
          'realizadas': 2714,
          'diferenca': 10,
          'fcv_medio': 0.9963,
          'por_periodo': {
            'manha': {'prog': 1000, 'real': 995, 'fcv': 0.995},
          },
        },
        'passageiros': {
          'pagantes': 10344,
          'catraca': 9168,
          'antecipados': 1176,
          'nao_pagantes': 18700,
          'total_geral': 29044,
          'percentual_gratuidade': 64.39,
        },
        'financeiro': {
          'total_vendas': 4900.0,
          'total_utilizacao': 4850.0,
          'creditos_transferidos_cartoes': 2500.0,
          'credito_circulante_acumulado': 12000.0,
          'saldo_final_recente': 35000.0,
          'receita_por_km': 0.25,
        },
      },
      'estatisticas_historicas': {
        'media_km': 6628.15,
        'desvio_padrao_km': 950.25,
        'media_viagens_realizadas': 904.67,
        'desvio_padrao_viagens': 120.5,
        'media_fcv': 0.9963,
        'desvio_padrao_fcv': 0.004,
        'media_tarifa_efetiva': 4.68,
        'desvio_padrao_tarifa_efetiva': 0.12,
      },
      'serie_temporal': {
        'periodo': {
          'data_inicio': '2026-08-01',
          'data_fim': '2026-08-31',
          'agrupamento': 'diario',
          'linha': null,
        },
        'total_pontos': 1,
        'serie': [
          {
            'referencia': '2026-08-01',
            'km_total': 6889.4,
            'km_produtivo': 6500.0,
            'km_improdutivo': 389.4,
            'viagens_programadas': 924,
            'viagens_realizadas': 920,
            'fcv': 0.9957,
            'passageiros_pagantes': 3500,
            'passageiros_nao_pagantes': 6000,
            'total_passageiros': 9500,
            'total_vendas': 1600.0,
            'total_utilizacao': 1580.0,
            'credito_circulante': 4000.0,
            'receita_por_km': 0.23,
          },
        ],
      },
      'ranking_linhas': [
        {
          'linha': '01',
          'km_total': 2072.6,
          'viagens': 260,
          'media_km_por_viagem': 7.97,
          'participacao_km_percentual': 52.4,
        },
      ],
      'anomalias': {
        'periodo': {
          'data_inicio': '2026-08-01',
          'data_fim': '2026-08-31',
          'agrupamento': null,
          'linha': null,
        },
        'parametros_tolerancia': {
          'tolerancia_desvio_km_pct': 15.0,
          'limiar_fcv': 0.98,
          'limiar_km_improd_pct': 10.0,
        },
        'estatisticas_historicas': {
          'media_km': 6628.15,
          'desvio_padrao_km': 950.25,
          'media_viagens_realizadas': 904.67,
          'desvio_padrao_viagens': 120.5,
          'media_fcv': 0.9963,
          'desvio_padrao_fcv': 0.004,
          'media_tarifa_efetiva': 4.68,
          'desvio_padrao_tarifa_efetiva': 0.12,
        },
        'total_ocorrencias_viagens': 2,
        'ocorrencias_por_classificacao': {'NaoRealizada': 2},
        'ocorrencias': [
          {'data': '2026-08-01', 'linha': '01', 'classificacao': 'NaoRealizada'},
        ],
        'total_desvios_operacionais': 1,
        'desvios_operacionais': [
          {
            'data': '2026-08-01',
            'tipo': 'desvio_quilometragem_media',
            'indicador': 'kmTotal',
            'valor_observado': 8200.0,
            'valor_referencia': 6628.15,
            'desvio_padrao_referencia': 950.25,
            'z_score': 1.6541,
            'desvio_percentual': 23.71,
            'descricao': 'Quilometragem do dia desviou 23.71% da média.',
          },
        ],
      },
    };

void main() {
  tearDown(() {
    RelatorioApiService.limparSessao();
    RelatorioApiService.configurarBaseUrl(null);
  });

  test('Converte e formata RelatorioConsolidado com todos os pilares e Z-Score', () {
    final relatorio = RelatorioConsolidado.fromJson(_mockRelatorioJson());

    expect(relatorio.resumoOperacional.quilometragem.kmTotal, closeTo(19884.45, 0.01));
    expect(relatorio.resumoOperacional.viagens.programadas, 2724);
    expect(relatorio.estatisticasHistoricas.desvioPadraoKm, closeTo(950.25, 0.01));
    expect(relatorio.rankingLinhas.first.linha, '01');
    expect(relatorio.anomalias.desviosOperacionais.first.zScore, closeTo(1.6541, 0.001));

    final texto = relatorio.toResumoExecutivoTexto();
    expect(texto, contains('RELATÓRIO OPERACIONAL CONSOLIDADO • SEMOB'));
    expect(texto, contains('19884.45 km'));
    expect(texto, contains('Z-Score=1.65'));
  });

  test('Envia Authorization Bearer token e filtros ao gerar relatorio consolidado', () async {
    RelatorioApiService.definirToken('jwt-token-teste');
    Uri? uriRecebida;
    String? authHeader;

    final mockClient = MockClient((http.Request req) async {
      uriRecebida = req.url;
      authHeader = req.headers['Authorization'];
      return http.Response(
        jsonEncode(_mockRelatorioJson()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final relatorio = await RelatorioApiService.gerarRelatorioConsolidado(
      agrupamento: 'mensal',
      dataInicio: '2026-08-01',
      dataFim: '2026-08-31',
      linha: '01',
      client: mockClient,
    );

    expect(authHeader, 'Bearer jwt-token-teste');
    expect(uriRecebida?.path, '/api/dashboard/relatorio');
    expect(uriRecebida?.queryParameters['agrupamento'], 'mensal');
    expect(uriRecebida?.queryParameters['linha'], '01');
    expect(relatorio.serieTemporal.totalPontos, 1);
  });

  test('Envia lote de arquivos HTML e retorna RelatorioUploadIntegrado', () async {
    final mockClient = MockClient((http.Request req) async {
      expect(req.url.path, '/api/dashboard/relatorio/upload-e-gerar');
      return http.Response(
        jsonEncode({
          'total_arquivos_recebidos': 1,
          'total_arquivos_persistidos': 1,
          'total_arquivos_apenas_processados': 0,
          'total_arquivos_com_erro': 0,
          'arquivos': [
            {
              'arquivo': 'Mensal_202608.html',
              'status': 'persistido',
              'tipo_relatorio': 'mensal',
              'colecao': 'viagensSistema',
              'total_registros_validos': 3,
              'documentos_afetados': 3,
              'detalhe_erro': null,
            },
          ],
          'relatorio': _mockRelatorioJson(),
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final resultado = await RelatorioApiService.enviarLoteArquivosEGerarRelatorio(
      arquivos: [
        ArquivoLido(
          nome: 'Mensal_202608.html',
          caminho: 'Mensal_202608.html',
          bytes: utf8.encode('<table class="data"></table>'),
        ),
      ],
      client: mockClient,
    );

    expect(resultado.totalArquivosPersistidos, 1);
    expect(resultado.arquivos.first.colecao, 'viagensSistema');
    expect(resultado.relatorio.resumoOperacional.viagens.realizadas, 2714);
  });

  test('RelatorioConsolidadoModel.fromJson aplica valores padrao seguros quando campos sao null', () {
    final model = RelatorioConsolidadoModel.fromJson(const <String, dynamic>{
      'gerado_em': null,
      'periodo': null,
      'resumo_operacional': null,
      'estatisticas_historicas': null,
      'serie_temporal': null,
      'ranking_linhas': null,
      'anomalias': null,
    });

    expect(model.geradoEm, isEmpty);
    expect(model.resumoOperacional.quilometragem.kmTotal, 0.0);
    expect(model.resumoOperacional.viagens.programadas, 0);
    expect(model.resumoOperacional.passageiros.pagantes, 0);
    expect(model.resumoOperacional.financeiro.totalVendas, 0.0);
    expect(model.serieTemporal.totalPontos, 0);
    expect(model.rankingLinhas, isEmpty);
    expect(model.anomalias.totalDesviosOperacionais, 0);
    expect(model.toResumoExecutivoTexto(), contains('RELATÓRIO OPERACIONAL CONSOLIDADO'));
  });

  test('RelatorioIntegrationController gerencia estados carregando, ultimoRelatorio e callbacks', () async {
    RelatorioConsolidadoModel? callbackRelatorio;
    String? callbackErro;

    final mockClient = MockClient((http.Request req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/api/dashboard/relatorio/gerar');
      return http.Response(
        jsonEncode(_mockRelatorioJson()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final controller = RelatorioIntegrationController(
      httpClient: mockClient,
      onSuccess: (rel) => callbackRelatorio = rel,
      onError: (err) => callbackErro = err,
    );

    expect(controller.carregando, isFalse);
    expect(controller.isLoading, isFalse);
    expect(controller.ultimoRelatorio, isNull);
    expect(controller.data, isNull);

    final resultado = await controller.acionarGeracaoRelatorio(
      filtros: RelatorioFiltroParams.fromDashboardState(
        periodicidadeOuAgrupamento: 'Mensal',
        dataInicio: DateTime(2026, 8, 1),
        dataFim: DateTime(2026, 8, 31),
        linha: 'Todas',
      ),
    );

    expect(resultado, isNotNull);
    expect(controller.carregando, isFalse);
    expect(controller.erro, isNull);
    expect(controller.errorMessage, isNull);
    expect(controller.ultimoRelatorio, same(resultado));
    expect(controller.data, same(resultado));
    expect(callbackRelatorio, same(resultado));
    expect(callbackErro, isNull);
    expect(controller.ultimoResumoExecutivoTexto, contains('19884.45 km'));
  });

  test('RelatorioIntegrationController captura erro e aciona onError sem lancar excecao no botao', () async {
    String? erroCapturado;

    final mockClient = MockClient((http.Request req) async {
      return http.Response(
        jsonEncode({'detail': 'Banco de dados indisponível no momento.'}),
        503,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final controller = RelatorioIntegrationController(httpClient: mockClient);
    final resultado = await controller.acionarGeracaoRelatorio(
      onError: (msg) => erroCapturado = msg,
    );

    expect(resultado, isNull);
    expect(controller.isLoading, isFalse);
    expect(controller.errorMessage, 'Banco de dados indisponível no momento.');
    expect(erroCapturado, 'Banco de dados indisponível no momento.');
  });
}
