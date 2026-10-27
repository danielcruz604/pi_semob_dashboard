import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../folder_scanner_io.dart' if (dart.library.html) '../folder_scanner_web.dart';
import '../local_data_loader.dart';
import '../models/dashboard_models.dart';

class AlertaExecutivoPdf {
  final String titulo;
  final String descricao;
  final bool critico;

  const AlertaExecutivoPdf({
    required this.titulo,
    required this.descricao,
    this.critico = false,
  });
}

class ExportService {
  static const Map<int, String> _nomesDiaSemana = {
    1: 'Segunda-feira',
    2: 'Terça-feira',
    3: 'Quarta-feira',
    4: 'Quinta-feira',
    5: 'Sexta-feira',
    6: 'Sábado',
    7: 'Domingo',
  };

  static const Map<int, String> _nomesDiaCurto = {
    1: 'Seg',
    2: 'Ter',
    3: 'Qua',
    4: 'Qui',
    5: 'Sex',
    6: 'Sáb',
    7: 'Dom',
  };

  /// Substitui apenas símbolos tipográficos Unicode fora do padrão Latin-1 (ISO-8859-1),
  /// preservando integralmente todos os acentos da língua portuguesa (á, é, í, ó, ú, ã, õ, â, ê, ô, ç).
  static String _sanitizarLatin1(String texto) {
    return texto
        .replaceAll('•', '-')
        .replaceAll('✓', 'OK')
        .replaceAll('✔', 'OK')
        .replaceAll('⚠', '')
        .replaceAll('→', '->')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .trim();
  }

  static String _fmtInt(int v) {
    final neg = v < 0;
    final s = v.abs().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return neg ? '-${buffer.toString()}' : buffer.toString();
  }

  static String _fmtDecimal(double v, {int casas = 2}) {
    final partes = v.toStringAsFixed(casas).split('.');
    final inteiro = int.tryParse(partes[0]) ?? 0;
    if (casas <= 0 || partes.length < 2) return _fmtInt(inteiro);
    return '${_fmtInt(inteiro)},${partes[1]}';
  }

  static String _fmtDataHoraAgora() {
    final d = DateTime.now();
    final dia = d.day.toString().padLeft(2, '0');
    final mes = d.month.toString().padLeft(2, '0');
    final hora = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${d.year} às ${hora}h$min';
  }

