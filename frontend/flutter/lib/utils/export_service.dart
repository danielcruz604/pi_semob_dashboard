import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../folder_scanner_io.dart' if (dart.library.html) '../folder_scanner_web.dart';
import '../models/dashboard_models.dart';

class ExportService {
  static Future<void> exportarRelatorioCsv({
    required ResumoOperacional resumo,
    required List<LinhaRanking> ranking,
    required AnomaliasResponse anomalias,
  }) async {
    final buffer = StringBuffer();

    // BOM UTF-8 para reconhecimento de caracteres acentuados no Excel
    buffer.write('\uFEFF');

    buffer.writeln('=== RELATÓRIO OPERACIONAL SEMOB - SÃO CAETANO DO SUL ===');
    buffer.writeln('Gerado em:;${DateTime.now().toIso8601String()}');
    buffer.writeln();

    buffer.writeln('INDICADORES PRINCIPAIS');
    buffer.writeln('Métrica;Valor');
    buffer.writeln('KM Total Rodado;${resumo.kmTotal.toStringAsFixed(2)} km');
    buffer.writeln('KM Produtivo;${resumo.kmProdutivo.toStringAsFixed(2)} km');
    buffer.writeln(
        'KM Improdutivo;${resumo.kmImprodutivo.toStringAsFixed(2)} km (${resumo.taxaImprodutiva.toStringAsFixed(1)}%)');
    buffer.writeln('Viagens Programadas;${resumo.viagensProgramadas}');
    buffer.writeln('Viagens Realizadas;${resumo.viagensRealizadas}');
    buffer.writeln('FCV Médio (Cumprimento);${(resumo.fcvMedio * 100).toStringAsFixed(2)}%');
    buffer.writeln('Total de Passageiros;${resumo.totalPassageiros}');
    buffer.writeln('Receita por KM;R\$ ${resumo.receitaPorKm.toStringAsFixed(2)}');
    buffer.writeln();

    buffer.writeln('RANKING DE LINHAS MUNICIPAIS');
    buffer.writeln('Linha;KM Total;Viagens Realizadas;Média KM/Viagem;Participação (%)');
    for (final l in ranking) {
      buffer.writeln(
          '${l.linha};${l.kmTotal.toStringAsFixed(2)};${l.viagens};${l.mediaKmPorViagem.toStringAsFixed(2)};${l.participacaoKm.toStringAsFixed(1)}%');
    }
    buffer.writeln();

    buffer.writeln('ANOMALIAS E OUTLIERS REGISTRADOS');
    buffer.writeln('Data;Tipo;Indicador;Observado;Referência;Descrição');
    for (final a in anomalias.desviosOperacionais) {
      buffer.writeln(
          '${a.data};${a.tipo};${a.indicador};${a.valorObservado};${a.valorReferencia};"${a.descricao}"');
    }

    final conteudoCsv = buffer.toString();

    if (kIsWeb) {
      debugPrint('Exportação Web acionada (${conteudoCsv.length} bytes)');
    } else {
      final caminho = 'relatorio_semob_${DateTime.now().millisecondsSinceEpoch}.csv';
      await salvarBytesNoCaminho(caminho, utf8.encode(conteudoCsv));
      debugPrint('Relatório salvo em: $caminho');
    }
  }
}
