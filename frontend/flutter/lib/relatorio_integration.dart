/// ============================================================================
/// MÓDULO ABSTRATO DE INTEGRAÇÃO DE RELATÓRIOS • SEMOB-SCS
/// ============================================================================
///
/// Este módulo é 100% desacoplado de widgets visuais (`Material`/`Cupertino`) e
/// entrega os DTOs, contratos e o controller reativo (`ChangeNotifier`) prontos
/// para serem acoplados ao futuro botão "Gerar Relatório" na interface.
///
/// ### GUIA RÁPIDO DE ACOPLAMENTO (1 LINHA NO BOTÃO DA UI)
///
/// ```dart
/// // 1. No State da página (já instanciado em `_DashboardPageState` como `relatorioController`):
/// final relatorioController = RelatorioIntegrationController(
///   onSuccess: (relatorio) => debugPrint(relatorio.toResumoExecutivoTexto()),
///   onError: (erro) => debugPrint('Falha ao gerar relatório: $erro'),
/// );
///
/// // 2. No `onPressed` do futuro botão visual (acoplamento em 1 linha):
/// onPressed: () => relatorioController.acionarGeracaoRelatorio(
///   arquivosLocais: _dataset.arquivosHtmlCarregados,
///   filtros: RelatorioFiltroParams.fromDashboardState(
///     periodicidadeOuAgrupamento: _periodicidade,
///     dataInicio: _dataInicio,
///     dataFim: _dataFim,
///     linha: _linhaSelecionada,
///   ),
/// )
/// ```
library;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'folder_scanner_io.dart' if (dart.library.html) 'folder_scanner_web.dart';
import 'relatorio_api_service.dart';

export 'relatorio_api_service.dart'
    show
        AnomaliasRelatorio,
        DesvioOperacionalRelatorio,
        EstatisticasHistoricasRelatorio,
        FinanceiroKpiRelatorio,
        LinhaRankingRelatorio,
        PassageirosKpiRelatorio,
        PeriodoFiltroRelatorio,
        PeriodoTurnoFcvRelatorio,
        PontoSerieTemporalRelatorio,
        QuilometragemKpiRelatorio,
        RelatorioApiException,
        RelatorioApiService,
        RelatorioConsolidado,
        RelatorioUploadIntegrado,
        ResultadoArquivoLote,
        ResultadoProcessamentoHtml,
        ResumoOperacionalRelatorio,
        SerieTemporalRelatorio;

/// Parâmetros tipados de filtragem e tolerância estatística para geração do relatório.
class RelatorioFiltroParams {
  final String agrupamento;
  final String? dataInicio;
  final String? dataFim;
  final String? linha;
  final double toleranciaDesvioKmPct;
  final double limiarFcv;
  final double limiarKmImprodPct;

  const RelatorioFiltroParams({
    this.agrupamento = 'diario',
    this.dataInicio,
    this.dataFim,
    this.linha,
    this.toleranciaDesvioKmPct = 15.0,
    this.limiarFcv = 0.98,
    this.limiarKmImprodPct = 10.0,
  });

  /// Constrói os parâmetros diretamente a partir do estado de filtros do Dashboard.
  factory RelatorioFiltroParams.fromDashboardState({
    String? periodicidadeOuAgrupamento,
    DateTime? dataInicio,
    DateTime? dataFim,
    String? linha,
    double toleranciaDesvioKmPct = 15.0,
    double limiarFcv = 0.98,
    double limiarKmImprodPct = 10.0,
  }) {
    return RelatorioFiltroParams(
      agrupamento: normalizarAgrupamento(periodicidadeOuAgrupamento),
      dataInicio: dataInicio != null ? formatarDataIso(dataInicio) : null,
      dataFim: dataFim != null ? formatarDataIso(dataFim) : null,
      linha: normalizarLinha(linha),
      toleranciaDesvioKmPct: toleranciaDesvioKmPct,
      limiarFcv: limiarFcv,
      limiarKmImprodPct: limiarKmImprodPct,
    );
  }

