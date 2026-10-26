import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'folder_scanner_io.dart' if (dart.library.html) 'folder_scanner_web.dart';
import 'relatorio_api_service.dart';
export 'folder_scanner_io.dart' if (dart.library.html) 'folder_scanner_web.dart' show ArquivoLido;
export 'relatorio_api_service.dart';
export 'relatorio_integration.dart';

/// Representa uma discrepância detectada quando um relatório HTML (Mensal ou Quinzenal)
/// sobrepõe dados já existentes ou calculados a partir dos registros diários com valores divergentes.
class DiscrepanciaConsolidacao {
  final String data;
  final String categoria;
  final String periodicidadeNova;
  final String periodicidadeBase;
  final String descricao;

  const DiscrepanciaConsolidacao({
    required this.data,
    required this.categoria,
    required this.periodicidadeNova,
    required this.periodicidadeBase,
    required this.descricao,
  });
}

class SemobDataset {
  final List<ResumoDiario> resumos = [];
  final List<PassageiroDiario> passageiros = [];
  final List<FcvDiario> fcv = [];
  final List<FaixaHorariaItem> faixasHorarias = [];
  final List<LinhaDiaria> linhas = [];

  /// Mantém os arquivos HTML brutos carregados para envio sob demanda ao backend FastAPI
  final List<ArquivoLido> arquivosHtmlCarregados = [];

  /// Lista de discrepâncias detectadas ao sobrepor cálculos diários com HTMLs Mensais/Quinzenais
  final List<DiscrepanciaConsolidacao> discrepanciasDetectadas = [];

  /// Contador de registros sobrepostos que possuíam valores idênticos ao cálculo diário e foram ignorados
  int registrosIdenticosIgnorados = 0;

  /// Contador de registros Mensais/Quinzenais calculados automaticamente a partir dos dados diários
  int registrosDerivadosViaDiario = 0;

  /// Último relatório consolidado retornado pelo backend para o conjunto de dados ativo
  RelatorioConsolidado? ultimoRelatorioBackend;

  /// Resultado do último envio em lote de arquivos HTML para o backend.
  RelatorioUploadIntegrado? ultimoUploadIntegrado;

  static const Map<String, int> _ordemMeses = {
    'janeiro': 1,
    'fevereiro': 2,
    'março': 3,
    'marco': 3,
    'abril': 4,
    'maio': 5,
    'junho': 6,
    'julho': 7,
    'agosto': 8,
    'setembro': 9,
    'outubro': 10,
    'novembro': 11,
    'dezembro': 12,
  };

  bool get isEmpty =>
      resumos.isEmpty &&
      passageiros.isEmpty &&
      fcv.isEmpty &&
      faixasHorarias.isEmpty &&
      linhas.isEmpty &&
      arquivosHtmlCarregados.isEmpty;

  static int _chaveOrdenacaoMes(String mesAno) {
    final partes = mesAno.toLowerCase().split('/');
    if (partes.length != 2) return 999999;
    final mesNum = _ordemMeses[partes[0].trim()] ?? 99;
    final anoNum = int.tryParse(partes[1].trim()) ?? 9999;
    return (anoNum * 100) + mesNum;
  }

  List<String> get mesesDisponiveis {
    final s = <String>{
      ...resumos.map((e) => e.mesAno),
      ...passageiros.map((e) => e.mesAno),
      ...fcv.map((e) => e.mesAno),
      ...faixasHorarias.map((e) => e.mesAno),
      ...linhas.map((e) => e.mesAno),
    };
    final lista = s.toList()
      ..sort((a, b) => _chaveOrdenacaoMes(a).compareTo(_chaveOrdenacaoMes(b)));
    return lista;
  }

  List<String> get linhasDisponiveis {
    final s = <String>{
      ...faixasHorarias.map((e) => e.linha),
      ...linhas.map((e) => e.linha),
    };
    final lista = s.toList()..sort();
    return lista;
  }
}

class ResumoDiario {
  final String mesAno;
  final String periodicidade;
  final String data;
  final DateTime dateTime;
  final int weekday;
  final int veiculos;
  final int maxVeicFaixa;
  final int viagensProg;
  final int viagensRealiz;
  final int difViagens;
  final double kmProd;
  final double kmImprod;
  final double kmTotal;
  final bool calculadoViaDiario;

  ResumoDiario({
    required this.mesAno,
    required this.periodicidade,
    required this.data,
    required this.dateTime,
    required this.weekday,
    required this.veiculos,
    required this.maxVeicFaixa,
    required this.viagensProg,
    required this.viagensRealiz,
    required this.difViagens,
    required this.kmProd,
    required this.kmImprod,
    required this.kmTotal,
    this.calculadoViaDiario = false,
  });

  ResumoDiario copiarParaPeriodicidade(
    String novaPeriodicidade, {
    bool calculadoViaDiario = true,
  }) {
    return ResumoDiario(
      mesAno: mesAno,
      periodicidade: novaPeriodicidade,
      data: data,
      dateTime: dateTime,
      weekday: weekday,
      veiculos: veiculos,
      maxVeicFaixa: maxVeicFaixa,
      viagensProg: viagensProg,
      viagensRealiz: viagensRealiz,
      difViagens: difViagens,
      kmProd: kmProd,
      kmImprod: kmImprod,
      kmTotal: kmTotal,
      calculadoViaDiario: calculadoViaDiario,
    );
  }
}

