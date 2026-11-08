class ResumoOperacional {
  final double kmTotal;
  final double kmProdutivo;
  final double kmImprodutivo;
  final double taxaImprodutiva;
  final int viagensProgramadas;
  final int viagensRealizadas;
  final double fcvMedio;
  final int totalPassageiros;
  final double receitaPorKm;

  ResumoOperacional({
    required this.kmTotal,
    required this.kmProdutivo,
    required this.kmImprodutivo,
    required this.taxaImprodutiva,
    required this.viagensProgramadas,
    required this.viagensRealizadas,
    required this.fcvMedio,
    required this.totalPassageiros,
    required this.receitaPorKm,
  });

  factory ResumoOperacional.fromJson(Map<String, dynamic> json) {
    final km = json['quilometragem'] ?? {};
    final viag = json['viagens'] ?? {};
    final pass = json['passageiros'] ?? {};
    final fin = json['financeiro'] ?? {};

    return ResumoOperacional(
      kmTotal: (km['km_total'] as num?)?.toDouble() ?? 0.0,
      kmProdutivo: (km['km_produtivo'] as num?)?.toDouble() ?? 0.0,
      kmImprodutivo: (km['km_improdutivo'] as num?)?.toDouble() ?? 0.0,
      taxaImprodutiva: (km['taxa_improdutiva_percentual'] as num?)?.toDouble() ?? 0.0,
      viagensProgramadas: (viag['programadas'] as num?)?.toInt() ?? 0,
      viagensRealizadas: (viag['realizadas'] as num?)?.toInt() ?? 0,
      fcvMedio: (viag['fcv_medio'] as num?)?.toDouble() ?? 0.0,
      totalPassageiros: (pass['total_geral'] as num?)?.toInt() ?? 0,
      receitaPorKm: (fin['receita_por_km'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class DesvioOperacional {
  final String data;
  final String tipo;
  final String indicador;
  final double valorObservado;
  final double valorReferencia;
  final double? desvioPercentual;
  final String descricao;

  DesvioOperacional({
    required this.data,
    required this.tipo,
    required this.indicador,
    required this.valorObservado,
    required this.valorReferencia,
    this.desvioPercentual,
    required this.descricao,
  });

  factory DesvioOperacional.fromJson(Map<String, dynamic> json) {
    return DesvioOperacional(
      data: json['data']?.toString() ?? '',
      tipo: json['tipo']?.toString() ?? '',
      indicador: json['indicador']?.toString() ?? '',
      valorObservado: (json['valor_observado'] as num?)?.toDouble() ?? 0.0,
      valorReferencia: (json['valor_referencia'] as num?)?.toDouble() ?? 0.0,
      desvioPercentual: (json['desvio_percentual'] as num?)?.toDouble(),
      descricao: json['descricao']?.toString() ?? '',
    );
  }
}

class AnomaliasResponse {
  final int totalOcorrenciasViagens;
  final Map<String, int> ocorrenciasPorClassificacao;
  final int totalDesviosOperacionais;
  final List<DesvioOperacional> desviosOperacionais;

  AnomaliasResponse({
    required this.totalOcorrenciasViagens,
    required this.ocorrenciasPorClassificacao,
    required this.totalDesviosOperacionais,
    required this.desviosOperacionais,
  });

  factory AnomaliasResponse.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> rawOc =
        (json['ocorrencias_por_classificacao'] as Map?)?.cast<String, dynamic>() ?? {};
    final parsedOc = rawOc.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));

    final List rawDesvios = json['desvios_operacionais'] as List? ?? [];
    return AnomaliasResponse(
      totalOcorrenciasViagens: (json['total_ocorrencias_viagens'] as num?)?.toInt() ?? 0,
      ocorrenciasPorClassificacao: parsedOc,
      totalDesviosOperacionais: (json['total_desvios_operacionais'] as num?)?.toInt() ?? 0,
      desviosOperacionais: rawDesvios
          .whereType<Map>()
          .map((d) => DesvioOperacional.fromJson(d.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class LinhaRanking {
  final String linha;
  final double kmTotal;
  final int viagens;
  final double mediaKmPorViagem;
  final double participacaoKm;

  LinhaRanking({
    required this.linha,
    required this.kmTotal,
    required this.viagens,
    required this.mediaKmPorViagem,
    required this.participacaoKm,
  });

  factory LinhaRanking.fromJson(Map<String, dynamic> json) {
    return LinhaRanking(
      linha: json['linha']?.toString() ?? '',
      kmTotal: (json['km_total'] as num?)?.toDouble() ?? 0.0,
      viagens: (json['viagens'] as num?)?.toInt() ?? 0,
      mediaKmPorViagem: (json['media_km_por_viagem'] as num?)?.toDouble() ?? 0.0,
      participacaoKm: (json['participacao_km_percentual'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
