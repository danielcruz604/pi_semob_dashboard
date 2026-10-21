import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'folder_scanner_io.dart' if (dart.library.html) 'folder_scanner_web.dart';

///Exceção padronizada para falhas de comunicação ou validação na API
class RelatorioApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? endpoint;

  const RelatorioApiException(
    this.message, {
    this.statusCode,
    this.endpoint,
  });

  @override
  String toString() => message;
}

class PeriodoFiltroRelatorio {
  final String? dataInicio;
  final String? dataFim;
  final String? agrupamento;
  final String? linha;

  const PeriodoFiltroRelatorio({
    this.dataInicio,
    this.dataFim,
    this.agrupamento,
    this.linha,
  });

  factory PeriodoFiltroRelatorio.fromJson(Map<String, dynamic> json) {
    return PeriodoFiltroRelatorio(
      dataInicio: json['data_inicio']?.toString(),
      dataFim: json['data_fim']?.toString(),
      agrupamento: json['agrupamento']?.toString(),
      linha: json['linha']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'data_inicio': dataInicio,
        'data_fim': dataFim,
        'agrupamento': agrupamento,
        'linha': linha,
      };
}

class QuilometragemKpiRelatorio {
  final double kmTotal;
  final double kmProdutivo;
  final double kmImprodutivo;
  final double taxaImprodutivaPercentual;
  final double mediaDiariaKm;

  const QuilometragemKpiRelatorio({
    required this.kmTotal,
    required this.kmProdutivo,
    required this.kmImprodutivo,
    required this.taxaImprodutivaPercentual,
    required this.mediaDiariaKm,
  });

  factory QuilometragemKpiRelatorio.fromJson(Map<String, dynamic> json) {
    return QuilometragemKpiRelatorio(
      kmTotal: _asDouble(json['km_total']),
      kmProdutivo: _asDouble(json['km_produtivo']),
      kmImprodutivo: _asDouble(json['km_improdutivo']),
      taxaImprodutivaPercentual: _asDouble(json['taxa_improdutiva_percentual']),
      mediaDiariaKm: _asDouble(json['media_diaria_km']),
    );
  }

  Map<String, dynamic> toJson() => {
        'km_total': kmTotal,
        'km_produtivo': kmProdutivo,
        'km_improdutivo': kmImprodutivo,
        'taxa_improdutiva_percentual': taxaImprodutivaPercentual,
        'media_diaria_km': mediaDiariaKm,
      };
}

class PeriodoTurnoFcvRelatorio {
  final int prog;
  final int real;
  final double fcv;

  const PeriodoTurnoFcvRelatorio({
    required this.prog,
    required this.real,
    required this.fcv,
  });

  factory PeriodoTurnoFcvRelatorio.fromJson(Map<String, dynamic> json) {
    return PeriodoTurnoFcvRelatorio(
      prog: _asInt(json['prog']),
      real: _asInt(json['real']),
      fcv: _asDouble(json['fcv']),
    );
  }

  Map<String, dynamic> toJson() => {
        'prog': prog,
        'real': real,
        'fcv': fcv,
      };
}

class ViagensKpiRelatorio {
  final int programadas;
  final int realizadas;
  final int diferenca;
  final double fcvMedio;
  final Map<String, PeriodoTurnoFcvRelatorio> porPeriodo;

  const ViagensKpiRelatorio({
    required this.programadas,
    required this.realizadas,
    required this.diferenca,
    required this.fcvMedio,
    required this.porPeriodo,
  });

  factory ViagensKpiRelatorio.fromJson(Map<String, dynamic> json) {
    final rawPeriodos = json['por_periodo'];
    final mapaPeriodos = <String, PeriodoTurnoFcvRelatorio>{};
    if (rawPeriodos is Map) {
      rawPeriodos.forEach((chave, valor) {
        if (valor is Map) {
          mapaPeriodos[chave.toString()] = PeriodoTurnoFcvRelatorio.fromJson(
            Map<String, dynamic>.from(valor),
          );
        }
      });
    }
    return ViagensKpiRelatorio(
      programadas: _asInt(json['programadas']),
      realizadas: _asInt(json['realizadas']),
      diferenca: _asInt(json['diferenca']),
      fcvMedio: _asDouble(json['fcv_medio']),
      porPeriodo: mapaPeriodos,
    );
  }

  Map<String, dynamic> toJson() => {
        'programadas': programadas,
        'realizadas': realizadas,
        'diferenca': diferenca,
        'fcv_medio': fcvMedio,
        'por_periodo': porPeriodo.map((k, v) => MapEntry(k, v.toJson())),
      };
}

class PassageirosKpiRelatorio {
  final int pagantes;
  final int catraca;
  final int antecipados;
  final int naoPagantes;
  final int totalGeral;
  final double percentualGratuidade;

  const PassageirosKpiRelatorio({
    required this.pagantes,
    required this.catraca,
    required this.antecipados,
    required this.naoPagantes,
    required this.totalGeral,
    required this.percentualGratuidade,
  });

  factory PassageirosKpiRelatorio.fromJson(Map<String, dynamic> json) {
    return PassageirosKpiRelatorio(
      pagantes: _asInt(json['pagantes']),
      catraca: _asInt(json['catraca']),
      antecipados: _asInt(json['antecipados']),
      naoPagantes: _asInt(json['nao_pagantes']),
      totalGeral: _asInt(json['total_geral']),
      percentualGratuidade: _asDouble(json['percentual_gratuidade']),
    );
  }

  Map<String, dynamic> toJson() => {
        'pagantes': pagantes,
        'catraca': catraca,
        'antecipados': antecipados,
        'nao_pagantes': naoPagantes,
        'total_geral': totalGeral,
        'percentual_gratuidade': percentualGratuidade,
      };
}

class FinanceiroKpiRelatorio {
  final double totalVendas;
  final double totalUtilizacao;
  final double creditosTransferidosCartoes;
  final double creditoCirculanteAcumulado;
  final double? saldoFinalRecente;
  final double receitaPorKm;