class PassageiroDiario {
  final String mesAno;
  final String periodicidade;
  final String data;
  final DateTime dateTime;
  final int weekday;
  final int catraca;
  final int antecipados;
  final int naoPagantes;
  final int totalPassageiros;
  final bool calculadoViaDiario;

  PassageiroDiario({
    required this.mesAno,
    required this.periodicidade,
    required this.data,
    required this.dateTime,
    required this.weekday,
    required this.catraca,
    required this.antecipados,
    required this.naoPagantes,
    required this.totalPassageiros,
    this.calculadoViaDiario = false,
  });

  PassageiroDiario copiarParaPeriodicidade(
    String novaPeriodicidade, {
    bool calculadoViaDiario = true,
  }) {
    return PassageiroDiario(
      mesAno: mesAno,
      periodicidade: novaPeriodicidade,
      data: data,
      dateTime: dateTime,
      weekday: weekday,
      catraca: catraca,
      antecipados: antecipados,
      naoPagantes: naoPagantes,
      totalPassageiros: totalPassageiros,
      calculadoViaDiario: calculadoViaDiario,
    );
  }
}

class FcvDiario {
  final String mesAno;
  final String periodicidade;
  final String data;
  final DateTime dateTime;
  final int weekday;
  final int manhaProg;
  final int manhaRealiz;
  final int tardeProg;
  final int tardeRealiz;
  final int noiteProg;
  final int noiteRealiz;
  final int totalProg;
  final int totalRealiz;
  final bool calculadoViaDiario;

  FcvDiario({
    required this.mesAno,
    required this.periodicidade,
    required this.data,
    required this.dateTime,
    required this.weekday,
    required this.manhaProg,
    required this.manhaRealiz,
    required this.tardeProg,
    required this.tardeRealiz,
    required this.noiteProg,
    required this.noiteRealiz,
    required this.totalProg,
    required this.totalRealiz,
    this.calculadoViaDiario = false,
  });

  FcvDiario copiarParaPeriodicidade(
    String novaPeriodicidade, {
    bool calculadoViaDiario = true,
  }) {
    return FcvDiario(
      mesAno: mesAno,
      periodicidade: novaPeriodicidade,
      data: data,
      dateTime: dateTime,
      weekday: weekday,
      manhaProg: manhaProg,
      manhaRealiz: manhaRealiz,
      tardeProg: tardeProg,
      tardeRealiz: tardeRealiz,
      noiteProg: noiteProg,
      noiteRealiz: noiteRealiz,
      totalProg: totalProg,
      totalRealiz: totalRealiz,
      calculadoViaDiario: calculadoViaDiario,
    );
  }
}

class FaixaHorariaItem {
  final String mesAno;
  final String periodicidade;
  final String data;
  final DateTime dateTime;
  final int weekday;
  final String linha;
  final int hora;
  final String faixaTexto;
  final int veiculos;
  final int viagens;
  final String partidas;
  final bool calculadoViaDiario;

  FaixaHorariaItem({
    required this.mesAno,
    required this.periodicidade,
    required this.data,
    required this.dateTime,
    required this.weekday,
    required this.linha,
    required this.hora,
    required this.faixaTexto,
    required this.veiculos,
    required this.viagens,
    required this.partidas,
    this.calculadoViaDiario = false,
  });

  FaixaHorariaItem copiarParaPeriodicidade(
    String novaPeriodicidade, {
    bool calculadoViaDiario = true,
  }) {
    return FaixaHorariaItem(
      mesAno: mesAno,
      periodicidade: novaPeriodicidade,
      data: data,
      dateTime: dateTime,
      weekday: weekday,
      linha: linha,
      hora: hora,
      faixaTexto: faixaTexto,
      veiculos: veiculos,
      viagens: viagens,
      partidas: partidas,
      calculadoViaDiario: calculadoViaDiario,
    );
  }
}

class LinhaDiaria {
  final String mesAno;
  final String periodicidade;
  final String data;
  final DateTime dateTime;
  final int weekday;
  final String linha;
  final int viagensProg;
  final int viagensRealiz;
  final double kmTotal;
  final bool calculadoViaDiario;

  LinhaDiaria({
    required this.mesAno,
    required this.periodicidade,
    required this.data,
    required this.dateTime,
    required this.weekday,
    required this.linha,
    required this.viagensProg,
    required this.viagensRealiz,
    required this.kmTotal,
    this.calculadoViaDiario = false,
  });

  LinhaDiaria copiarParaPeriodicidade(
    String novaPeriodicidade, {
    bool calculadoViaDiario = true,
  }) {
    return LinhaDiaria(
      mesAno: mesAno,
      periodicidade: novaPeriodicidade,
      data: data,
      dateTime: dateTime,
      weekday: weekday,
      linha: linha,
      viagensProg: viagensProg,
      viagensRealiz: viagensRealiz,
      kmTotal: kmTotal,
      calculadoViaDiario: calculadoViaDiario,
    );
  }
}

class LocalDataLoader {
  /// Verifica se o arquivo possui extensão `.html` ou `.htm` aceita pelo backend.
  static bool arquivoEhHtmlSuportado(String nomeArquivo) {
    final nome = nomeArquivo.toLowerCase().trim();
    return nome.endsWith('.html') || nome.endsWith('.htm');
  }