  /// Gera um Boletim / Relatório Institucional em PDF (A4) com diagramação editorial sóbria,
  /// acentuação completa em português, tabelas técnicas limpas e notas explicativas discretas.
  static Future<Uint8List> gerarBytesRelatorioPdf({
    required String mesSelecionado,
    required String periodicidade,
    required String? linhaSelecionada,
    required String intervaloTexto,
    required String origemDados,
    required List<ResumoDiario> resumos,
    required List<PassageiroDiario> passageiros,
    required List<FcvDiario> fcv,
    required List<FaixaHorariaItem> faixasHorarias,
    required List<LinhaDiaria> linhas,
    required List<AlertaExecutivoPdf> alertas,
  }) async {
    final pdf = pw.Document(
      title: 'Boletim Operacional SEMOB - $mesSelecionado ($periodicidade)',
      author: 'Secretaria Municipal de Mobilidade Urbana (SEMOB) - São Caetano do Sul',
      subject: 'Acompanhamento Operacional do Transporte Público Coletivo',
    );

    // Consolidação dos dados do período filtrado
    int viagensProg = 0;
    int viagensRealiz = 0;
    double kmTotal = 0;
    double kmProd = 0;
    double kmImprod = 0;
    int maxFrota = 0;

    if (linhaSelecionada == null && resumos.isNotEmpty) {
      for (final r in resumos) {
        viagensProg += r.viagensProg;
        viagensRealiz += r.viagensRealiz;
        kmTotal += r.kmTotal;
        kmProd += r.kmProd;
        kmImprod += r.kmImprod;
        if (r.veiculos > maxFrota) maxFrota = r.veiculos;
      }
    } else if (linhas.isNotEmpty) {
      for (final l in linhas) {
        viagensProg += l.viagensProg;
        viagensRealiz += l.viagensRealiz;
        kmTotal += l.kmTotal;
        kmProd += l.kmTotal;
      }
    } else {
      for (final f in faixasHorarias) {
        viagensRealiz += f.viagens;
        viagensProg += f.viagens;
        if (f.veiculos > maxFrota) maxFrota = f.veiculos;
      }
    }

    if (maxFrota == 0 && faixasHorarias.isNotEmpty) {
      for (final f in faixasHorarias) {
        if (f.veiculos > maxFrota) maxFrota = f.veiculos;
      }
    }

    int totalPass = 0;
    int totalCatraca = 0;
    int totalAntecipados = 0;
    int totalGratuitos = 0;
    for (final p in passageiros) {
      totalPass += p.totalPassageiros;
      totalCatraca += p.catraca;
      totalAntecipados += p.antecipados;
      totalGratuitos += p.naoPagantes;
    }
    final int totalPagantes = totalCatraca + totalAntecipados;

    final double fcvPercent = viagensProg > 0 ? (viagensRealiz / viagensProg) * 100.0 : 100.0;
    final int viagensNaoRealizadas = (viagensProg - viagensRealiz) > 0 ? (viagensProg - viagensRealiz) : 0;
    final double taxaKmOcioso = kmTotal > 0 ? (kmImprod / kmTotal) * 100.0 : 0.0;
    final double ipk = kmTotal > 0 ? totalPass / kmTotal : 0.0;
    final double percGratuidade = totalPass > 0 ? (totalGratuitos / totalPass) * 100.0 : 0.0;
    final double percPagantes = totalPass > 0 ? (totalPagantes / totalPass) * 100.0 : 0.0;

    // Consolidação por período do dia (Manhã, Tarde, Noite)
    int manhaP = 0, manhaR = 0, tardeP = 0, tardeR = 0, noiteP = 0, noiteR = 0;
    for (final item in fcv) {
      manhaP += item.manhaProg;
      manhaR += item.manhaRealiz;
      tardeP += item.tardeProg;
      tardeR += item.tardeRealiz;
      noiteP += item.noiteProg;
      noiteR += item.noiteRealiz;
    }
    if (manhaR == 0 && tardeR == 0 && noiteR == 0 && faixasHorarias.isNotEmpty) {
      for (final item in faixasHorarias) {
        if (item.hora >= 5 && item.hora < 12) {
          manhaR += item.viagens;
        } else if (item.hora >= 12 && item.hora < 18) {
          tardeR += item.viagens;
        } else {
          noiteR += item.viagens;
        }
      }
      final ratio = viagensProg > 0 ? (viagensRealiz / viagensProg) : 0.9984;
      final safeRatio = ratio > 0 ? ratio : 1.0;
      manhaP = (manhaR / safeRatio).round();
      tardeP = (tardeR / safeRatio).round();
      noiteP = (noiteR / safeRatio).round();
    }

    // Consolidação por linha
    final Map<String, int> viagensProgPorLinha = {};
    final Map<String, int> viagensRealizPorLinha = {};
    final Map<String, double> kmPorLinha = {};
    if (linhas.isNotEmpty) {
      for (final l in linhas) {
        viagensProgPorLinha[l.linha] = (viagensProgPorLinha[l.linha] ?? 0) + l.viagensProg;
        viagensRealizPorLinha[l.linha] = (viagensRealizPorLinha[l.linha] ?? 0) + l.viagensRealiz;
        kmPorLinha[l.linha] = (kmPorLinha[l.linha] ?? 0.0) + l.kmTotal;
      }
    } else {
      for (final f in faixasHorarias) {
        viagensProgPorLinha[f.linha] = (viagensProgPorLinha[f.linha] ?? 0) + f.viagens;
        viagensRealizPorLinha[f.linha] = (viagensRealizPorLinha[f.linha] ?? 0) + f.viagens;
      }
    }
    final topLinhas = viagensRealizPorLinha.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final int diasAnalisados = resumos.length;
    final int diasDentroDaMeta = resumos.where((r) {
      final fcvDia = r.viagensProg > 0 ? (r.viagensRealiz / r.viagensProg) * 100.0 : 100.0;
      return fcvDia >= 98.0;
    }).length;
    final int diasAbaixoMeta = diasAnalisados - diasDentroDaMeta;

    final bool temAlertaCritico = alertas.any((a) => a.critico) || fcvPercent < 95.0;
    final bool operacaoRegular = fcvPercent >= 98.0 && !temAlertaCritico;

    // Paleta institucional sóbria (Padrão Ofício / Relatório Técnico)
    const corInstitucional = PdfColor.fromInt(0xFF1B365D); // Azul-marinho institucional
    const corTextoPrincipal = PdfColor.fromInt(0xFF1E293B); // Grafite escuro
    const corTextoSecundario = PdfColor.fromInt(0xFF475569); // Cinza ardósia
    const corBordaSuave = PdfColor.fromInt(0xFFCBD5E1);
    const corFundoZebra = PdfColor.fromInt(0xFFF8FAFC);

    // Cores semânticas discretas (apenas para situação contratual)
    const corConforme = PdfColor.fromInt(0xFF166534);
    const corRessalva = PdfColor.fromInt(0xFF92400E);
    const corNaoConforme = PdfColor.fromInt(0xFF991B1B);

    final PdfColor corSituacao =
        operacaoRegular ? corConforme : (temAlertaCritico ? corNaoConforme : corRessalva);
    final String textoSituacao = operacaoRegular
        ? 'Regular (Meta contratual atingida)'
        : (temAlertaCritico ? 'Abaixo da meta contratual' : 'Regular com ressalvas pontuais');

    // Nota técnica introdutória com redação natural e humana
    final String notaIntrodutoria = _redigirNotaTecnica(
      diasAnalisados: diasAnalisados,
      diasDentroDaMeta: diasDentroDaMeta,
      diasAbaixoMeta: diasAbaixoMeta,
      viagensProg: viagensProg,
      viagensRealiz: viagensRealiz,
      viagensNaoRealizadas: viagensNaoRealizadas,
      fcvPercent: fcvPercent,
      totalPass: totalPass,
      totalPagantes: totalPagantes,
      totalGratuitos: totalGratuitos,
      percGratuidade: percGratuidade,
      kmTotal: kmTotal,
      kmProd: kmProd,
      kmImprod: kmImprod,
      taxaKmOcioso: taxaKmOcioso,
      maxFrota: maxFrota,
      ipk: ipk,
    );

    final mapPassPorData = {for (final p in passageiros) p.data: p};

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 32),
        header: (context) => _buildCabecalhoOficial(
          context: context,
          mesSelecionado: _sanitizarLatin1(mesSelecionado),
          periodicidade: _sanitizarLatin1(periodicidade),
          linhaSelecionada: linhaSelecionada != null ? _sanitizarLatin1(linhaSelecionada) : null,
          intervaloTexto: _sanitizarLatin1(intervaloTexto),
          textoSituacao: textoSituacao,
          corSituacao: corSituacao,
        ),
        footer: (context) => _buildRodapeOficial(context, _sanitizarLatin1(origemDados)),
        build: (context) => [
          // 1. NOTA TÉCNICA / RESUMO DO PERÍODO
          _tituloSecaoEditorial('Síntese Operacional do Período'),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const pw.BoxDecoration(
              color: corFundoZebra,
              border: pw.Border(
                left: pw.BorderSide(color: corInstitucional, width: 2.5),
                top: pw.BorderSide(color: corBordaSuave, width: 0.5),
                right: pw.BorderSide(color: corBordaSuave, width: 0.5),
                bottom: pw.BorderSide(color: corBordaSuave, width: 0.5),
              ),
            ),
            child: pw.Text(
              notaIntrodutoria,
              textAlign: pw.TextAlign.justify,
              style: const pw.TextStyle(
                fontSize: 8.8,
                color: corTextoPrincipal,
                lineSpacing: 2.2,
              ),
            ),
          ),
          pw.SizedBox(height: 14),