  /// Desserialização segura com valores padrão caso campos venham `null` ou ausentes.
  factory RelatorioFiltroParams.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return RelatorioFiltroParams(
      agrupamento: normalizarAgrupamento(map['agrupamento']?.toString()),
      dataInicio: _stringOuNull(map['data_inicio']),
      dataFim: _stringOuNull(map['data_fim']),
      linha: normalizarLinha(map['linha']?.toString()),
      toleranciaDesvioKmPct: _doubleSeguro(map['tolerancia_desvio_km_pct'], padrao: 15.0),
      limiarFcv: _doubleSeguro(map['limiar_fcv'], padrao: 0.98),
      limiarKmImprodPct: _doubleSeguro(map['limiar_km_improd_pct'], padrao: 10.0),
    );
  }

  Map<String, dynamic> toJson() => {
        'agrupamento': normalizarAgrupamento(agrupamento),
        'data_inicio': dataInicio,
        'data_fim': dataFim,
        'linha': normalizarLinha(linha),
        'tolerancia_desvio_km_pct': toleranciaDesvioKmPct,
        'limiar_fcv': limiarFcv,
        'limiar_km_improd_pct': limiarKmImprodPct,
      };

  Map<String, String> toQueryParameters() {
    final params = <String, String>{
      'agrupamento': normalizarAgrupamento(agrupamento),
      'tolerancia_desvio_km_pct': toleranciaDesvioKmPct.toString(),
      'limiar_fcv': limiarFcv.toString(),
      'limiar_km_improd_pct': limiarKmImprodPct.toString(),
    };
    if (dataInicio != null && dataInicio!.trim().isNotEmpty) {
      params['data_inicio'] = dataInicio!.trim();
    }
    if (dataFim != null && dataFim!.trim().isNotEmpty) {
      params['data_fim'] = dataFim!.trim();
    }
    final linhaNormalizada = normalizarLinha(linha);
    if (linhaNormalizada != null) {
      params['linha'] = linhaNormalizada;
    }
    return params;
  }

  RelatorioFiltroParams copyWith({
    String? agrupamento,
    String? dataInicio,
    String? dataFim,
    String? linha,
    double? toleranciaDesvioKmPct,
    double? limiarFcv,
    double? limiarKmImprodPct,
  }) {
    return RelatorioFiltroParams(
      agrupamento: agrupamento ?? this.agrupamento,
      dataInicio: dataInicio ?? this.dataInicio,
      dataFim: dataFim ?? this.dataFim,
      linha: linha ?? this.linha,
      toleranciaDesvioKmPct: toleranciaDesvioKmPct ?? this.toleranciaDesvioKmPct,
      limiarFcv: limiarFcv ?? this.limiarFcv,
      limiarKmImprodPct: limiarKmImprodPct ?? this.limiarKmImprodPct,
    );
  }

  static String normalizarAgrupamento(String? valor) {
    final limpo = (valor ?? '').trim().toLowerCase();
    if (limpo == 'mensal' || limpo.contains('mês') || limpo.contains('mes')) {
      return 'mensal';
    }
    if (limpo == 'semanal' || limpo.contains('seman')) {
      return 'semanal';
    }
    return 'diario';
  }

  static String? normalizarLinha(String? linha) {
    if (linha == null) return null;
    final limpa = linha.trim();
    if (limpa.isEmpty || limpa.toLowerCase() == 'todas') return null;
    return limpa;
  }

  static String formatarDataIso(DateTime data) =>
      '${data.year.toString().padLeft(4, '0')}-'
      '${data.month.toString().padLeft(2, '0')}-'
      '${data.day.toString().padLeft(2, '0')}';
}

/// Modelo/DTO consolidado do relatório operacional, com `fromJson` e `toJson`
/// seguros (com valores padrão caso qualquer campo venha `null` do backend)
/// e formatação executiva via `.toResumoExecutivoTexto()`.
class RelatorioConsolidadoModel extends RelatorioConsolidado {
  const RelatorioConsolidadoModel({
    required super.geradoEm,
    required super.periodo,
    required super.resumoOperacional,
    required super.estatisticasHistoricas,
    required super.serieTemporal,
    required super.rankingLinhas,
    required super.anomalias,
    required super.rawJson,
  });