  static bool arquivoEhRelatorioUtil(String nomeArquivo) {
    final nome = nomeArquivo.toLowerCase().trim();
    if (!nome.endsWith('.html') && !nome.endsWith('.htm')) return false;

    if (nome.contains('_viagens') ||
        nome.contains('nrealiz') ||
        nome.contains('nterm') ||
        nome.contains('ninic') ||
        nome.contains('resumo_fxhr') ||
        nome.contains('saldos')) {
      return false;
    }

    if (nome.contains('passageiro') ||
        nome.contains('fcv') ||
        nome.contains('fxhr') ||
        nome.contains('fx_hr') ||
        nome.contains('linhas')) {
      return true;
    }

    if (RegExp(r'(mensal|quinzenal)[_\s-]*\d{6}').hasMatch(nome)) {
      return true;
    }

    return false;
  }

  static String extrairNomeCurtoPasta(String rawPath) {
    String limpo = rawPath;
    try {
      limpo = Uri.decodeFull(rawPath);
    } catch (_) {}
    if (limpo.contains(':')) {
      final aposDoisPontos = limpo.split(':').last;
      if (aposDoisPontos.isNotEmpty) limpo = aposDoisPontos;
    }
    final partes = limpo.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
    return partes.isNotEmpty ? partes.last : 'Pasta';
  }

  /// Carrega uma pasta nativa e mescla (ou cria) o `SemobDataset`,
  /// calculando automaticamente visões Quinzenais/Mensais ausentes a partir dos diários
  /// e validando sobreposições sem duplicar nem perder dados.
  static Future<SemobDataset> carregarPasta(
    String caminhoEscolhido, {
    SemobDataset? datasetExistente,
  }) async {
    final dataset = datasetExistente ?? SemobDataset();
    if (kIsWeb) return dataset;

    final arquivosLidos = await escanearPastaNativa(
      caminhoEscolhido,
      arquivoEhHtmlSuportado,
    );

    for (final arq in arquivosLidos) {
      _registrarArquivoHtmlUnico(dataset, arq);
      if (arquivoEhRelatorioUtil(arq.nome)) {
        _processarArquivoIndividual(
          nomeArquivo: arq.nome,
          caminhoCompleto: arq.caminho,
          bytes: arq.bytes,
          dataset: dataset,
        );
      }
    }

    reconciliarDerivacoesDiarias(dataset);
    return dataset;
  }

  /// Carrega um ou mais arquivos HTML selecionados pelo usuário (juntos, um por um ou em ordem aleatória),
  /// preservando dados anteriores em `datasetExistente`, reconciliando sobreposições e derivando
  /// automaticamente Quinzenal/Mensal a partir dos registros diários quando ausentes.
  static Future<SemobDataset> carregarArquivosSelecionados(
    List<dynamic> files, {
    SemobDataset? datasetExistente,
  }) async {
    final dataset = datasetExistente ?? SemobDataset();
    for (final arquivo in files) {
      try {
        final String nome = arquivo.name?.toString() ?? 'relatorio.html';
        if (!arquivoEhHtmlSuportado(nome)) continue;

        final List<int> bytes = await arquivo.readAsBytes();
        String caminho = nome;
        if (!kIsWeb) {
          try {
            caminho = arquivo.path?.toString() ?? nome;
          } catch (_) {}
        }

        _registrarArquivoHtmlUnico(
          dataset,
          ArquivoLido(
            nome: nome,
            caminho: caminho,
            bytes: bytes,
          ),
        );

        if (arquivoEhRelatorioUtil(nome)) {
          _processarArquivoIndividual(
            nomeArquivo: nome,
            caminhoCompleto: caminho,
            bytes: bytes,
            dataset: dataset,
          );
        }
      } catch (_) {}
    }

    reconciliarDerivacoesDiarias(dataset);
    return dataset;
  }

  static void _registrarArquivoHtmlUnico(SemobDataset ds, ArquivoLido novo) {
    final idx = ds.arquivosHtmlCarregados.indexWhere(
      (a) => a.nome.toLowerCase() == novo.nome.toLowerCase(),
    );
    if (idx >= 0) {
      ds.arquivosHtmlCarregados[idx] = novo;
    } else {
      ds.arquivosHtmlCarregados.add(novo);
    }
  }

