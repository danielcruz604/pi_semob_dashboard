import 'package:flutter/material.dart';
import 'relatorio_api_service.dart';

/// Tela de cadastro de novos operadores do sistema SEMOB-SCS.
/// O acesso a esta tela é restrito a usuários com perfil administrador (`gestor` / `admin`).
class CadastroUsuarioPage extends StatefulWidget {
  const CadastroUsuarioPage({super.key});

  @override
  State<CadastroUsuarioPage> createState() => _CadastroUsuarioPageState();
}

class _CadastroUsuarioPageState extends State<CadastroUsuarioPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _cargoController = TextEditingController();

  bool _senhaVisivel = false;
  bool _salvando = false;
  String? _mensagemErro;
  Map<String, dynamic>? _ultimoUsuarioCriado;

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _cargoController.dispose();
    super.dispose();
  }

  Future<void> _submeterCadastro() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _salvando = true;
      _mensagemErro = null;
      _ultimoUsuarioCriado = null;
    });

    try {
      final criado = await RelatorioApiService.cadastrarUsuario(
        nome: _nomeController.text.trim(),
        email: _emailController.text.trim().toLowerCase(),
        senha: _senhaController.text,
        papel: _cargoController.text.trim().toLowerCase(),
      );

      if (!mounted) return;
      setState(() {
        _salvando = false;
        _ultimoUsuarioCriado = criado;
        _nomeController.clear();
        _emailController.clear();
        _senhaController.clear();
        _cargoController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Usuário "${criado['nome']}" cadastrado com sucesso!'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
    } on RelatorioApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _mensagemErro = e.statusCode == 403
            ? 'Acesso negado: apenas administradores (gestor) podem cadastrar novos usuários.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _mensagemErro = 'Erro inesperado ao cadastrar usuário: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final papelAtual = (RelatorioApiService.usuarioLogado?['papel'] ?? '').toString().trim().toLowerCase();
    final ehAdmin = papelAtual == 'gestor' || papelAtual == 'admin';
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF38BDF8), size: 22),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Cadastro de Usuários • SEMOB',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: EdgeInsets.all(isMobile ? 20 : 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: !ehAdmin
                  ? _buildBloqueioAcesso()
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F2FE),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.admin_panel_settings_rounded,
                                  color: Color(0xFF0284C7),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Novo Operador do Sistema',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Preencha os dados abaixo para liberar o acesso ao painel.',
                                      style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),

                          if (_mensagemErro != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline_rounded, size: 18, color: Colors.red.shade700),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _mensagemErro!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.red.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_ultimoUsuarioCriado != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF10B981)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF059669)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Cadastrado: ${_ultimoUsuarioCriado!['nome']} (${_ultimoUsuarioCriado!['email']}) • Cargo: ${_ultimoUsuarioCriado!['papel']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF065F46),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // 1. Nome Completo
                          TextFormField(
                            controller: _nomeController,
                            textCapitalization: TextCapitalization.words,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                            decoration: _inputDecoration(
                              label: 'Nome Completo',
                              hint: 'Ex.: Maria Silva',
                              icone: Icons.person_outline_rounded,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().length < 2) {
                                return 'Informe o nome completo (mínimo 2 caracteres).';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // 2. E-mail
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                            decoration: _inputDecoration(
                              label: 'E-mail Corporativo',
                              hint: 'Ex.: nome.sobrenome@semob.sp.gov.br',
                              icone: Icons.email_outlined,
                            ),
                            validator: (v) {
                              final texto = v?.trim() ?? '';
                              if (texto.isEmpty) return 'Informe o e-mail.';
                              if (!texto.contains('@') || !texto.contains('.')) {
                                return 'Informe um e-mail válido.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // 3. Senha
                          TextFormField(
                            controller: _senhaController,
                            obscureText: !_senhaVisivel,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                            decoration: _inputDecoration(
                              label: 'Senha de Acesso',
                              hint: 'Mínimo de 6 caracteres',
                              icone: Icons.lock_outline_rounded,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _senhaVisivel ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  size: 19,
                                  color: Colors.blueGrey,
                                ),
                                onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.length < 6) {
                                return 'A senha deve ter pelo menos 6 caracteres.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // 4. Cargo (Papel no banco de dados - campo escrito livre)
                          TextFormField(
                            controller: _cargoController,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                            decoration: _inputDecoration(
                              label: 'Cargo (Papel no sistema)',
                              hint: 'Digite o cargo (ex.: gestor, analista, fiscal)',
                              icone: Icons.badge_outlined,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Informe o cargo / papel do usuário.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Nota: O cargo "gestor" concede permissão de administrador para cadastrar novos usuários.',
                            style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                          ),
                          const SizedBox(height: 22),

                          _buildBotoesAcao(),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBotoesAcao() {
    final botaoCadastrar = ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: _salvando ? null : _submeterCadastro,
      icon: _salvando
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.check_rounded, size: 18),
      label: Text(
        _salvando ? 'Cadastrando...' : 'Cadastrar Usuário',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );

    final botaoVoltar = OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: _salvando ? null : () => Navigator.pop(context),
      child: const Text(
        'Voltar ao Painel',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569)),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 380) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              botaoCadastrar,
              const SizedBox(height: 10),
              botaoVoltar,
            ],
          );
        }

        return Row(
          children: [
            Expanded(flex: 2, child: botaoVoltar),
            const SizedBox(width: 12),
            Expanded(flex: 3, child: botaoCadastrar),
          ],
        );
      },
    );
  }

  Widget _buildBloqueioAcesso() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_person_rounded, size: 54, color: Color(0xFFDC2626)),
        const SizedBox(height: 14),
        const Text(
          'Acesso Restrito ao Administrador',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Apenas usuários com perfil de administrador (gestor) têm permissão para cadastrar novos operadores no sistema.',
          style: TextStyle(fontSize: 13, color: Colors.blueGrey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar ao Painel'),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icone,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(fontSize: 13, color: Colors.blueGrey),
      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
      prefixIcon: Icon(icone, size: 20, color: const Color(0xFF0284C7)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }
}