  /// Converte uma instância base `RelatorioConsolidado` em `RelatorioConsolidadoModel`.
  factory RelatorioConsolidadoModel.fromBase(RelatorioConsolidado base) {
    if (base is RelatorioConsolidadoModel) return base;
    return RelatorioConsolidadoModel(
      geradoEm: base.geradoEm,
      periodo: base.periodo,
      resumoOperacional: base.resumoOperacional,
      estatisticasHistoricas: base.estatisticasHistoricas,
      serieTemporal: base.serieTemporal,
      rankingLinhas: base.rankingLinhas,
      anomalias: base.anomalias,
      rawJson: base.rawJson,
    );
  }

  /// Desserialização tolerante a `null`: garante valores padrão seguros para todos
  /// os 5 pilares da SEMOB-SCS, estatísticas históricas, séries temporais e anomalias.
  factory RelatorioConsolidadoModel.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};

    final listaRanking = <LinhaRankingRelatorio>[];
    final rawRanking = map['ranking_linhas'];
    if (rawRanking is List) {
      for (final item in rawRanking) {
        if (item is Map) {
          listaRanking.add(LinhaRankingRelatorio.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final anomaliasMap = _mapaSeguro(map['anomalias']);
    final anomaliasParsed = AnomaliasRelatorio.fromJson(anomaliasMap);
    final estatisticasMap = map['estatisticas_historicas'] is Map
        ? _mapaSeguro(map['estatisticas_historicas'])
        : anomaliasParsed.estatisticasHistoricas.toJson();

    return RelatorioConsolidadoModel(
      geradoEm: _stringOuNull(map['gerado_em']) ?? '',
      periodo: PeriodoFiltroRelatorio.fromJson(_mapaSeguro(map['periodo'])),
      resumoOperacional: ResumoOperacionalRelatorio.fromJson(
        _mapaSeguro(map['resumo_operacional']),
      ),
      estatisticasHistoricas: EstatisticasHistoricasRelatorio.fromJson(estatisticasMap),
      serieTemporal: SerieTemporalRelatorio.fromJson(_mapaSeguro(map['serie_temporal'])),
      rankingLinhas: listaRanking,
      anomalias: anomaliasParsed,
      rawJson: Map<String, dynamic>.from(map),
    );
  }

  /// Gera o resumo executivo textual completo (Quilometragem, Viagens/FCV,
  /// Passageiros Pagantes/Gratuidades, Financeiro, Desvio Padrão, Ranking e Z-Score)
  /// pronto para exportação ou apresentação aos gestores e ao Prefeito.
  @override
  String toResumoExecutivoTexto() => RelatorioApiService.formatarResumoRelatorio(this);
}

/// Contrato abstrato da camada de integração de geração de relatórios.
abstract class IRelatorioIntegrationHandler implements Listenable {
  /// Indica se há uma operação de upload/geração de relatório em andamento.
  bool get carregando;

  /// Alias em inglês para `carregando`.
  bool get isLoading;

  /// Mensagem de erro da última operação (ou `null` quando não houve falha).
  String? get erro;

  /// Alias em inglês para `erro`.
  String? get errorMessage;

  /// Último relatório consolidado obtido do backend.
  RelatorioConsolidadoModel? get ultimoRelatorio;

  /// Alias em inglês para `ultimoRelatorio`.
  RelatorioConsolidadoModel? get data;

  /// Resultado detalhado do último lote de arquivos sincronizado com o backend.
  RelatorioUploadIntegrado? get ultimoResultadoUpload;

  /// Texto executivo formatado correspondente ao `ultimoRelatorio`.
  String? get ultimoResumoExecutivoTexto;

  /// Solicita a geração do relatório consolidado em `POST /api/dashboard/relatorio/gerar`
  /// (ou `GET /api/v1/dashboard/relatorio` quando `usarPost == false`).
  Future<RelatorioConsolidadoModel> gerarRelatorio({
    RelatorioFiltroParams? filtros,
    bool usarPost = true,
  });

  /// Envia os arquivos `.html`/`.htm` carregados localmente para
  /// `POST /api/dashboard/relatorio/upload-e-gerar` e retorna o relatório consolidado atualizado.
  Future<RelatorioConsolidadoModel> sincronizarArquivosEGerarRelatorio({
    required List<ArquivoLido> arquivos,
    RelatorioFiltroParams? filtros,
  });

  /// Método de alto nível pronto para ser conectado diretamente ao `onPressed` do futuro botão.
  /// Se `arquivosLocais` contiver relatórios `.html`, sincroniza o lote e gera o relatório;
  /// caso contrário, gera o relatório diretamente a partir dos dados já persistidos no MongoDB.
  Future<RelatorioConsolidadoModel?> acionarGeracaoRelatorio({
    List<ArquivoLido>? arquivosLocais,
    RelatorioFiltroParams? filtros,
    bool sincronizarArquivosQuandoDisponiveis = true,
    ValueChanged<RelatorioConsolidadoModel>? onSuccess,
    ValueChanged<String>? onError,
  });

  /// Limpa a mensagem de erro atual e notifica os ouvintes.
  void limparErro();

  /// Reinicia todos os estados (`carregando`, `erro`, `ultimoRelatorio`) do controller.
  void limparEstado();
}

/// Implementação padrão baseada em `ChangeNotifier` para gerenciar todo o ciclo
/// de vida da geração de relatórios sem acoplamento com widgets visuais.
class RelatorioIntegrationController extends ChangeNotifier
    implements IRelatorioIntegrationHandler {
  final http.Client? _httpClient;
  RelatorioFiltroParams _filtrosPadrao;
  ValueChanged<RelatorioConsolidadoModel>? onSuccess;
  ValueChanged<String>? onError;

  bool _carregando = false;
  String? _erro;
  RelatorioConsolidadoModel? _ultimoRelatorio;
  RelatorioUploadIntegrado? _ultimoResultadoUpload;

  RelatorioIntegrationController({
    http.Client? httpClient,
    RelatorioFiltroParams filtrosPadrao = const RelatorioFiltroParams(),
    this.onSuccess,
    this.onError,
  })  : _httpClient = httpClient,
        _filtrosPadrao = filtrosPadrao;

  @override
  bool get carregando => _carregando;

  @override
  bool get isLoading => _carregando;

  @override
  String? get erro => _erro;

  @override
  String? get errorMessage => _erro;

  @override
  RelatorioConsolidadoModel? get ultimoRelatorio => _ultimoRelatorio;

  @override
  RelatorioConsolidadoModel? get data => _ultimoRelatorio;

  @override
  RelatorioUploadIntegrado? get ultimoResultadoUpload => _ultimoResultadoUpload;

  @override
  String? get ultimoResumoExecutivoTexto => _ultimoRelatorio?.toResumoExecutivoTexto();

  RelatorioFiltroParams get filtrosPadrao => _filtrosPadrao;

  void atualizarFiltrosPadrao(RelatorioFiltroParams novosFiltros) {
    _filtrosPadrao = novosFiltros;
    notifyListeners();
  }

  @override
  Future<RelatorioConsolidadoModel> gerarRelatorio({
    RelatorioFiltroParams? filtros,
    bool usarPost = true,
  }) async {
    final params = filtros ?? _filtrosPadrao;
    _iniciarOperacao();

    try {
      final relatorioBase = await RelatorioApiService.gerarRelatorioConsolidado(
        agrupamento: RelatorioFiltroParams.normalizarAgrupamento(params.agrupamento),
        dataInicio: params.dataInicio,
        dataFim: params.dataFim,
        linha: RelatorioFiltroParams.normalizarLinha(params.linha),
        toleranciaDesvioKmPct: params.toleranciaDesvioKmPct,
        limiarFcv: params.limiarFcv,
        limiarKmImprodPct: params.limiarKmImprodPct,
        usarPost: usarPost,
        usarRotaV1: !usarPost,
        client: _httpClient,
      );

      final model = RelatorioConsolidadoModel.fromBase(relatorioBase);
      _concluirComSucesso(model);
      return model;
    } catch (e) {
      final mensagem = _normalizarMensagemErro(e);
      _concluirComErro(mensagem);
      rethrow;
    }
  }

  @override
  Future<RelatorioConsolidadoModel> sincronizarArquivosEGerarRelatorio({
    required List<ArquivoLido> arquivos,
    RelatorioFiltroParams? filtros,
  }) async {
    final params = filtros ?? _filtrosPadrao;
    _iniciarOperacao();

    try {
      final resultadoLote = await RelatorioApiService.enviarLoteArquivosEGerarRelatorio(
        arquivos: arquivos,
        agrupamento: RelatorioFiltroParams.normalizarAgrupamento(params.agrupamento),
        dataInicio: params.dataInicio,
        dataFim: params.dataFim,
        linha: RelatorioFiltroParams.normalizarLinha(params.linha),
        toleranciaDesvioKmPct: params.toleranciaDesvioKmPct,
        limiarFcv: params.limiarFcv,
        limiarKmImprodPct: params.limiarKmImprodPct,
        client: _httpClient,
      );

      _ultimoResultadoUpload = resultadoLote;
      final model = RelatorioConsolidadoModel.fromBase(resultadoLote.relatorio);
      _concluirComSucesso(model);
      return model;
    } catch (e) {
      final mensagem = _normalizarMensagemErro(e);
      _concluirComErro(mensagem);
      rethrow;
    }
  }

  @override
  Future<RelatorioConsolidadoModel?> acionarGeracaoRelatorio({
    List<ArquivoLido>? arquivosLocais,
    RelatorioFiltroParams? filtros,
    bool sincronizarArquivosQuandoDisponiveis = true,
    ValueChanged<RelatorioConsolidadoModel>? onSuccess,
    ValueChanged<String>? onError,
  }) async {
    if (_carregando) return _ultimoRelatorio;

    try {
      final RelatorioConsolidadoModel relatorio;
      if (sincronizarArquivosQuandoDisponiveis &&
          arquivosLocais != null &&
          arquivosLocais.isNotEmpty) {
        relatorio = await sincronizarArquivosEGerarRelatorio(
          arquivos: arquivosLocais,
          filtros: filtros,
        );
      } else {
        relatorio = await gerarRelatorio(filtros: filtros);
      }
      onSuccess?.call(relatorio);
      return relatorio;
    } catch (e) {
      final mensagem = _erro ?? _normalizarMensagemErro(e);
      onError?.call(mensagem);
      return null;
    }
  }

  @override
  void limparErro() {
    if (_erro != null) {
      _erro = null;
      notifyListeners();
    }
  }

  @override
  void limparEstado() {
    _carregando = false;
    _erro = null;
    _ultimoRelatorio = null;
    _ultimoResultadoUpload = null;
    notifyListeners();
  }

  void _iniciarOperacao() {
    _carregando = true;
    _erro = null;
    notifyListeners();
  }

  void _concluirComSucesso(RelatorioConsolidadoModel model) {
    _carregando = false;
    _erro = null;
    _ultimoRelatorio = model;
    notifyListeners();
    onSuccess?.call(model);
  }

  void _concluirComErro(String mensagem) {
    _carregando = false;
    _erro = mensagem;
    notifyListeners();
    onError?.call(mensagem);
  }

  static String _normalizarMensagemErro(Object erro) {
    if (erro is RelatorioApiException) {
      return erro.message;
    }
    return erro.toString();
  }
}

Map<String, dynamic> _mapaSeguro(dynamic valor) {
  if (valor is Map<String, dynamic>) return valor;
  if (valor is Map) return Map<String, dynamic>.from(valor);
  return <String, dynamic>{};
}

String? _stringOuNull(dynamic valor) {
  if (valor == null) return null;
  final texto = valor.toString().trim();
  return texto.isEmpty ? null : texto;
}

double _doubleSeguro(dynamic valor, {required double padrao}) {
  if (valor == null) return padrao;
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor.toString()) ?? padrao;
}