  /// Calcula automaticamente as visões `Quinzenal` e `Mensal` a partir dos registros diários
  /// quando o usuário possui apenas uma das periodicidades carregadas.
  static void reconciliarDerivacoesDiarias(SemobDataset ds) {
    const periodicidadesAlvo = ['Mensal', 'Quinzenal'];

    // 1. Resumos Diários
    final resumosSnapshot = List<ResumoDiario>.from(ds.resumos);
    for (final item in resumosSnapshot) {
      for (final perAlvo in periodicidadesAlvo) {
        if (item.periodicidade == perAlvo) continue;
        final jaExiste = ds.resumos.any(
          (r) => r.data == item.data && r.periodicidade == perAlvo,
        );
        if (!jaExiste) {
          ds.resumos.add(item.copiarParaPeriodicidade(perAlvo, calculadoViaDiario: true));
          ds.registrosDerivadosViaDiario++;
        }
      }
    }

    // 2. Passageiros Diários
    final passSnapshot = List<PassageiroDiario>.from(ds.passageiros);
    for (final item in passSnapshot) {
      for (final perAlvo in periodicidadesAlvo) {
        if (item.periodicidade == perAlvo) continue;
        final jaExiste = ds.passageiros.any(
          (p) => p.data == item.data && p.periodicidade == perAlvo,
        );
        if (!jaExiste) {
          ds.passageiros.add(item.copiarParaPeriodicidade(perAlvo, calculadoViaDiario: true));
          ds.registrosDerivadosViaDiario++;
        }
      }
    }

    // 3. FCV por Turno
    final fcvSnapshot = List<FcvDiario>.from(ds.fcv);
    for (final item in fcvSnapshot) {
      for (final perAlvo in periodicidadesAlvo) {
        if (item.periodicidade == perAlvo) continue;
        final jaExiste = ds.fcv.any(
          (f) => f.data == item.data && f.periodicidade == perAlvo,
        );
        if (!jaExiste) {
          ds.fcv.add(item.copiarParaPeriodicidade(perAlvo, calculadoViaDiario: true));
          ds.registrosDerivadosViaDiario++;
        }
      }
    }

    // 4. Faixas Horárias
    final fxSnapshot = List<FaixaHorariaItem>.from(ds.faixasHorarias);
    for (final item in fxSnapshot) {
      for (final perAlvo in periodicidadesAlvo) {
        if (item.periodicidade == perAlvo) continue;
        final jaExiste = ds.faixasHorarias.any(
          (f) =>
              f.data == item.data &&
              f.linha == item.linha &&
              f.hora == item.hora &&
              f.periodicidade == perAlvo,
        );
        if (!jaExiste) {
          ds.faixasHorarias.add(item.copiarParaPeriodicidade(perAlvo, calculadoViaDiario: true));
          ds.registrosDerivadosViaDiario++;
        }
      }
    }

    // 5. Linhas Diárias
    final linhasSnapshot = List<LinhaDiaria>.from(ds.linhas);
    for (final item in linhasSnapshot) {
      for (final perAlvo in periodicidadesAlvo) {
        if (item.periodicidade == perAlvo) continue;
        final jaExiste = ds.linhas.any(
          (l) => l.data == item.data && l.linha == item.linha && l.periodicidade == perAlvo,
        );
        if (!jaExiste) {
          ds.linhas.add(item.copiarParaPeriodicidade(perAlvo, calculadoViaDiario: true));
          ds.registrosDerivadosViaDiario++;
        }
      }
    }
  }

  static void _registrarDiscrepanciaUnica(SemobDataset ds, DiscrepanciaConsolidacao nova) {
    final jaRegistrada = ds.discrepanciasDetectadas.any(
      (d) =>
          d.data == nova.data &&
          d.categoria == nova.categoria &&
          d.descricao == nova.descricao,
    );
    if (!jaRegistrada) {
      ds.discrepanciasDetectadas.add(nova);
    }
  }

  static void _inserirOuReconciliarResumo(SemobDataset ds, ResumoDiario novo) {
    final idxMesmaPer = ds.resumos.indexWhere(
      (r) => r.data == novo.data && r.periodicidade == novo.periodicidade,
    );
    final idxOutraPer = ds.resumos.indexWhere(
      (r) => r.data == novo.data && r.periodicidade != novo.periodicidade,
    );

    final referencia = idxMesmaPer >= 0
        ? ds.resumos[idxMesmaPer]
        : (idxOutraPer >= 0 ? ds.resumos[idxOutraPer] : null);

    if (referencia != null) {
      final diffs = <String>[];
      if (referencia.viagensProg != novo.viagensProg) {
        diffs.add('Viagens Prog.: diário=${referencia.viagensProg} vs ${novo.periodicidade}=${novo.viagensProg}');
      }
      if (referencia.viagensRealiz != novo.viagensRealiz) {
        diffs.add('Viagens Realiz.: diário=${referencia.viagensRealiz} vs ${novo.periodicidade}=${novo.viagensRealiz}');
      }
      if (referencia.veiculos > 0 && novo.veiculos > 0 && referencia.veiculos != novo.veiculos) {
        diffs.add('Frota: diário=${referencia.veiculos} vs ${novo.periodicidade}=${novo.veiculos}');
      }
      if ((referencia.kmTotal - novo.kmTotal).abs() > 0.05) {
        diffs.add(
          'KM Total: diário=${referencia.kmTotal.toStringAsFixed(2)} vs ${novo.periodicidade}=${novo.kmTotal.toStringAsFixed(2)}',
        );
      }

      if (diffs.isEmpty) {
        // Dados idênticos: ignora duplicação, promove eventual cálculo derivado para confirmado e segue a validação
        ds.registrosIdenticosIgnorados++;
        if (idxMesmaPer >= 0) {
          if (ds.resumos[idxMesmaPer].calculadoViaDiario) {
            ds.resumos[idxMesmaPer] = novo;
          }
          return;
        }
      } else {
        final origemBase = referencia.calculadoViaDiario
            ? 'Cálculo via Diários'
            : 'Base ${referencia.periodicidade}';
        _registrarDiscrepanciaUnica(
          ds,
          DiscrepanciaConsolidacao(
            data: novo.data,
            categoria: 'Resumo Operacional',
            periodicidadeNova: novo.periodicidade,
            periodicidadeBase: origemBase,
            descricao:
                'O HTML ${novo.periodicidade} divergiu de $origemBase em ${novo.data} (${diffs.join(" | ")}).',
          ),
        );
      }
    }

    if (idxMesmaPer >= 0) {
      ds.resumos[idxMesmaPer] = novo;
    } else {
      ds.resumos.add(novo);
    }
  }