  const FinanceiroKpiRelatorio({
    required this.totalVendas,
    required this.totalUtilizacao,
    required this.creditosTransferidosCartoes,
    required this.creditoCirculanteAcumulado,
    required this.saldoFinalRecente,
    required this.receitaPorKm,
  });

  factory FinanceiroKpiRelatorio.fromJson(Map<String, dynamic> json) {
    return FinanceiroKpiRelatorio(
      totalVendas: _asDouble(json['total_vendas']),
      totalUtilizacao: _asDouble(json['total_utilizacao']),
      creditosTransferidosCartoes: _asDouble(json['creditos_transferidos_cartoes']),
      creditoCirculanteAcumulado: _asDouble(json['credito_circulante_acumulado']),
      saldoFinalRecente: _asNullableDouble(json['saldo_final_recente']),
      receitaPorKm: _asDouble(json['receita_por_km']),
    );
  }

  Map<String, dynamic> toJson() => {
        'total_vendas': totalVendas,
        'total_utilizacao': totalUtilizacao,
        'creditos_transferidos_cartoes': creditosTransferidosCartoes,
        'credito_circulante_acumulado': creditoCirculanteAcumulado,
        'saldo_final_recente': saldoFinalRecente,
        'receita_por_km': receitaPorKm,
      };
}

class ResumoOperacionalRelatorio {
  final PeriodoFiltroRelatorio periodo;
  final QuilometragemKpiRelatorio quilometragem;
  final ViagensKpiRelatorio viagens;
  final PassageirosKpiRelatorio passageiros;
  final FinanceiroKpiRelatorio financeiro;

  const ResumoOperacionalRelatorio({
    required this.periodo,
    required this.quilometragem,
    required this.viagens,
    required this.passageiros,
    required this.financeiro,
  });

  factory ResumoOperacionalRelatorio.fromJson(Map<String, dynamic> json) {
    return ResumoOperacionalRelatorio(
      periodo: PeriodoFiltroRelatorio.fromJson(_asMap(json['periodo'])),
      quilometragem: QuilometragemKpiRelatorio.fromJson(_asMap(json['quilometragem'])),
      viagens: ViagensKpiRelatorio.fromJson(_asMap(json['viagens'])),
      passageiros: PassageirosKpiRelatorio.fromJson(_asMap(json['passageiros'])),
      financeiro: FinanceiroKpiRelatorio.fromJson(_asMap(json['financeiro'])),
    );
  }

  Map<String, dynamic> toJson() => {
        'periodo': periodo.toJson(),
        'quilometragem': quilometragem.toJson(),
        'viagens': viagens.toJson(),
        'passageiros': passageiros.toJson(),
        'financeiro': financeiro.toJson(),
      };
}

class EstatisticasHistoricasRelatorio {
  final double mediaKm;
  final double desvioPadraoKm;
  final double mediaViagensRealizadas;
  final double desvioPadraoViagens;
  final double mediaFcv;
  final double desvioPadraoFcv;
  final double mediaTarifaEfetiva;
  final double desvioPadraoTarifaEfetiva;

  const EstatisticasHistoricasRelatorio({
    required this.mediaKm,
    required this.desvioPadraoKm,
    required this.mediaViagensRealizadas,
    required this.desvioPadraoViagens,
    required this.mediaFcv,
    required this.desvioPadraoFcv,
    required this.mediaTarifaEfetiva,
    required this.desvioPadraoTarifaEfetiva,
  });

  factory EstatisticasHistoricasRelatorio.fromJson(Map<String, dynamic> json) {
    return EstatisticasHistoricasRelatorio(
      mediaKm: _asDouble(json['media_km']),
      desvioPadraoKm: _asDouble(json['desvio_padrao_km']),
      mediaViagensRealizadas: _asDouble(json['media_viagens_realizadas']),
      desvioPadraoViagens: _asDouble(json['desvio_padrao_viagens']),
      mediaFcv: _asDouble(json['media_fcv']),
      desvioPadraoFcv: _asDouble(json['desvio_padrao_fcv']),
      mediaTarifaEfetiva: _asDouble(json['media_tarifa_efetiva']),
      desvioPadraoTarifaEfetiva: _asDouble(json['desvio_padrao_tarifa_efetiva']),
    );
  }

  Map<String, dynamic> toJson() => {
        'media_km': mediaKm,
        'desvio_padrao_km': desvioPadraoKm,
        'media_viagens_realizadas': mediaViagensRealizadas,
        'desvio_padrao_viagens': desvioPadraoViagens,
        'media_fcv': mediaFcv,
        'desvio_padrao_fcv': desvioPadraoFcv,
        'media_tarifa_efetiva': mediaTarifaEfetiva,
        'desvio_padrao_tarifa_efetiva': desvioPadraoTarifaEfetiva,
      };
}

class PontoSerieTemporalRelatorio {
  final String referencia;
  final double kmTotal;
  final double kmProdutivo;
  final double kmImprodutivo;
  final int viagensProgramadas;
  final int viagensRealizadas;
  final double fcv;
  final int passageirosPagantes;
  final int passageirosNaoPagantes;
  final int totalPassageiros;
  final double totalVendas;
  final double totalUtilizacao;
  final double creditoCirculante;
  final double receitaPorKm;

  const PontoSerieTemporalRelatorio({
    required this.referencia,
    required this.kmTotal,
    required this.kmProdutivo,
    required this.kmImprodutivo,
    required this.viagensProgramadas,
    required this.viagensRealizadas,
    required this.fcv,
    required this.passageirosPagantes,
    required this.passageirosNaoPagantes,
    required this.totalPassageiros,
    required this.totalVendas,
    required this.totalUtilizacao,
    required this.creditoCirculante,
    required this.receitaPorKm,
  });

