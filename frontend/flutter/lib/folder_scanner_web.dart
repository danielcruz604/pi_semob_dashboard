class ArquivoLido {
  final String nome;
  final String caminho;
  final List<int> bytes;

  ArquivoLido({
    required this.nome,
    required this.caminho,
    required this.bytes,
  });
}

Future<List<ArquivoLido>> escanearPastaNativa(
  String caminhoEscolhido,
  bool Function(String nome) filtroNome,
) async {
  // Na Web o carregamento é feito via seleção de arquivos (XFile)
  return [];
}