  static void _inserirOuReconciliarPassageiro(SemobDataset ds, PassageiroDiario novo) {
    final idxMesmaPer = ds.passageiros.indexWhere(
      (p) => p.data == novo.data && p.periodicidade == novo.periodicidade,
    );
    final idxOutraPer = ds.passageiros.indexWhere(
      (p) => p.data == novo.data && p.periodicidade != novo.periodicidade,
    );

    final referencia = idxMesmaPer >= 0
        ? ds.passageiros[idxMesmaPer]
        : (idxOutraPer >= 0 ? ds.passageiros[idxOutraPer] : null);

    if (referencia != null) {
      final diffs = <String>[];
      if (referencia.catraca != novo.catraca) {
        diffs.add('Catraca: diário=${referencia.catraca} vs ${novo.periodicidade}=${novo.catraca}');
      }
      if (referencia.naoPagantes != novo.naoPagantes) {
        diffs.add('Gratuitos: diário=${referencia.naoPagantes} vs ${novo.periodicidade}=${novo.naoPagantes}');
      }
      if (referencia.totalPassageiros != novo.totalPassageiros) {
        diffs.add(
          'Total Passageiros: diário=${referencia.totalPassageiros} vs ${novo.periodicidade}=${novo.totalPassageiros}',
        );
      }

      if (diffs.isEmpty) {
        ds.registrosIdenticosIgnorados++;
        if (idxMesmaPer >= 0) {
          if (ds.passageiros[idxMesmaPer].calculadoViaDiario) {
            ds.passageiros[idxMesmaPer] = novo;
          }
          return;
        }
      } else {
        final origemBase = referencia.calculadoViaDiario
            ? 'Cálculo via Diários'
            : 'Base ${referencia.periodicidade}';
        _registrarDiscrepanciaUnica(
          ds,
          DiscrepanciaConsolidacao(
            data: novo.data,
            categoria: 'Passageiros',
            periodicidadeNova: novo.periodicidade,
            periodicidadeBase: origemBase,
            descricao:
                'O HTML ${novo.periodicidade} de Passageiros divergiu de $origemBase em ${novo.data} (${diffs.join(" | ")}).',
          ),
        );
      }
    }

    if (idxMesmaPer >= 0) {
      ds.passageiros[idxMesmaPer] = novo;
    } else {
      ds.passageiros.add(novo);
    }
  }

  static void _inserirOuReconciliarFcv(SemobDataset ds, FcvDiario novo) {
    final idxMesmaPer = ds.fcv.indexWhere(
      (f) => f.data == novo.data && f.periodicidade == novo.periodicidade,
    );
    final idxOutraPer = ds.fcv.indexWhere(
      (f) => f.data == novo.data && f.periodicidade != novo.periodicidade,
    );

    final referencia = idxMesmaPer >= 0
        ? ds.fcv[idxMesmaPer]
        : (idxOutraPer >= 0 ? ds.fcv[idxOutraPer] : null);

    if (referencia != null) {
      final diffs = <String>[];
      if (referencia.totalProg != novo.totalProg || referencia.totalRealiz != novo.totalRealiz) {
        diffs.add(
          'Total FCV: diário=${referencia.totalRealiz}/${referencia.totalProg} vs ${novo.periodicidade}=${novo.totalRealiz}/${novo.totalProg}',
        );
      }
      if (referencia.manhaRealiz != novo.manhaRealiz ||
          referencia.tardeRealiz != novo.tardeRealiz ||
          referencia.noiteRealiz != novo.noiteRealiz) {
        diffs.add(
          'Turnos (M/T/N): diário=${referencia.manhaRealiz}/${referencia.tardeRealiz}/${referencia.noiteRealiz} vs ${novo.periodicidade}=${novo.manhaRealiz}/${novo.tardeRealiz}/${novo.noiteRealiz}',
        );
      }

      if (diffs.isEmpty) {
        ds.registrosIdenticosIgnorados++;
        if (idxMesmaPer >= 0) {
          if (ds.fcv[idxMesmaPer].calculadoViaDiario) {
            ds.fcv[idxMesmaPer] = novo;
          }
          return;
        }
      } else {
        final origemBase = referencia.calculadoViaDiario
            ? 'Cálculo via Diários'
            : 'Base ${referencia.periodicidade}';
        _registrarDiscrepanciaUnica(
          ds,
          DiscrepanciaConsolidacao(
            data: novo.data,
            categoria: 'FCV por Período',
            periodicidadeNova: novo.periodicidade,
            periodicidadeBase: origemBase,
            descricao:
                'O HTML ${novo.periodicidade} de FCV divergiu de $origemBase em ${novo.data} (${diffs.join(" | ")}).',
          ),
        );
      }
    }

    if (idxMesmaPer >= 0) {
      ds.fcv[idxMesmaPer] = novo;
    } else {
      ds.fcv.add(novo);
    }
  }

