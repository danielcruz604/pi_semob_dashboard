from app.services.transporte_metadata import extrair_metadados_nome_arquivo
from app.services.transporte_numbers import limpar_numero_brasileiro
from app.services.transporte_service import processar_html_bytes

def teste_conversao_numerica_brasileira():
    assert limpar_numero_brasileiro("5.168", inteira=True) == 5168
    assert float(limpar_numero_brasileiro("20.434.667,35")) == 20434667.35
    assert float(limpar_numero_brasileiro("-3.380,00")) == -3380.0
    assert limpar_numero_brasileiro("12.5") == 12.5
    assert limpar_numero_brasileiro("12,5") == 12.5

def teste_metadados_mensais_e_quinzenais():
    mensal = extrair_metadados_nome_arquivo("Mensal_Linhas_202608.html")
    assert mensal["periodicidade"] == "mensal"
    assert mensal["ano"] == 2026
    assert mensal["mes"] == 8
    quinzenal = extrair_metadados_nome_arquivo("Quinzenal_Viagens_202609.html")
    assert quinzenal["periodicidade"] == "quinzenal"
    assert quinzenal["ano"] == 2026
    assert quinzenal["mes"] == 9

def teste_leitura_preserva_linha_e_remove_total():
    html = b'''<!DOCTYPE html><html><head><meta charset="cp1252"></head><body>
    <table class="data"><th>Data</th><th>Linha</th><th>kmTotal</th><th>nrViagens</th>
    <tr><td>01/08/2026</td><td>01</td><td>1.062,6</td><td>132</td></tr>
    <tr><td>Total Geral</td><td></td><td>1.062,6</td><td>132</td></tr></table>
    </body></html>'''
    resultado = processar_html_bytes(html, "Mensal_Linhas_202608.html")
    assert resultado["total_registros_validos"] == 1
    assert resultado["dados"][0]["linha"] == "01"
    assert resultado["dados"][0]["km_total"] == 1062.6
    assert resultado["dados"][0]["data"] == "2026-08-01"

def teste_tabela_sem_registros_e_aceita():
    html = b'''<!DOCTYPE html><html><body>
    <table class="data"><th>Data</th><th>Linha</th><th>Prefixo</th><th>Atividade</th>
    </table></body></html>'''
    resultado = processar_html_bytes(html, "Quinzenal_Viag_Ninic_202609.html")
    assert resultado["total_registros_validos"] == 0
    assert resultado["dados"] == []

def teste_multiplos_conjuntos_e_saldo_negativo():
    html = b'''<!DOCTYPE html><html><body>
    <table class="data"><th>Mes</th><th>Dia</th><th>Serie</th><th>Creditos transferidos para cartoes</th><th>Saldo Final</th>
    <tr><td>2026-08</td><td>02</td><td>1</td><td>4.805,00</td><td>20.434.667,35</td></tr>
    </table>
    <table class="data"><th>Mes</th><th>Dia</th><th>Total Vendas</th><th>Total Utilizacao</th><th>Credito Circulante</th>
    <tr><td>2026-08</td><td>01</td><td>0,00</td><td>3.380,00</td><td>-3.380,00</td></tr>
    </table></body></html>'''
    resultado = processar_html_bytes(html, "Saldos_Mensal.html")
    assert resultado["total_registros_validos"] == 1
    assert resultado["total_registros_conjuntos"] == 2
    assert len(resultado["conjuntos_dados"]) == 2
    movimento = resultado["conjuntos_dados"][1]["dados"][0]
    assert movimento["credito_circulante"] == -3380.0
    assert resultado["conjuntos_dados"][0]["dados"][0]["saldo_final"] == 20434667.35