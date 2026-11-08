import 'package:flutter/material.dart';
import '../models/dashboard_models.dart';

class AlertaMobilidadeWidget extends StatelessWidget {
  final AnomaliasResponse anomalias;
  final bool modoTV;

  const AlertaMobilidadeWidget({
    super.key,
    required this.anomalias,
    this.modoTV = false,
  });

  @override
  Widget build(BuildContext context) {
    if (anomalias.totalDesviosOperacionais == 0 &&
        anomalias.totalOcorrenciasViagens == 0) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF10B981)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF059669)),
            const SizedBox(width: 12),
            Text(
              'Operação Regular: Nenhuma anomalia crítica detectada nas linhas de SCS.',
              style: TextStyle(
                color: const Color(0xFF065F46),
                fontWeight: FontWeight.w600,
                fontSize: modoTV ? 16 : 14,
              ),
            ),
          ],
        ),
      );
    }

    final temFalhaCritica = anomalias.desviosOperacionais.any((d) =>
        d.tipo == 'fcv_abaixo_da_meta' ||
        (anomalias.ocorrenciasPorClassificacao['NaoRealizada'] ?? 0) > 0);

    final corTema = temFalhaCritica ? const Color(0xFFDC2626) : const Color(0xFFD97706);
    final corFundo = temFalhaCritica ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(modoTV ? 18 : 14),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: corTema, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: corTema, size: modoTV ? 28 : 22),
              const SizedBox(width: 10),
              Text(
                temFalhaCritica
                    ? 'ALERTA CRÍTICO DE MOBILIDADE • INTERVENÇÃO NECESSÁRIA'
                    : 'ALERTA OPERACIONAL • DESVIOS DETECTADOS',
                style: TextStyle(
                  color: corTema,
                  fontWeight: FontWeight.bold,
                  fontSize: modoTV ? 17 : 14,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: corTema,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${anomalias.totalDesviosOperacionais + anomalias.totalOcorrenciasViagens} OCORRÊNCIAS',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: anomalias.desviosOperacionais.take(3).map((desvio) {
              return Chip(
                backgroundColor: Colors.white,
                side: BorderSide(color: corTema.withOpacity(0.5)),
                label: Text(
                  '${desvio.indicador.toUpperCase()}: ${desvio.descricao}',
                  style: TextStyle(
                    fontSize: modoTV ? 13 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