  static void _inserirOuReconciliarFxHr(SemobDataset ds, FaixaHorariaItem novo) {
    final idxMesmaPer = ds.faixasHorarias.indexWhere(
      (f) =>
          f.data == novo.data &&
          f.linha == novo.linha &&
          f.hora == novo.hora &&
          f.periodicidade == novo.periodicidade,
    );
    final idxOutraPer = ds.faixasHorarias.indexWhere(
      (f) =>
          f.data == novo.data &&
          f.linha == novo.linha &&
          f.hora == novo.hora &&
          f.periodicidade != novo.periodicidade,
    );

    final referencia = idxMesmaPer >= 0
        ? ds.faixasHorarias[idxMesmaPer]
        : (idxOutraPer >= 0 ? ds.faixasHorarias[idxOutraPer] : null);

    if (referencia != null) {
      final diffs = <String>[];
      if (referencia.viagens != novo.viagens) {
        diffs.add('Viagens (${novo.hora}h L${novo.linha}): diário=${referencia.viagens} vs ${novo.periodicidade}=${novo.viagens}');
      }
      if (referencia.veiculos != novo.veiculos) {
        diffs.add('Veículos (${novo.hora}h L${novo.linha}): diário=${referencia.veiculos} vs ${novo.periodicidade}=${novo.veiculos}');
      }

      if (diffs.isEmpty) {
        ds.registrosIdenticosIgnorados++;
        if (idxMesmaPer >= 0) {
          if (ds.faixasHorarias[idxMesmaPer].calculadoViaDiario) {
            ds.faixasHorarias[idxMesmaPer] = novo;
          }
          return;
        }
      } else {
        final origemBase = referencia.calculadoViaDiario
            ? 'Cálculo via Diários'
            : 'Base ${referencia.periodicidade}';
        _registrarDiscrepanciaUnica(
          ds,
          DiscrepanciaConsolidacao(
            data: novo.data,
            categoria: 'Faixa Horária (Linha ${novo.linha})',
            periodicidadeNova: novo.periodicidade,
            periodicidadeBase: origemBase,
            descricao:
                'O HTML ${novo.periodicidade} de Faixa Horária divergiu de $origemBase em ${novo.data} (${diffs.join(" | ")}).',
          ),
        );
      }
    }

    if (idxMesmaPer >= 0) {
      ds.faixasHorarias[idxMesmaPer] = novo;
    } else {
      ds.faixasHorarias.add(novo);
    }
  }

  static void _inserirOuReconciliarLinha(SemobDataset ds, LinhaDiaria novo) {
    final idxMesmaPer = ds.linhas.indexWhere(
      (l) => l.data == novo.data && l.linha == novo.linha && l.periodicidade == novo.periodicidade,
    );
    final idxOutraPer = ds.linhas.indexWhere(
      (l) => l.data == novo.data && l.linha == novo.linha && l.periodicidade != novo.periodicidade,
    );

    final referencia = idxMesmaPer >= 0
        ? ds.linhas[idxMesmaPer]
        : (idxOutraPer >= 0 ? ds.linhas[idxOutraPer] : null);

    if (referencia != null) {
      final diffs = <String>[];
      if (referencia.viagensRealiz != novo.viagensRealiz) {
        diffs.add(
          'Viagens (Linha ${novo.linha}): diário=${referencia.viagensRealiz} vs ${novo.periodicidade}=${novo.viagensRealiz}',
        );
      }
      if ((referencia.kmTotal - novo.kmTotal).abs() > 0.05) {
        diffs.add(
          'KM (Linha ${novo.linha}): diário=${referencia.kmTotal.toStringAsFixed(2)} vs ${novo.periodicidade}=${novo.kmTotal.toStringAsFixed(2)}',
        );
      }

      if (diffs.isEmpty) {
        ds.registrosIdenticosIgnorados++;
        if (idxMesmaPer >= 0) {
          if (ds.linhas[idxMesmaPer].calculadoViaDiario) {
            ds.linhas[idxMesmaPer] = novo;
          }
          return;
        }
      } else {
        final origemBase = referencia.calculadoViaDiario
            ? 'Cálculo via Diários'
            : 'Base ${referencia.periodicidade}';
        _registrarDiscrepanciaUnica(
          ds,
          DiscrepanciaConsolidacao(
            data: novo.data,
            categoria: 'Linha ${novo.linha}',
            periodicidadeNova: novo.periodicidade,
            periodicidadeBase: origemBase,
            descricao:
                'O HTML ${novo.periodicidade} de Linhas divergiu de $origemBase em ${novo.data} (${diffs.join(" | ")}).',
          ),
        );
      }
    }

    if (idxMesmaPer >= 0) {
      ds.linhas[idxMesmaPer] = novo;
    } else {
      ds.linhas.add(novo);
    }
  }

  /// Envia um único `ArquivoLido` para o backend processar e salvar no MongoDB.
  static Future<ResultadoProcessamentoHtml> enviarArquivoIndividualParaBackend(
    ArquivoLido arquivo, {
    bool persistirNoBanco = true,
  }) {
    return RelatorioApiService.enviarArquivoHtmlIndividual(
      nomeArquivo: arquivo.nome,
      bytes: arquivo.bytes,
      persistirNoBanco: persistirNoBanco,
    );
  }