          // 2. QUADRO CONSOLIDADO DE INDICADORES (TABELA EXECUTIVA LIMPA)
          _tituloSecaoEditorial('Quadro Consolidado de Indicadores'),
          _buildQuadroIndicadoresConsolidados(
            fcvPercent: fcvPercent,
            viagensProg: viagensProg,
            viagensRealiz: viagensRealiz,
            viagensNaoRealizadas: viagensNaoRealizadas,
            diasAnalisados: diasAnalisados,
            diasDentroDaMeta: diasDentroDaMeta,
            totalPass: totalPass,
            totalPagantes: totalPagantes,
            percPagantes: percPagantes,
            totalGratuitos: totalGratuitos,
            percGratuidade: percGratuidade,
            kmTotal: kmTotal,
            kmProd: kmProd,
            kmImprod: kmImprod,
            taxaKmOcioso: taxaKmOcioso,
            maxFrota: maxFrota,
            ipk: ipk,
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Notas técnicas: (1) FCV (Fator de Cumprimento de Viagens): percentual de partidas efetivamente realizadas frente ao quadro de horários determinado pela SEMOB (meta mínima: 98,0%). '
            '(2) KM em Linha vs. Garagem: distância percorrida atendendo passageiros nas linhas versus deslocamento vazio entre garagem e terminais (limite técnico de referência: até 10%). '
            '(3) IPK (Índice de Passageiros por Quilômetro): média de passageiros transportados por quilômetro rodado.',
            style: const pw.TextStyle(fontSize: 6.8, color: corTextoSecundario, lineSpacing: 1.2),
          ),
          pw.SizedBox(height: 14),