  factory PontoSerieTemporalRelatorio.fromJson(Map<String, dynamic> json) {
    return PontoSerieTemporalRelatorio(
      referencia: json['referencia']?.toString() ?? '',
      kmTotal: _asDouble(json['km_total']),
      kmProdutivo: _asDouble(json['km_produtivo']),
      kmImprodutivo: _asDouble(json['km_improdutivo']),
      viagensProgramadas: _asInt(json['viagens_programadas']),
      viagensRealizadas: _asInt(json['viagens_realizadas']),
      fcv: _asDouble(json['fcv']),
      passageirosPagantes: _asInt(json['passageiros_pagantes']),
      passageirosNaoPagantes: _asInt(json['passageiros_nao_pagantes']),
      totalPassageiros: _asInt(json['total_passageiros']),
      totalVendas: _asDouble(json['total_vendas']),
      totalUtilizacao: _asDouble(json['total_utilizacao']),
      creditoCirculante: _asDouble(json['credito_circulante']),
      receitaPorKm: _asDouble(json['receita_por_km']),
    );
  }

  Map<String, dynamic> toJson() => {
        'referencia': referencia,
        'km_total': kmTotal,
        'km_produtivo': kmProdutivo,
        'km_improdutivo': kmImprodutivo,
        'viagens_programadas': viagensProgramadas,
        'viagens_realizadas': viagensRealizadas,
        'fcv': fcv,
        'passageiros_pagantes': passageirosPagantes,
        'passageiros_nao_pagantes': passageirosNaoPagantes,
        'total_passageiros': totalPassageiros,
        'total_vendas': totalVendas,
        'total_utilizacao': totalUtilizacao,
        'credito_circulante': creditoCirculante,
        'receita_por_km': receitaPorKm,
      };
}

class SerieTemporalRelatorio {
  final PeriodoFiltroRelatorio periodo;
  final int totalPontos;
  final List<PontoSerieTemporalRelatorio> serie;

  const SerieTemporalRelatorio({
    required this.periodo,
    required this.totalPontos,
    required this.serie,
  });