  /// Sincroniza os arquivos HTML carregados no `dataset` com o backend e retorna o
  /// `RelatorioConsolidado` gerado pelo servidor. Caso nenhum arquivo local esteja em memória,
  /// solicita o relatório consolidado diretamente do banco de dados do backend
  static Future<RelatorioConsolidado> sincronizarEGerarRelatorio({
    required SemobDataset dataset,
    String agrupamento = 'diario',
    String? dataInicio,
    String? dataFim,
    String? linha,
    double toleranciaDesvioKmPct = 15.0,
    double limiarFcv = 0.98,
    double limiarKmImprodPct = 10.0,
    bool enviarArquivosEmMemoria = true,
  }) async {
    if (enviarArquivosEmMemoria && dataset.arquivosHtmlCarregados.isNotEmpty) {
      final resultadoLote = await RelatorioApiService.enviarLoteArquivosEGerarRelatorio(
        arquivos: dataset.arquivosHtmlCarregados,
        agrupamento: agrupamento,
        dataInicio: dataInicio,
        dataFim: dataFim,
        linha: linha,
        toleranciaDesvioKmPct: toleranciaDesvioKmPct,
        limiarFcv: limiarFcv,
        limiarKmImprodPct: limiarKmImprodPct,
      );
      dataset.ultimoUploadIntegrado = resultadoLote;
      dataset.ultimoRelatorioBackend = resultadoLote.relatorio;
      return resultadoLote.relatorio;
    }

    final relatorio = await RelatorioApiService.gerarRelatorioConsolidado(
      agrupamento: agrupamento,
      dataInicio: dataInicio,
      dataFim: dataFim,
      linha: linha,
      toleranciaDesvioKmPct: toleranciaDesvioKmPct,
      limiarFcv: limiarFcv,
      limiarKmImprodPct: limiarKmImprodPct,
    );
    dataset.ultimoRelatorioBackend = relatorio;
    return relatorio;
  }

  static void _processarArquivoIndividual({
    required String nomeArquivo,
    required String caminhoCompleto,
    required List<int> bytes,
    required SemobDataset dataset,
  }) {
    final nome = nomeArquivo.toLowerCase();

    String htmlStr;
    try {
      htmlStr = utf8.decode(bytes);
    } catch (_) {
      htmlStr = latin1.decode(bytes);
    }

    final caminhoNorm = caminhoCompleto.replaceAll('\\', '/');
    final periodicidade = (caminhoNorm.toLowerCase().contains('quinzenal') ||
            nome.contains('quinzenal'))
        ? 'Quinzenal'
        : 'Mensal';

    final mesAno = _inferirMesAno(caminhoNorm, nome, htmlStr);

    if (nome.contains('passageiro')) {
      _parsePassageiros(htmlStr, mesAno, periodicidade, dataset);
    } else if (nome.contains('fcv')) {
      _parseFcv(htmlStr, mesAno, periodicidade, dataset);
    } else if (nome.contains('fxhr') || nome.contains('fx_hr')) {
      _parseFxHr(htmlStr, mesAno, periodicidade, dataset);
    } else if (nome.contains('linhas')) {
      _parseLinhas(htmlStr, mesAno, periodicidade, dataset);
    } else if (RegExp(r'(mensal|quinzenal)[_\s-]*\d{6}').hasMatch(nome)) {
      _parseResumoGeral(htmlStr, mesAno, periodicidade, dataset);
    }
  }

  static String _inferirMesAno(String path, String filename, String htmlStr) {
    final lower = '$path/$filename'.toLowerCase();
    if (lower.contains('julho') || lower.contains('202607')) return 'Julho/2026';
    if (lower.contains('setembro') || lower.contains('202609')) return 'Setembro/2026';
    if (lower.contains('agosto') || lower.contains('202608')) return 'Agosto/2026';

    final matchData = RegExp(r'\b\d{2}/(07|08|09)/2026\b').firstMatch(htmlStr);
    if (matchData != null) {
      if (matchData.group(1) == '07') return 'Julho/2026';
      if (matchData.group(1) == '08') return 'Agosto/2026';
      if (matchData.group(1) == '09') return 'Setembro/2026';
    }
    return 'Agosto/2026';
  }

  static List<List<String>> _extrairLinhasTabelaDados(String htmlContent, int minCols) {
    final doc = html_parser.parse(htmlContent);
    final tabelas = doc.querySelectorAll('table.data');
    final resultado = <List<String>>[];

    for (final tab in tabelas) {
      final ths = tab.querySelectorAll('th');
      if (ths.length < minCols) continue;

      for (final tr in tab.querySelectorAll('tr')) {
        final tds = tr.querySelectorAll('td');
        if (tds.length < minCols) continue;
        final valores = tds.map((e) => e.text.trim()).toList();
        final primeiro = valores[0].toLowerCase();
        final segundo = valores.length > 1 ? valores[1].toLowerCase() : '';
        if (primeiro.isEmpty ||
            primeiro.contains('total') ||
            primeiro.contains('gerado') ||
            primeiro.contains('smart') ||
            segundo.contains('total')) {
          continue;
        }
        resultado.add(valores);
      }
    }
    return resultado;
  }

  static void _parseResumoGeral(String html, String mesAno, String per, SemobDataset ds) {
    final rows = _extrairLinhasTabelaDados(html, 10);
    for (final r in rows) {
      final dt = _parseDataBR(r[0]);
      if (dt == null) continue;
      _inserirOuReconciliarResumo(
        ds,
        ResumoDiario(
          mesAno: mesAno,
          periodicidade: per,
          data: r[0],
          dateTime: dt,
          weekday: dt.weekday,
          veiculos: _toInt(r[2]),
          maxVeicFaixa: _toInt(r[3]),
          viagensProg: _toInt(r[4]),
          viagensRealiz: _toInt(r[5]),
          difViagens: _toInt(r[6]),
          kmProd: _toDouble(r[7]),
          kmImprod: _toDouble(r[8]),
          kmTotal: _toDouble(r[9]),
        ),
      );
    }
  }