          // 3. CUMPRIMENTO POR FAIXA DE HORÁRIO E PRINCIPAIS LINHAS (LADO A LADO EM TABELAS SÓBRIAS)
          _tituloSecaoEditorial('Desempenho por Turno e Principais Linhas'),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 5,
                child: _buildTabelaTurnos(
                  manhaP: manhaP,
                  manhaR: manhaR,
                  tardeP: tardeP,
                  tardeR: tardeR,
                  noiteP: noiteP,
                  noiteR: noiteR,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 5,
                child: _buildTabelaPrincipaisLinhas(
                  topLinhas: topLinhas,
                  viagensProgPorLinha: viagensProgPorLinha,
                  kmPorLinha: kmPorLinha,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // 4. REGISTRO DE OCORRÊNCIAS E RESSALVAS DO PERÍODO
          if (alertas.isNotEmpty) ...[
            _tituloSecaoEditorial('Apontamentos Operacionais e Ressalvas'),
            _buildQuadroApontamentos(alertas),
            pw.SizedBox(height: 14),
          ],

          // 5. DEMONSTRATIVO DIÁRIO DE OPERAÇÃO
          _tituloSecaoEditorial('Demonstrativo Diário de Operação e Demanda'),
          if (resumos.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              child: pw.Text(
                'Não há registros diários disponíveis para o filtro selecionado.',
                style: const pw.TextStyle(fontSize: 8.5, color: corTextoSecundario),
              ),
            )
          else
            _buildTabelaDiariaEditorial(
              resumos: resumos,
              mapPassPorData: mapPassPorData,
              viagensProgTotal: viagensProg,
              viagensRealizTotal: viagensRealiz,
              fcvPercentTotal: fcvPercent,
              kmTotalGeral: kmTotal,
              kmImprodGeral: kmImprod,
              totalPagantesGeral: totalPagantes,
              totalGratuitosGeral: totalGratuitos,
              totalPassGeral: totalPass,
              maxFrotaGeral: maxFrota,
            ),

          pw.SizedBox(height: 18),
          _buildBlocoEncerramento(),
        ],
      ),
    );

    return pdf.save();
  }

  static String _redigirNotaTecnica({
    required int diasAnalisados,
    required int diasDentroDaMeta,
    required int diasAbaixoMeta,
    required int viagensProg,
    required int viagensRealiz,
    required int viagensNaoRealizadas,
    required double fcvPercent,
    required int totalPass,
    required int totalPagantes,
    required int totalGratuitos,
    required double percGratuidade,
    required double kmTotal,
    required double kmProd,
    required double kmImprod,
    required double taxaKmOcioso,
    required int maxFrota,
    required double ipk,
  }) {
    final partes = <String>[];

    if (viagensProg > 0) {
      if (fcvPercent >= 98.0) {
        partes.add(
          'No período analisado ($diasAnalisados ${diasAnalisados == 1 ? "dia avaliado" : "dias avaliados"}), o sistema municipal de transporte coletivo cumpriu ${_fmtDecimal(fcvPercent)}% das viagens programadas, atingindo a meta contratual mínima de 98,0%. '
          'Foram realizadas ${_fmtInt(viagensRealiz)} das ${_fmtInt(viagensProg)} viagens previstas ($diasDentroDaMeta de $diasAnalisados dias dentro do parâmetro regular).',
        );
      } else {
        partes.add(
          'No período analisado ($diasAnalisados ${diasAnalisados == 1 ? "dia avaliado" : "dias avaliados"}), o índice médio de cumprimento de viagens foi de ${_fmtDecimal(fcvPercent)}%, abaixo do parâmetro contratual de 98,0%. '
          'Das ${_fmtInt(viagensProg)} partidas programadas, ${_fmtInt(viagensRealiz)} foram realizadas e ${_fmtInt(viagensNaoRealizadas)} deixaram de ocorrer ao longo de $diasAbaixoMeta ${diasAbaixoMeta == 1 ? "dia" : "dias"} com desempenho inferior à meta.',
        );
      }
    }

    if (totalPass > 0) {
      partes.add(
        'A demanda registrada nas catracas totalizou ${_fmtInt(totalPass)} passageiros transportados, distribuídos entre ${_fmtInt(totalPagantes)} embarques tarifados e ${_fmtInt(totalGratuitos)} gratuidades regulamentares (${_fmtDecimal(percGratuidade, casas: 1)}% do movimento total, abrangendo idosos, estudantes e demais isenções legais).',
      );
    }

    if (kmTotal > 0) {
      partes.add(
        'A operação contou com frota máxima de $maxFrota veículos em horário de pico e percorreu ${_fmtDecimal(kmTotal, casas: 1)} km totais, sendo ${_fmtDecimal(kmProd, casas: 1)} km em atendimento comercial nas linhas e ${_fmtDecimal(kmImprod, casas: 1)} km (${_fmtDecimal(taxaKmOcioso, casas: 1)}%) em deslocamentos de garagem, resultando na média de ${_fmtDecimal(ipk)} passageiros por quilômetro (IPK).',
      );
    }

    if (partes.isEmpty) {
      return 'Sem registros operacionais consolidados para os parâmetros selecionados.';
    }
    return partes.join(' ');
  }

  static pw.Widget _buildCabecalhoOficial({
    required pw.Context context,
    required String mesSelecionado,
    required String periodicidade,
    required String? linhaSelecionada,
    required String intervaloTexto,
    required String textoSituacao,
    required PdfColor corSituacao,
  }) {
    const corInstitucional = PdfColor.fromInt(0xFF1B365D);
    const corTextoPrincipal = PdfColor.fromInt(0xFF1E293B);
    const corTextoSecundario = PdfColor.fromInt(0xFF475569);
    const corBorda = PdfColor.fromInt(0xFFCBD5E1);
    const corFundoMeta = PdfColor.fromInt(0xFFF8FAFC);

    // A partir da página 2, exibe um cabeçalho compacto de continuação de folha oficial
    if (context.pageNumber > 1) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: corInstitucional, width: 1)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'PREFEITURA MUNICIPAL DE SÃO CAETANO DO SUL - SEMOB',
              style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: corInstitucional),
            ),
            pw.Text(
              'Boletim de Acompanhamento Operacional - $mesSelecionado ($periodicidade)',
              style: const pw.TextStyle(fontSize: 7.5, color: corTextoSecundario),
            ),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(height: 3, color: corInstitucional),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'PREFEITURA MUNICIPAL DE SÃO CAETANO DO SUL',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: corInstitucional,
                    letterSpacing: 0.4,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  'Secretaria Municipal de Mobilidade Urbana - SEMOB',
                  style: const pw.TextStyle(fontSize: 8.2, color: corTextoSecundario),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'BOLETIM DE ACOMPANHAMENTO OPERACIONAL',
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                    color: corTextoPrincipal,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  'Transporte Público Coletivo Municipal',
                  style: const pw.TextStyle(fontSize: 8, color: corTextoSecundario),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: corBorda, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.2),
            1: pw.FlexColumnWidth(3.0),
            2: pw.FlexColumnWidth(2.4),
            3: pw.FlexColumnWidth(2.8),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: corFundoMeta),
              children: [
                _celulaMetadado('COMPETÊNCIA / BASE', '$mesSelecionado ($periodicidade)'),
                _celulaMetadado('PERÍODO ANALISADO', intervaloTexto),
                _celulaMetadado(
                  'ABRANGÊNCIA',
                  linhaSelecionada == null ? 'Sistema Municipal (Todas as linhas)' : 'Linha $linhaSelecionada',
                ),
                _celulaMetadado('SITUAÇÃO NO PERÍODO', textoSituacao, corValor: corSituacao),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 14),
      ],
    );
  }

  static pw.Widget _celulaMetadado(
    String rotulo,
    String valor, {
    PdfColor corValor = const PdfColor.fromInt(0xFF1E293B),
  }) {
    const corTextoSecundario = PdfColor.fromInt(0xFF64748B);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            rotulo,
            style: pw.TextStyle(fontSize: 6.2, fontWeight: pw.FontWeight.bold, color: corTextoSecundario),
          ),
          pw.SizedBox(height: 1.5),
          pw.Text(
            valor,
            style: pw.TextStyle(fontSize: 7.8, fontWeight: pw.FontWeight.bold, color: corValor),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildRodapeOficial(pw.Context context, String origemDados) {
    const corTextoSecundario = PdfColor.fromInt(0xFF64748B);
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColor.fromInt(0xFFCBD5E1), width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'SEMOB São Caetano do Sul - Fonte dos dados: $origemDados - Emitido em ${_fmtDataHoraAgora()}',
            style: const pw.TextStyle(fontSize: 7, color: corTextoSecundario),
          ),
          pw.Text(
            'Folha ${context.pageNumber} de ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: corTextoSecundario),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tituloSecaoEditorial(String titulo) {
    const corInstitucional = PdfColor.fromInt(0xFF1B365D);
    const corBorda = PdfColor.fromInt(0xFFCBD5E1);
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.only(bottom: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: corBorda, width: 0.7)),
      ),
      child: pw.Row(
        children: [
          pw.Container(width: 3, height: 10, color: corInstitucional),
          pw.SizedBox(width: 5),
          pw.Text(
            titulo.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: corInstitucional,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildQuadroIndicadoresConsolidados({
    required double fcvPercent,
    required int viagensProg,
    required int viagensRealiz,
    required int viagensNaoRealizadas,
    required int diasAnalisados,
    required int diasDentroDaMeta,
    required int totalPass,
    required int totalPagantes,
    required double percPagantes,
    required int totalGratuitos,
    required double percGratuidade,
    required double kmTotal,
    required double kmProd,
    required double kmImprod,
    required double taxaKmOcioso,
    required int maxFrota,
    required double ipk,
  }) {
    const corBorda = PdfColor.fromInt(0xFFCBD5E1);
    const corCabecalho = PdfColor.fromInt(0xFFF1F5F9);
    const corConforme = PdfColor.fromInt(0xFF166534);
    const corNaoConforme = PdfColor.fromInt(0xFF991B1B);
    const corRessalva = PdfColor.fromInt(0xFF92400E);

    final PdfColor corFcv =
        fcvPercent >= 98.0 ? corConforme : (fcvPercent >= 95.0 ? corRessalva : corNaoConforme);

    return pw.Table(
      border: pw.TableBorder.all(color: corBorda, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.2),
        1: pw.FlexColumnWidth(2.0),
        2: pw.FlexColumnWidth(2.2),
        3: pw.FlexColumnWidth(3.6),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: corCabecalho),
          children: [
            _celulaCabecalho('Indicador Operacional', align: pw.TextAlign.left),
            _celulaCabecalho('Resultado no Período'),
            _celulaCabecalho('Referência / Meta'),
            _celulaCabecalho('Detalhamento Técnico', align: pw.TextAlign.left),
          ],
        ),
        _linhaIndicador(
          nome: 'Cumprimento de Viagens (FCV) ¹',
          valor: '${_fmtDecimal(fcvPercent)}%',
          referencia: 'Mínimo de 98,0%',
          detalhe: '$diasDentroDaMeta de $diasAnalisados dias atingiram a meta contratual',
          corValor: corFcv,
        ),
        _linhaIndicador(
          nome: 'Oferta de Viagens Realizadas',
          valor: '${_fmtInt(viagensRealiz)} viagens',
          referencia: '${_fmtInt(viagensProg)} previstas',
          detalhe: viagensNaoRealizadas > 0
              ? 'Diferença de ${_fmtInt(viagensNaoRealizadas)} viagens não realizadas no período'
              : 'Totalidade das viagens programadas foi atendida',
          zebra: true,
        ),
        _linhaIndicador(
          nome: 'Passageiros Transportados (Total)',
          valor: _fmtInt(totalPass),
          referencia: 'Demanda efetiva',
          detalhe: 'Pagantes: ${_fmtInt(totalPagantes)} (${_fmtDecimal(percPagantes, casas: 1)}%) | '
              'Gratuidades: ${_fmtInt(totalGratuitos)} (${_fmtDecimal(percGratuidade, casas: 1)}%)',
        ),
        _linhaIndicador(
          nome: 'Quilometragem Total Percorrida ²',
          valor: '${_fmtDecimal(kmTotal, casas: 1)} km',
          referencia: 'Garagem <= 10,0%',
          detalhe: 'Em linha: ${_fmtDecimal(kmProd, casas: 1)} km | '
              'Deslocamento de garagem: ${_fmtDecimal(kmImprod, casas: 1)} km (${_fmtDecimal(taxaKmOcioso, casas: 1)}%)',
          zebra: true,
        ),
        _linhaIndicador(
          nome: 'Frota em Pico e Índice de Ocupação (IPK) ³',
          valor: '$maxFrota veículos',
          referencia: 'IPK: ${_fmtDecimal(ipk)} pass./km',
          detalhe: 'Frota máxima simultânea em operação e média de embarques por km rodado',
        ),
      ],
    );
  }

  static pw.TableRow _linhaIndicador({
    required String nome,
    required String valor,
    required String referencia,
    required String detalhe,
    PdfColor corValor = const PdfColor.fromInt(0xFF1E293B),
    bool zebra = false,
  }) {
    const corZebra = PdfColor.fromInt(0xFFF8FAFC);
    const corTextoPrincipal = PdfColor.fromInt(0xFF1E293B);
    const corTextoSecundario = PdfColor.fromInt(0xFF475569);

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: zebra ? corZebra : PdfColors.white),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
          child: pw.Text(
            nome,
            style: pw.TextStyle(fontSize: 7.8, fontWeight: pw.FontWeight.bold, color: corTextoPrincipal),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
          child: pw.Text(
            valor,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 8.2, fontWeight: pw.FontWeight.bold, color: corValor),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
          child: pw.Text(
            referencia,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 7.5, color: corTextoSecundario),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
          child: pw.Text(
            detalhe,
            style: const pw.TextStyle(fontSize: 7.5, color: corTextoSecundario),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTabelaTurnos({
    required int manhaP,
    required int manhaR,
    required int tardeP,
    required int tardeR,
    required int noiteP,
    required int noiteR,
  }) {
    const corBorda = PdfColor.fromInt(0xFFCBD5E1);
    const corCabecalho = PdfColor.fromInt(0xFFF1F5F9);

    return pw.Table(
      border: pw.TableBorder.all(color: corBorda, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.6),
        1: pw.FlexColumnWidth(1.3),
        2: pw.FlexColumnWidth(1.3),
        3: pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: corCabecalho),
          children: [
            _celulaCabecalho('Faixa Horária (Turno)', align: pw.TextAlign.left),
            _celulaCabecalho('Previstas'),
            _celulaCabecalho('Realizadas'),
            _celulaCabecalho('FCV (%)'),
          ],
        ),
        _linhaTurno('Manhã (05h às 11h59)', manhaP, manhaR),
        _linhaTurno('Tarde (12h às 17h59)', tardeP, tardeR, zebra: true),
        _linhaTurno('Noite (18h às 04h59)', noiteP, noiteR),
      ],
    );
  }

  static pw.TableRow _linhaTurno(String turno, int prog, int realiz, {bool zebra = false}) {
    final double perc = prog > 0 ? (realiz / prog) * 100.0 : 0.0;
    const corConforme = PdfColor.fromInt(0xFF166534);
    const corRessalva = PdfColor.fromInt(0xFF92400E);
    const corNaoConforme = PdfColor.fromInt(0xFF991B1B);
    final PdfColor corFcv = perc >= 98.0 ? corConforme : (perc >= 95.0 ? corRessalva : corNaoConforme);

    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: zebra ? const PdfColor.fromInt(0xFFF8FAFC) : PdfColors.white,
      ),
      children: [
        _celulaDados(turno, align: pw.TextAlign.left, bold: true),
        _celulaDados(_fmtInt(prog)),
        _celulaDados(_fmtInt(realiz)),
        _celulaDados(prog > 0 ? '${_fmtDecimal(perc, casas: 1)}%' : '-', bold: true, cor: corFcv),
      ],
    );
  }

  static pw.Widget _buildTabelaPrincipaisLinhas({
    required List<MapEntry<String, int>> topLinhas,
    required Map<String, int> viagensProgPorLinha,
    required Map<String, double> kmPorLinha,
  }) {
    const corBorda = PdfColor.fromInt(0xFFCBD5E1);
    const corCabecalho = PdfColor.fromInt(0xFFF1F5F9);

    final linhasExibir = topLinhas.take(5).toList();

    return pw.Table(
      border: pw.TableBorder.all(color: corBorda, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: corCabecalho),
          children: [
            _celulaCabecalho('Principais Linhas (Oferta)', align: pw.TextAlign.left),
            _celulaCabecalho('Viag. Realiz.'),
            _celulaCabecalho('FCV (%)'),
            _celulaCabecalho('KM Total'),
          ],
        ),
        if (linhasExibir.isEmpty)
          pw.TableRow(
            children: [
              _celulaDados('Sem detalhamento por linha', align: pw.TextAlign.left),
              _celulaDados('-'),
              _celulaDados('-'),
              _celulaDados('-'),
            ],
          )
        else
          ...List.generate(linhasExibir.length, (i) {
            final entry = linhasExibir[i];
            final nomeLinha = _sanitizarLatin1(entry.key);
            final realiz = entry.value;
            final prog = viagensProgPorLinha[entry.key] ?? realiz;
            final fcvL = prog > 0 ? (realiz / prog) * 100.0 : 100.0;
            final kmL = kmPorLinha[entry.key] ?? 0.0;
            return pw.TableRow(
              decoration: pw.BoxDecoration(
                color: i.isOdd ? const PdfColor.fromInt(0xFFF8FAFC) : PdfColors.white,
              ),
              children: [
                _celulaDados('Linha $nomeLinha', align: pw.TextAlign.left, bold: true),
                _celulaDados(_fmtInt(realiz)),
                _celulaDados('${_fmtDecimal(fcvL, casas: 1)}%'),
                _celulaDados(kmL > 0 ? '${_fmtDecimal(kmL, casas: 0)} km' : '-'),
              ],
            );
          }),
      ],
    );
  }

  static pw.Widget _buildQuadroApontamentos(List<AlertaExecutivoPdf> alertas) {
    const corBorda = PdfColor.fromInt(0xFFCBD5E1);
    const corCabecalho = PdfColor.fromInt(0xFFF1F5F9);
    const corNaoConforme = PdfColor.fromInt(0xFF991B1B);
    const corRessalva = PdfColor.fromInt(0xFF92400E);

    final exibidos = alertas.take(10).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Table(
          border: pw.TableBorder.all(color: corBorda, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.2),
            1: pw.FlexColumnWidth(2.8),
            2: pw.FlexColumnWidth(6.0),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: corCabecalho),
              children: [
                _celulaCabecalho('Classificação'),
                _celulaCabecalho('Ocorrência Registrada', align: pw.TextAlign.left),
                _celulaCabecalho('Descrição Técnica', align: pw.TextAlign.left),
              ],
            ),
            ...List.generate(exibidos.length, (i) {
              final a = exibidos[i];
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: i.isOdd ? const PdfColor.fromInt(0xFFF8FAFC) : PdfColors.white,
                ),
                children: [
                  _celulaDados(
                    a.critico ? 'Crítico' : 'Ressalva',
                    bold: true,
                    cor: a.critico ? corNaoConforme : corRessalva,
                  ),
                  _celulaDados(_sanitizarLatin1(a.titulo), align: pw.TextAlign.left, bold: true),
                  _celulaDados(_sanitizarLatin1(a.descricao), align: pw.TextAlign.left),
                ],
              );
            }),
          ],
        ),
        if (alertas.length > 10)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Text(
              'Nota: Há outros ${alertas.length - 10} registros detalhados no demonstrativo diário a seguir.',
              style: pw.TextStyle(
                fontSize: 7,
                fontStyle: pw.FontStyle.italic,
                color: const PdfColor.fromInt(0xFF475569),
              ),
            ),
          ),
      ],
    );
  }

  static pw.Widget _buildTabelaDiariaEditorial({
    required List<ResumoDiario> resumos,
    required Map<String, PassageiroDiario> mapPassPorData,
    required int viagensProgTotal,
    required int viagensRealizTotal,
    required double fcvPercentTotal,
    required double kmTotalGeral,
    required double kmImprodGeral,
    required int totalPagantesGeral,
    required int totalGratuitosGeral,
    required int totalPassGeral,
    required int maxFrotaGeral,
  }) {
    const corInstitucional = PdfColor.fromInt(0xFF1B365D);
    const corConforme = PdfColor.fromInt(0xFF166534);
    const corRessalva = PdfColor.fromInt(0xFF92400E);
    const corNaoConforme = PdfColor.fromInt(0xFF991B1B);
    const corZebra = PdfColor.fromInt(0xFFF8FAFC);
    const corBordaTabela = PdfColor.fromInt(0xFFCBD5E1);

    final headers = [
      'Data',
      'Dia',
      'Frota',
      'Previstas',
      'Realizadas',
      'Dif.',
      'FCV (%)',
      'KM Total',
      'Pagantes',
      'Gratuitos',
      'Total Pass.',
      'Situação',
    ];

    final List<pw.TableRow> rows = [];

    // Cabeçalho institucional da tabela
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: corInstitucional),
        children: headers
            .map(
              (h) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
                child: pw.Text(
                  h,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 6.8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );

    for (int i = 0; i < resumos.length; i++) {
      final r = resumos[i];
      final p = mapPassPorData[r.data];
      final double fcvDia = r.viagensProg > 0 ? (r.viagensRealiz / r.viagensProg) * 100.0 : 100.0;
      final int saldoDia = r.viagensRealiz - r.viagensProg;
      final int pagantesDia = p != null ? (p.catraca + p.antecipados) : 0;

      final bool metaOk = fcvDia >= 98.0;
      final bool atencao = fcvDia >= 95.0 && fcvDia < 98.0;

      final PdfColor corStatus = metaOk ? corConforme : (atencao ? corRessalva : corNaoConforme);
      final String rotuloStatus = metaOk ? 'Regular' : (atencao ? 'Atenção' : 'Abaixo da meta');

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : corZebra),
          children: [
            _celulaDados(r.data, bold: true),
            _celulaDados(_nomesDiaCurto[r.weekday] ?? _sanitizarLatin1(_nomesDiaSemana[r.weekday] ?? '')),
            _celulaDados('${r.veiculos}'),
            _celulaDados(_fmtInt(r.viagensProg)),
            _celulaDados(_fmtInt(r.viagensRealiz), bold: true),
            _celulaDados(
              saldoDia == 0 ? '0' : (saldoDia > 0 ? '+${_fmtInt(saldoDia)}' : _fmtInt(saldoDia)),
              cor: saldoDia >= 0 ? corConforme : corNaoConforme,
            ),
            _celulaDados('${_fmtDecimal(fcvDia)}%', cor: corStatus, bold: true),
            _celulaDados(_fmtDecimal(r.kmTotal, casas: 1)),
            _celulaDados(p != null ? _fmtInt(pagantesDia) : '-'),
            _celulaDados(p != null ? _fmtInt(p.naoPagantes) : '-'),
            _celulaDados(p != null ? _fmtInt(p.totalPassageiros) : '-', bold: true),
            _celulaDados(rotuloStatus, cor: corStatus, bold: true),
          ],
        ),
      );
    }

    // Linha de Total / Consolidação
    final int saldoTotal = viagensRealizTotal - viagensProgTotal;
    final bool metaTotalOk = fcvPercentTotal >= 98.0;
    final PdfColor corTotalStatus = metaTotalOk ? corConforme : corNaoConforme;

    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
        children: [
          _celulaDados('TOTAL', bold: true),
          _celulaDados('${resumos.length} d.', bold: true),
          _celulaDados('Máx: $maxFrotaGeral', bold: true),
          _celulaDados(_fmtInt(viagensProgTotal), bold: true),
          _celulaDados(_fmtInt(viagensRealizTotal), bold: true),
          _celulaDados(
            saldoTotal == 0 ? '0' : (saldoTotal > 0 ? '+${_fmtInt(saldoTotal)}' : _fmtInt(saldoTotal)),
            bold: true,
            cor: saldoTotal >= 0 ? corConforme : corNaoConforme,
          ),
          _celulaDados('${_fmtDecimal(fcvPercentTotal)}%', bold: true, cor: corTotalStatus),
          _celulaDados(_fmtDecimal(kmTotalGeral, casas: 1), bold: true),
          _celulaDados(_fmtInt(totalPagantesGeral), bold: true),
          _celulaDados(_fmtInt(totalGratuitosGeral), bold: true),
          _celulaDados(_fmtInt(totalPassGeral), bold: true),
          _celulaDados(metaTotalOk ? 'Meta atingida' : 'Abaixo da meta', bold: true, cor: corTotalStatus),
        ],
      ),
    );

    return pw.Table(
      border: pw.TableBorder.all(color: corBordaTabela, width: 0.5),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  static pw.Widget _buildBlocoEncerramento() {
    const corBorda = PdfColor.fromInt(0xFF94A3B8);
    const corTextoSecundario = PdfColor.fromInt(0xFF475569);
    const corTextoPrincipal = PdfColor.fromInt(0xFF1E293B);

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          flex: 6,
          child: pw.Text(
            'Documento emitido pelo Sistema de Monitoramento do Transporte Coletivo da SEMOB - São Caetano do Sul, '
            'com base nos arquivos operacionais e de bilhetagem eletrônica consolidados no período.',
            style: const pw.TextStyle(fontSize: 7, color: corTextoSecundario, lineSpacing: 1.3),
          ),
        ),
        pw.SizedBox(width: 30),
        pw.Expanded(
          flex: 4,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                height: 18,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: corBorda, width: 0.6)),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Conferência Técnica - SEMOB / SCS',
                style: pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold, color: corTextoPrincipal),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _celulaCabecalho(
    String texto, {
    pw.TextAlign align = pw.TextAlign.center,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4.5),
      child: pw.Text(
        texto,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 7.2,
          fontWeight: pw.FontWeight.bold,
          color: const PdfColor.fromInt(0xFF1E293B),
        ),
      ),
    );
  }

  static pw.Widget _celulaDados(
    String texto, {
    bool bold = false,
    PdfColor cor = const PdfColor.fromInt(0xFF1E293B),
    pw.TextAlign align = pw.TextAlign.center,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
      child: pw.Text(
        texto,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 7.0,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: cor,
        ),
      ),
    );
  }

  static Future<void> exportarRelatorioCsv({
    required ResumoOperacional resumo,
    required List<LinhaRanking> ranking,
    required AnomaliasResponse anomalias,
  }) async {
    final buffer = StringBuffer();
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

    final conteudoCsv = buffer.toString();
    if (!kIsWeb) {
      final caminho = 'relatorio_semob_${DateTime.now().millisecondsSinceEpoch}.csv';
      await salvarBytesNoCaminho(caminho, utf8.encode(conteudoCsv));
    }
  }
}