  factory SerieTemporalRelatorio.fromJson(Map<String, dynamic> json) {
    final listaRaw = json['serie'];
    final itens = <PontoSerieTemporalRelatorio>[];
    if (listaRaw is List) {
      for (final item in listaRaw) {
        if (item is Map) {
          itens.add(PontoSerieTemporalRelatorio.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return SerieTemporalRelatorio(
      periodo: PeriodoFiltroRelatorio.fromJson(_asMap(json['periodo'])),
      totalPontos: _asInt(json['total_pontos'], fallback: itens.length),
      serie: itens,
    );
  }

  Map<String, dynamic> toJson() => {
        'periodo': periodo.toJson(),
        'total_pontos': totalPontos,
        'serie': serie.map((e) => e.toJson()).toList(),
      };
}

class LinhaRankingRelatorio {
  final String linha;
  final double kmTotal;
  final int viagens;
  final double mediaKmPorViagem;
  final double participacaoKmPercentual;

  const LinhaRankingRelatorio({
    required this.linha,
    required this.kmTotal,
    required this.viagens,
    required this.mediaKmPorViagem,
    required this.participacaoKmPercentual,
  });

  factory LinhaRankingRelatorio.fromJson(Map<String, dynamic> json) {
    return LinhaRankingRelatorio(
      linha: json['linha']?.toString() ?? '',
      kmTotal: _asDouble(json['km_total']),
      viagens: _asInt(json['viagens']),
      mediaKmPorViagem: _asDouble(json['media_km_por_viagem']),
      participacaoKmPercentual: _asDouble(json['participacao_km_percentual']),
    );
  }

  Map<String, dynamic> toJson() => {
        'linha': linha,
        'km_total': kmTotal,
        'viagens': viagens,
        'media_km_por_viagem': mediaKmPorViagem,
        'participacao_km_percentual': participacaoKmPercentual,
      };
}

class DesvioOperacionalRelatorio {
  final String data;
  final String tipo;
  final String indicador;
  final double valorObservado;
  final double valorReferencia;
  final double? desvioPadraoReferencia;
  final double? zScore;
  final double? desvioPercentual;
  final String descricao;

  const DesvioOperacionalRelatorio({
    required this.data,
    required this.tipo,
    required this.indicador,
    required this.valorObservado,
    required this.valorReferencia,
    this.desvioPadraoReferencia,
    this.zScore,
    this.desvioPercentual,
    required this.descricao,
  });

  factory DesvioOperacionalRelatorio.fromJson(Map<String, dynamic> json) {
    return DesvioOperacionalRelatorio(
      data: json['data']?.toString() ?? '',
      tipo: json['tipo']?.toString() ?? '',
      indicador: json['indicador']?.toString() ?? '',
      valorObservado: _asDouble(json['valor_observado']),
      valorReferencia: _asDouble(json['valor_referencia']),
      desvioPadraoReferencia: _asNullableDouble(json['desvio_padrao_referencia']),
      zScore: _asNullableDouble(json['z_score']),
      desvioPercentual: _asNullableDouble(json['desvio_percentual']),
      descricao: json['descricao']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'data': data,
        'tipo': tipo,
        'indicador': indicador,
        'valor_observado': valorObservado,
        'valor_referencia': valorReferencia,
        'desvio_padrao_referencia': desvioPadraoReferencia,
        'z_score': zScore,
        'desvio_percentual': desvioPercentual,
        'descricao': descricao,
      };
}

class AnomaliasRelatorio {
  final PeriodoFiltroRelatorio periodo;
  final Map<String, double> parametrosTolerancia;
  final EstatisticasHistoricasRelatorio estatisticasHistoricas;
  final int totalOcorrenciasViagens;
  final Map<String, int> ocorrenciasPorClassificacao;
  final List<Map<String, dynamic>> ocorrencias;
  final int totalDesviosOperacionais;
  final List<DesvioOperacionalRelatorio> desviosOperacionais;

  const AnomaliasRelatorio({
    required this.periodo,
    required this.parametrosTolerancia,
    required this.estatisticasHistoricas,
    required this.totalOcorrenciasViagens,
    required this.ocorrenciasPorClassificacao,
    required this.ocorrencias,
    required this.totalDesviosOperacionais,
    required this.desviosOperacionais,
  });

  factory AnomaliasRelatorio.fromJson(Map<String, dynamic> json) {
    final params = <String, double>{};
    final rawParams = json['parametros_tolerancia'];
    if (rawParams is Map) {
      rawParams.forEach((k, v) => params[k.toString()] = _asDouble(v));
    }

    final porClass = <String, int>{};
    final rawClass = json['ocorrencias_por_classificacao'];
    if (rawClass is Map) {
      rawClass.forEach((k, v) => porClass[k.toString()] = _asInt(v));
    }

    final listaOc = <Map<String, dynamic>>[];
    final rawOc = json['ocorrencias'];
    if (rawOc is List) {
      for (final item in rawOc) {
        if (item is Map) listaOc.add(Map<String, dynamic>.from(item));
      }
    }

    final listaDesvios = <DesvioOperacionalRelatorio>[];
    final rawDesvios = json['desvios_operacionais'];
    if (rawDesvios is List) {
      for (final item in rawDesvios) {
        if (item is Map) {
          listaDesvios.add(DesvioOperacionalRelatorio.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return AnomaliasRelatorio(
      periodo: PeriodoFiltroRelatorio.fromJson(_asMap(json['periodo'])),
      parametrosTolerancia: params,
      estatisticasHistoricas: EstatisticasHistoricasRelatorio.fromJson(
        _asMap(json['estatisticas_historicas']),
      ),
      totalOcorrenciasViagens: _asInt(json['total_ocorrencias_viagens'], fallback: listaOc.length),
      ocorrenciasPorClassificacao: porClass,
      ocorrencias: listaOc,
      totalDesviosOperacionais: _asInt(
        json['total_desvios_operacionais'],
        fallback: listaDesvios.length,
      ),
      desviosOperacionais: listaDesvios,
    );
  }

  Map<String, dynamic> toJson() => {
        'periodo': periodo.toJson(),
        'parametros_tolerancia': parametrosTolerancia,
        'estatisticas_historicas': estatisticasHistoricas.toJson(),
        'total_ocorrencias_viagens': totalOcorrenciasViagens,
        'ocorrencias_por_classificacao': ocorrenciasPorClassificacao,
        'ocorrencias': ocorrencias,
        'total_desvios_operacionais': totalDesviosOperacionais,
        'desvios_operacionais': desviosOperacionais.map((e) => e.toJson()).toList(),
      };
}

class RelatorioConsolidado {
  final String geradoEm;
  final PeriodoFiltroRelatorio periodo;
  final ResumoOperacionalRelatorio resumoOperacional;
  final EstatisticasHistoricasRelatorio estatisticasHistoricas;
  final SerieTemporalRelatorio serieTemporal;
  final List<LinhaRankingRelatorio> rankingLinhas;
  final AnomaliasRelatorio anomalias;
  final Map<String, dynamic> rawJson;

  const RelatorioConsolidado({
    required this.geradoEm,
    required this.periodo,
    required this.resumoOperacional,
    required this.estatisticasHistoricas,
    required this.serieTemporal,
    required this.rankingLinhas,
    required this.anomalias,
    required this.rawJson,
  });

  factory RelatorioConsolidado.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('resumo_operacional') ||
        !json.containsKey('serie_temporal') ||
        !json.containsKey('anomalias')) {
      throw const RelatorioApiException(
        'Resposta do servidor incompleta: campos obrigatórios do relatório consolidado ausentes.',
      );
    }

    final listaRanking = <LinhaRankingRelatorio>[];
    final rawRanking = json['ranking_linhas'];
    if (rawRanking is List) {
      for (final item in rawRanking) {
        if (item is Map) {
          listaRanking.add(LinhaRankingRelatorio.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final anomaliasParsed = AnomaliasRelatorio.fromJson(_asMap(json['anomalias']));
    final estatisticasMap = json['estatisticas_historicas'] is Map
        ? _asMap(json['estatisticas_historicas'])
        : anomaliasParsed.estatisticasHistoricas.toJson();

    return RelatorioConsolidado(
      geradoEm: json['gerado_em']?.toString() ?? '',
      periodo: PeriodoFiltroRelatorio.fromJson(_asMap(json['periodo'])),
      resumoOperacional: ResumoOperacionalRelatorio.fromJson(_asMap(json['resumo_operacional'])),
      estatisticasHistoricas: EstatisticasHistoricasRelatorio.fromJson(estatisticasMap),
      serieTemporal: SerieTemporalRelatorio.fromJson(_asMap(json['serie_temporal'])),
      rankingLinhas: listaRanking,
      anomalias: anomaliasParsed,
      rawJson: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toJson() => {
        'gerado_em': geradoEm,
        'periodo': periodo.toJson(),
        'resumo_operacional': resumoOperacional.toJson(),
        'estatisticas_historicas': estatisticasHistoricas.toJson(),
        'serie_temporal': serieTemporal.toJson(),
        'ranking_linhas': rankingLinhas.map((e) => e.toJson()).toList(),
        'anomalias': anomalias.toJson(),
      };

  String formatarTextoResumo() => RelatorioApiService.formatarResumoRelatorio(this);

  String toResumoExecutivoTexto() => RelatorioApiService.formatarResumoRelatorio(this);
}

class ResultadoArquivoLote {
  final String arquivo;
  final String status;
  final String? tipoRelatorio;
  final String? colecao;
  final int totalRegistrosValidos;
  final int? documentosAfetados;
  final String? detalheErro;

  const ResultadoArquivoLote({
    required this.arquivo,
    required this.status,
    this.tipoRelatorio,
    this.colecao,
    required this.totalRegistrosValidos,
    this.documentosAfetados,
    this.detalheErro,
  });

  factory ResultadoArquivoLote.fromJson(Map<String, dynamic> json) {
    return ResultadoArquivoLote(
      arquivo: json['arquivo']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      tipoRelatorio: json['tipo_relatorio']?.toString(),
      colecao: json['colecao']?.toString(),
      totalRegistrosValidos: _asInt(json['total_registros_validos']),
      documentosAfetados: json['documentos_afetados'] == null
          ? null
          : _asInt(json['documentos_afetados']),
      detalheErro: json['detalhe_erro']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'arquivo': arquivo,
        'status': status,
        'tipo_relatorio': tipoRelatorio,
        'colecao': colecao,
        'total_registros_validos': totalRegistrosValidos,
        'documentos_afetados': documentosAfetados,
        'detalhe_erro': detalheErro,
      };
}

class RelatorioUploadIntegrado {
  final int totalArquivosRecebidos;
  final int totalArquivosPersistidos;
  final int totalArquivosApenasProcessados;
  final int totalArquivosComErro;
  final List<ResultadoArquivoLote> arquivos;
  final RelatorioConsolidado relatorio;
  final Map<String, dynamic> rawJson;

  const RelatorioUploadIntegrado({
    required this.totalArquivosRecebidos,
    required this.totalArquivosPersistidos,
    required this.totalArquivosApenasProcessados,
    required this.totalArquivosComErro,
    required this.arquivos,
    required this.relatorio,
    required this.rawJson,
  });

  factory RelatorioUploadIntegrado.fromJson(Map<String, dynamic> json) {
    final listaArqs = <ResultadoArquivoLote>[];
    final rawArqs = json['arquivos'];
    if (rawArqs is List) {
      for (final item in rawArqs) {
        if (item is Map) {
          listaArqs.add(ResultadoArquivoLote.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return RelatorioUploadIntegrado(
      totalArquivosRecebidos: _asInt(json['total_arquivos_recebidos'], fallback: listaArqs.length),
      totalArquivosPersistidos: _asInt(json['total_arquivos_persistidos']),
      totalArquivosApenasProcessados: _asInt(json['total_arquivos_apenas_processados']),
      totalArquivosComErro: _asInt(json['total_arquivos_com_erro']),
      arquivos: listaArqs,
      relatorio: RelatorioConsolidado.fromJson(_asMap(json['relatorio'])),
      rawJson: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toJson() => {
        'total_arquivos_recebidos': totalArquivosRecebidos,
        'total_arquivos_persistidos': totalArquivosPersistidos,
        'total_arquivos_apenas_processados': totalArquivosApenasProcessados,
        'total_arquivos_com_erro': totalArquivosComErro,
        'arquivos': arquivos.map((e) => e.toJson()).toList(),
        'relatorio': relatorio.toJson(),
      };
}

class ResultadoProcessamentoHtml {
  final String arquivo;
  final Map<String, dynamic> metadados;
  final int totalRegistrosValidos;
  final List<String> colunas;
  final List<Map<String, dynamic>> dados;
  final Map<String, dynamic>? persistencia;
  final Map<String, dynamic> rawJson;

  const ResultadoProcessamentoHtml({
    required this.arquivo,
    required this.metadados,
    required this.totalRegistrosValidos,
    required this.colunas,
    required this.dados,
    this.persistencia,
    required this.rawJson,
  });

  factory ResultadoProcessamentoHtml.fromJson(Map<String, dynamic> json) {
    final cols = <String>[];
    if (json['colunas'] is List) {
      for (final c in json['colunas'] as List) {
        cols.add(c.toString());
      }
    }
    final registros = <Map<String, dynamic>>[];
    if (json['dados'] is List) {
      for (final item in json['dados'] as List) {
        if (item is Map) registros.add(Map<String, dynamic>.from(item));
      }
    }
    return ResultadoProcessamentoHtml(
      arquivo: json['arquivo']?.toString() ?? '',
      metadados: _asMap(json['metadados']),
      totalRegistrosValidos: _asInt(json['total_registros_validos'], fallback: registros.length),
      colunas: cols,
      dados: registros,
      persistencia: json['persistencia'] is Map
          ? Map<String, dynamic>.from(json['persistencia'] as Map)
          : null,
      rawJson: Map<String, dynamic>.from(json),
    );
  }
}

///Serviço central de comunicação HTTP com o backend FastAPI
class RelatorioApiService {
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static String? _customBaseUrl;
  static String? _tokenJwt;
  static Map<String, dynamic>? _usuarioLogado;
  static Duration timeoutPadrao = const Duration(seconds: 45);

  ///Retorna a URL base da API ajustada automaticamente para a plataforma atual
  static String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.trim().isNotEmpty) {
      return _removerBarraFinal(_customBaseUrl!.trim());
    }
    if (_envBaseUrl.trim().isNotEmpty) {
      return _removerBarraFinal(_envBaseUrl.trim());
    }
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }

  static void configurarBaseUrl(String? url) {
    _customBaseUrl = url;
  }

  static String? get tokenJwt => _tokenJwt;
  static Map<String, dynamic>? get usuarioLogado => _usuarioLogado;
  static bool get estaAutenticado => _tokenJwt != null && _tokenJwt!.isNotEmpty;

  static void definirToken(String? token, {Map<String, dynamic>? usuario}) {
    _tokenJwt = (token != null && token.trim().isNotEmpty) ? token.trim() : null;
    if (usuario != null) {
      _usuarioLogado = Map<String, dynamic>.from(usuario);
    }
  }

  static void limparSessao() {
    _tokenJwt = null;
    _usuarioLogado = null;
  }

  ///Monta cabeçalhos HTTP incluindo `Authorization: Bearer <token>` quando autenticado
  static Map<String, String> montarHeaders({
    bool jsonBody = false,
    Map<String, String>? extras,
  }) {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (jsonBody) 'Content-Type': 'application/json; charset=utf-8',
      if (estaAutenticado) 'Authorization': 'Bearer $_tokenJwt',
    };
    if (extras != null) {
      headers.addAll(extras);
    }
    return headers;
  }

  ///Autentica o operador em `POST /api/usuarios/login` e armazena o token JWT
  static Future<Map<String, dynamic>> autenticarUsuario({
    required String email,
    required String senha,
    http.Client? client,
  }) async {
    const endpoint = '/api/usuarios/login';
    final uri = Uri.parse('$baseUrl$endpoint');
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .post(
            uri,
            headers: montarHeaders(jsonBody: true),
            body: jsonEncode({'email': email.trim(), 'senha': senha}),
          )
          .timeout(const Duration(seconds: 12));

      final payload = _decodificarJsonObjeto(response, endpoint);
      if (response.statusCode == 200) {
        final token = payload['access_token']?.toString();
        final usuario = payload['usuario'] is Map
            ? Map<String, dynamic>.from(payload['usuario'] as Map)
            : null;
        definirToken(token, usuario: usuario);
        return payload;
      }
      throw RelatorioApiException(
        _extrairDetalheErro(payload, response.statusCode),
        statusCode: response.statusCode,
        endpoint: endpoint,
      );
    } on RelatorioApiException {
      rethrow;
    } catch (e) {
      throw RelatorioApiException(
        'Não foi possível conectar ao servidor ($baseUrl): $e',
        endpoint: endpoint,
      );
    } finally {
      if (client == null) httpClient.close();
    }
  }

  ///Envia um único arquivo `.html`/`.htm` para o backend processar e salvar no MongoDB.
  static Future<ResultadoProcessamentoHtml> enviarArquivoHtmlIndividual({
    required String nomeArquivo,
    required List<int> bytes,
    bool persistirNoBanco = true,
    http.Client? client,
  }) async {
    final endpoint = persistirNoBanco
        ? '/api/transporte/processar-e-salvar'
        : '/api/transporte/processar-html';
    final uri = Uri.parse('$baseUrl$endpoint');
    final httpClient = client ?? http.Client();

    try {
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(montarHeaders());
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: nomeArquivo,
        ),
      );

      final streamed = await httpClient.send(request).timeout(timeoutPadrao);
      final response = await http.Response.fromStream(streamed);
      final payload = _decodificarJsonObjeto(response, endpoint);

      if (response.statusCode == 200) {
        return ResultadoProcessamentoHtml.fromJson(payload);
      }
      throw RelatorioApiException(
        _extrairDetalheErro(payload, response.statusCode),
        statusCode: response.statusCode,
        endpoint: endpoint,
      );
    } on RelatorioApiException {
      rethrow;
    } catch (e) {
      throw RelatorioApiException(
        'Falha ao enviar o arquivo "$nomeArquivo" para o backend: $e',
        endpoint: endpoint,
      );
    } finally {
      if (client == null) httpClient.close();
    }
  }

  ///Envia um lote de arquivos `.html`/`.htm` (vindos do `LocalDataLoader` / `folder_scanner`)
  ///para `POST /api/dashboard/relatorio/upload-e-gerar`, persistindo no MongoDB e retornando
  ///o relatório consolidado já filtrado
  static Future<RelatorioUploadIntegrado> enviarLoteArquivosEGerarRelatorio({
    required List<ArquivoLido> arquivos,
    String agrupamento = 'diario',
    String? dataInicio,
    String? dataFim,
    String? linha,
    double toleranciaDesvioKmPct = 15.0,
    double limiarFcv = 0.98,
    double limiarKmImprodPct = 10.0,
    http.Client? client,
  }) async {
    if (arquivos.isEmpty) {
      throw const RelatorioApiException(
        'Selecione pelo menos um arquivo .html ou .htm para enviar ao backend.',
        statusCode: 400,
        endpoint: '/api/dashboard/relatorio/upload-e-gerar',
      );
    }

    const endpoint = '/api/dashboard/relatorio/upload-e-gerar';
    final queryParams = _montarQueryParamsRelatorio(
      agrupamento: agrupamento,
      dataInicio: dataInicio,
      dataFim: dataFim,
      linha: linha,
      toleranciaDesvioKmPct: toleranciaDesvioKmPct,
      limiarFcv: limiarFcv,
      limiarKmImprodPct: limiarKmImprodPct,
    );
    final uri = Uri.parse('$baseUrl$endpoint').replace(queryParameters: queryParams);
    final httpClient = client ?? http.Client();

    try {
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(montarHeaders());
      for (final arq in arquivos) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'files',
            arq.bytes,
            filename: arq.nome,
          ),
        );
      }

      final streamed = await httpClient.send(request).timeout(timeoutPadrao);
      final response = await http.Response.fromStream(streamed);
      final payload = _decodificarJsonObjeto(response, endpoint);

      if (response.statusCode == 200) {
        return RelatorioUploadIntegrado.fromJson(payload);
      }
      throw RelatorioApiException(
        _extrairDetalheErro(payload, response.statusCode),
        statusCode: response.statusCode,
        endpoint: endpoint,
      );
    } on RelatorioApiException {
      rethrow;
    } catch (e) {
      throw RelatorioApiException(
        'Falha ao enviar lote de arquivos para geração de relatório: $e',
        endpoint: endpoint,
      );
    } finally {
      if (client == null) httpClient.close();
    }
  }

  ///Solicita ao backend a geração do relatório consolidado (`GET /api/dashboard/relatorio`
  ///ou `POST /api/dashboard/relatorio/gerar`) com os filtros ativos
  static Future<RelatorioConsolidado> gerarRelatorioConsolidado({
    String agrupamento = 'diario',
    String? dataInicio,
    String? dataFim,
    String? linha,
    double toleranciaDesvioKmPct = 15.0,
    double limiarFcv = 0.98,
    double limiarKmImprodPct = 10.0,
    bool usarPost = false,
    bool usarRotaV1 = false,
    http.Client? client,
  }) async {
    final endpoint = usarPost
        ? '/api/dashboard/relatorio/gerar'
        : (usarRotaV1 ? '/api/v1/dashboard/relatorio' : '/api/dashboard/relatorio');
    final queryParams = _montarQueryParamsRelatorio(
      agrupamento: agrupamento,
      dataInicio: dataInicio,
      dataFim: dataFim,
      linha: linha,
      toleranciaDesvioKmPct: toleranciaDesvioKmPct,
      limiarFcv: limiarFcv,
      limiarKmImprodPct: limiarKmImprodPct,
    );
    final uri = Uri.parse('$baseUrl$endpoint').replace(queryParameters: queryParams);
    final httpClient = client ?? http.Client();

    try {
      final response = usarPost
          ? await httpClient.post(uri, headers: montarHeaders()).timeout(timeoutPadrao)
          : await httpClient.get(uri, headers: montarHeaders()).timeout(timeoutPadrao);

      final payload = _decodificarJsonObjeto(response, endpoint);
      if (response.statusCode == 200) {
        return RelatorioConsolidado.fromJson(payload);
      }
      throw RelatorioApiException(
        _extrairDetalheErro(payload, response.statusCode),
        statusCode: response.statusCode,
        endpoint: endpoint,
      );
    } on RelatorioApiException {
      rethrow;
    } catch (e) {
      throw RelatorioApiException(
        'Falha ao gerar relatório consolidado no servidor ($baseUrl): $e',
        endpoint: endpoint,
      );
    } finally {
      if (client == null) httpClient.close();
    }
  }

  ///Função utilitária que formata os dados do `RelatorioConsolidado` em texto estruturado
  ///pronto para exportação (.txt/.md), área de transferência ou exibição em modal
  static String formatarResumoRelatorio(RelatorioConsolidado relatorio) {
    final sb = StringBuffer();
    final p = relatorio.periodo;
    final km = relatorio.resumoOperacional.quilometragem;
    final vg = relatorio.resumoOperacional.viagens;
    final ps = relatorio.resumoOperacional.passageiros;
    final fn = relatorio.resumoOperacional.financeiro;
    final st = relatorio.estatisticasHistoricas;
    final an = relatorio.anomalias;

    final inicioStr = p.dataInicio ?? 'Início disponível';
    final fimStr = p.dataFim ?? 'Fim disponível';
    final linhaStr = (p.linha != null && p.linha!.isNotEmpty) ? p.linha! : 'Todas as linhas';
    final agrupStr = (p.agrupamento ?? 'diario').toUpperCase();

    sb.writeln('==============================================================');
    sb.writeln('       RELATÓRIO OPERACIONAL CONSOLIDADO • SEMOB');
    sb.writeln('==============================================================');
    sb.writeln('Gerado em   : ${relatorio.geradoEm}');
    sb.writeln('Período     : $inicioStr a $fimStr');
    sb.writeln('Agrupamento : $agrupStr');
    sb.writeln('Linha       : $linhaStr');
    sb.writeln('--------------------------------------------------------------');

    sb.writeln('\n[1. QUILOMETRAGEM E EFICIÊNCIA DE FROTA]');
    sb.writeln('• Quilometragem Total       : ${km.kmTotal.toStringAsFixed(2)} km');
    sb.writeln('• Quilometragem Produtiva   : ${km.kmProdutivo.toStringAsFixed(2)} km');
    sb.writeln('• Quilometragem Improdutiva : ${km.kmImprodutivo.toStringAsFixed(2)} km (${km.taxaImprodutivaPercentual.toStringAsFixed(2)}%)');
    sb.writeln('• Média Diária              : ${km.mediaDiariaKm.toStringAsFixed(2)} km/dia');

    sb.writeln('\n[2. CUMPRIMENTO DE VIAGENS (FCV)]');
    sb.writeln('• Viagens Programadas       : ${vg.programadas}');
    sb.writeln('• Viagens Realizadas        : ${vg.realizadas}');
    sb.writeln('• Diferença (Não Realizadas): ${vg.diferenca}');
    sb.writeln('• FCV Médio Global          : ${(vg.fcvMedio * 100).toStringAsFixed(2)}%');
    if (vg.porPeriodo.isNotEmpty) {
      vg.porPeriodo.forEach((turno, dadosTurno) {
        sb.writeln(
          '  - Turno ${turno.toUpperCase()}: Prog=${dadosTurno.prog} | Real=${dadosTurno.real} | FCV=${(dadosTurno.fcv * 100).toStringAsFixed(2)}%',
        );
      });
    }

    sb.writeln('\n[3. DEMANDA DE PASSAGEIROS]');
    sb.writeln('• Total Geral de Passageiros: ${ps.totalGeral}');
    sb.writeln('• Pagantes                  : ${ps.pagantes} (Catraca: ${ps.catraca} | Antecipados: ${ps.antecipados})');
    sb.writeln('• Gratuidades (Não Pagantes): ${ps.naoPagantes} (${ps.percentualGratuidade.toStringAsFixed(2)}%)');

    sb.writeln('\n[4. INDICADORES FINANCEIROS E BILHETAGEM]');
    sb.writeln('• Total de Vendas           : R\$ ${fn.totalVendas.toStringAsFixed(2)}');
    sb.writeln('• Total de Utilização       : R\$ ${fn.totalUtilizacao.toStringAsFixed(2)}');
    sb.writeln('• Créditos Transf. Cartões  : R\$ ${fn.creditosTransferidosCartoes.toStringAsFixed(2)}');
    sb.writeln('• Crédito Circulante Acum.  : R\$ ${fn.creditoCirculanteAcumulado.toStringAsFixed(2)}');
    if (fn.saldoFinalRecente != null) {
      sb.writeln('• Saldo Final Mais Recente  : R\$ ${fn.saldoFinalRecente!.toStringAsFixed(2)}');
    }
    sb.writeln('• Receita por Quilômetro    : R\$ ${fn.receitaPorKm.toStringAsFixed(2)}/km');

    sb.writeln('\n[5. ESTATÍSTICAS HISTÓRICAS E DISPERSÃO (DESVIO PADRÃO)]');
    sb.writeln('• KM Diário         : Média = ${st.mediaKm.toStringAsFixed(2)} km | DP = ${st.desvioPadraoKm.toStringAsFixed(2)} km');
    sb.writeln('• Viagens Diárias   : Média = ${st.mediaViagensRealizadas.toStringAsFixed(2)} | DP = ${st.desvioPadraoViagens.toStringAsFixed(2)}');
    sb.writeln('• FCV Histórico     : Média = ${(st.mediaFcv * 100).toStringAsFixed(2)}% | DP = ${(st.desvioPadraoFcv * 100).toStringAsFixed(2)}%');
    sb.writeln('• Tarifa Efetiva    : Média = R\$ ${st.mediaTarifaEfetiva.toStringAsFixed(4)} | DP = R\$ ${st.desvioPadraoTarifaEfetiva.toStringAsFixed(4)}');

    if (relatorio.rankingLinhas.isNotEmpty) {
      sb.writeln('\n[6. RANKING DE LINHAS POR QUILOMETRAGEM]');
      for (final item in relatorio.rankingLinhas.take(10)) {
        sb.writeln(
          '• Linha ${item.linha.padLeft(2, '0')}: ${item.kmTotal.toStringAsFixed(2)} km | '
          '${item.viagens} viagens (${item.mediaKmPorViagem.toStringAsFixed(2)} km/viagem) | '
          '${item.participacaoKmPercentual.toStringAsFixed(2)}% do total',
        );
      }
    }

    sb.writeln('\n[7. ANOMALIAS, DESVIOS OPERACIONAIS (Z-SCORE) E OCORRÊNCIAS]');
    sb.writeln('• Total de Ocorrências Registradas : ${an.totalOcorrenciasViagens}');
    if (an.ocorrenciasPorClassificacao.isNotEmpty) {
      final resumoClass = an.ocorrenciasPorClassificacao.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(' | ');
      sb.writeln('  ($resumoClass)');
    }
    sb.writeln('• Total de Desvios Detectados      : ${an.totalDesviosOperacionais}');
    for (final d in an.desviosOperacionais) {
      final zTexto = d.zScore != null ? ' | Z-Score=${d.zScore!.toStringAsFixed(2)}' : '';
      sb.writeln('  - [${d.data}] (${d.tipo}$zTexto): ${d.descricao}');
    }
    sb.writeln('==============================================================');

    return sb.toString();
  }

  static Map<String, String> _montarQueryParamsRelatorio({
    required String agrupamento,
    String? dataInicio,
    String? dataFim,
    String? linha,
    required double toleranciaDesvioKmPct,
    required double limiarFcv,
    required double limiarKmImprodPct,
  }) {
    final params = <String, String>{
      'agrupamento': agrupamento.trim().toLowerCase(),
      'tolerancia_desvio_km_pct': toleranciaDesvioKmPct.toString(),
      'limiar_fcv': limiarFcv.toString(),
      'limiar_km_improd_pct': limiarKmImprodPct.toString(),
    };
    if (dataInicio != null && dataInicio.trim().isNotEmpty) {
      params['data_inicio'] = dataInicio.trim();
    }
    if (dataFim != null && dataFim.trim().isNotEmpty) {
      params['data_fim'] = dataFim.trim();
    }
    if (linha != null && linha.trim().isNotEmpty && linha.trim().toLowerCase() != 'todas') {
      params['linha'] = linha.trim();
    }
    return params;
  }

  static Map<String, dynamic> _decodificarJsonObjeto(http.Response response, String endpoint) {
    final texto = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (texto.isEmpty) {
      throw RelatorioApiException(
        'Resposta vazia do servidor (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
        endpoint: endpoint,
      );
    }
    try {
      final decodificado = jsonDecode(texto);
      if (decodificado is Map<String, dynamic>) {
        return decodificado;
      }
      if (decodificado is Map) {
        return Map<String, dynamic>.from(decodificado);
      }
      throw RelatorioApiException(
        'Formato JSON inesperado retornado pelo endpoint $endpoint.',
        statusCode: response.statusCode,
        endpoint: endpoint,
      );
    } on RelatorioApiException {
      rethrow;
    } catch (_) {
      throw RelatorioApiException(
        'Erro HTTP ${response.statusCode} ao acessar $endpoint.',
        statusCode: response.statusCode,
        endpoint: endpoint,
      );
    }
  }

  static String _extrairDetalheErro(Map<String, dynamic> payload, int statusCode) {
    final detail = payload['detail'];
    if (detail is String && detail.trim().isNotEmpty) {
      return detail.trim();
    }
    if (detail is List && detail.isNotEmpty) {
      return detail
          .map((e) => e is Map ? (e['msg']?.toString() ?? e.toString()) : e.toString())
          .join('; ');
    }
    return 'Falha na requisição (HTTP $statusCode).';
  }

  static String _removerBarraFinal(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

double _asDouble(dynamic value, {double fallback = 0.0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

double? _asNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString()) ?? double.tryParse(value.toString())?.round() ?? fallback;
}