  static void _parsePassageiros(String html, String mesAnoPadrao, String per, SemobDataset ds) {
    final rows = _extrairLinhasTabelaDados(html, 6);
    for (final r in rows) {
      final mesRaw = r[0];
      final diaRaw = r[1].padLeft(2, '0');
      final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(mesRaw);
      if (match == null) continue;
      final dataBR = '$diaRaw/${match.group(2)}/${match.group(1)}';
      final dt = _parseDataBR(dataBR);
      if (dt == null) continue;

      String mesLabel = mesAnoPadrao;
      if (match.group(2) == '07') mesLabel = 'Julho/2026';
      if (match.group(2) == '08') mesLabel = 'Agosto/2026';
      if (match.group(2) == '09') mesLabel = 'Setembro/2026';

      _inserirOuReconciliarPassageiro(
        ds,
        PassageiroDiario(
          mesAno: mesLabel,
          periodicidade: per,
          data: dataBR,
          dateTime: dt,
          weekday: dt.weekday,
          catraca: _toInt(r[2]),
          antecipados: _toInt(r[3]),
          naoPagantes: _toInt(r[4]),
          totalPassageiros: _toInt(r[5]),
        ),
      );
    }
  }

  static void _parseFcv(String html, String mesAno, String per, SemobDataset ds) {
    final rows = _extrairLinhasTabelaDados(html, 9);
    for (final r in rows) {
      final dt = _parseDataBR(r[0]);
      if (dt == null) continue;
      _inserirOuReconciliarFcv(
        ds,
        FcvDiario(
          mesAno: mesAno,
          periodicidade: per,
          data: r[0],
          dateTime: dt,
          weekday: dt.weekday,
          manhaProg: _toInt(r[1]),
          manhaRealiz: _toInt(r[2]),
          tardeProg: _toInt(r[3]),
          tardeRealiz: _toInt(r[4]),
          noiteProg: _toInt(r[5]),
          noiteRealiz: _toInt(r[6]),
          totalProg: _toInt(r[7]),
          totalRealiz: _toInt(r[8]),
        ),
      );
    }
  }

  static void _parseFxHr(String html, String mesAno, String per, SemobDataset ds) {
    final rows = _extrairLinhasTabelaDados(html, 6);
    for (final r in rows) {
      final dt = _parseDataBR(r[0]);
      if (dt == null) continue;
      final fx = r[2];
      final hora = int.tryParse(fx.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      _inserirOuReconciliarFxHr(
        ds,
        FaixaHorariaItem(
          mesAno: mesAno,
          periodicidade: per,
          data: r[0],
          dateTime: dt,
          weekday: dt.weekday,
          linha: r[1].padLeft(2, '0'),
          hora: hora,
          faixaTexto: fx,
          veiculos: _toInt(r[3]),
          viagens: _toInt(r[4]),
          partidas: r[5],
        ),
      );
    }
  }

  static void _parseLinhas(String html, String mesAno, String per, SemobDataset ds) {
    final doc = html_parser.parse(html);
    final tabelas = doc.querySelectorAll('table.data');

    for (final tab in tabelas) {
      final ths = tab.querySelectorAll('th').map((e) => e.text.trim().toLowerCase()).toList();
      if (ths.length < 4) continue;

      final idxData = ths.indexWhere((h) => h.contains('data'));
      final idxLinha = ths.indexWhere((h) => h.contains('linha'));
      final idxProg = ths.indexWhere((h) => h.contains('progr'));
      final idxReal = ths.indexWhere((h) => h.contains('realiz') || h.contains('nrviagens') || h == 'viagens');
      final idxKm = ths.indexWhere((h) => h.contains('kmtotal') || h.contains('km_total') || h == 'km');

      if (idxData == -1 || idxLinha == -1) continue;

      for (final tr in tab.querySelectorAll('tr')) {
        final tds = tr.querySelectorAll('td').map((e) => e.text.trim()).toList();
        if (tds.length < ths.length) continue;
        final dt = _parseDataBR(tds[idxData]);
        if (dt == null) continue;

        final real = idxReal != -1 ? _toInt(tds[idxReal]) : 0;
        final prog = idxProg != -1 ? _toInt(tds[idxProg]) : real;
        final km = idxKm != -1 ? _toDouble(tds[idxKm]) : 0.0;

        _inserirOuReconciliarLinha(
          ds,
          LinhaDiaria(
            mesAno: mesAno,
            periodicidade: per,
            data: tds[idxData],
            dateTime: dt,
            weekday: dt.weekday,
            linha: tds[idxLinha].padLeft(2, '0'),
            viagensProg: prog,
            viagensRealiz: real,
            kmTotal: km,
          ),
        );
      }
    }
  }

  static DateTime? parseDataBR(String s) {
    final p = s.trim().split('/');
    if (p.length != 3) return null;
    final d = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final y = int.tryParse(p[2]);
    if (d == null || m == null || y == null) return null;
    return DateTime(y, m, d);
  }

  static DateTime? _parseDataBR(String s) => parseDataBR(s);

  static int _toInt(String s) => _toDouble(s).round();

  static double _toDouble(String s) {
    final limpo = s.replaceAll('.', '').replaceAll(',', '.').trim();
    return double.tryParse(limpo) ?? 0.0;
  }
}
