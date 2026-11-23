import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'theme.dart';

/// Componentes de interface pequenos e reutilizados por todas as telas.

/// Intercala [spacing] entre os filhos.
List<Widget> spaced(List<Widget> children, double spacing) => [
  for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: spacing), children[i]],
];

/// Corpo rolável padrão das telas, com rodapé fixo opcional.
class ScreenBody extends StatelessWidget {
  const ScreenBody({super.key, required this.children, this.footer});

  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: spaced(children, 24)),
        ),
        if (footer != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: p.bg,
              border: Border(top: BorderSide(color: p.border, width: 0.5)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(padding: const EdgeInsets.all(16), child: footer),
            ),
          ),
      ],
    );
  }
}

class Section extends StatelessWidget {
  const Section({super.key, this.title, this.aside, required this.children});

  final String? title;
  final Widget? aside;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
            // Wrap: com fonte grande, o valor ao lado desce para a linha de baixo.
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  title!,
                  style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                ?aside,
              ],
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.border, width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}

/// Linha "rótulo ... valor" com números tabulares.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border, width: 0.5)),
            ),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: p.textMuted, fontSize: 15)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w500, fontFeatures: tabular),
            ),
          ),
        ],
      ),
    );
  }
}

enum ButtonVariant { primary, secondary, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.large = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final IconData? icon;
  final bool loading;

  /// Alvo de 72 px e texto maior, para o modo simples.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (bg, fg, border) = switch (variant) {
      ButtonVariant.primary => (p.accent, p.onAccent, p.accent),
      ButtonVariant.secondary => (p.surface, p.text, p.border),
      ButtonVariant.danger => (p.surface, p.danger, p.danger),
    };
    final leading = loading
        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        : icon == null
        ? null
        : Icon(icon, size: large ? 26 : 20, color: fg);
    return SizedBox(
      height: large ? 72 : 54,
      width: double.infinity,
      child: TextButton(
        onPressed: loading ? null : onPressed,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.5),
          disabledForegroundColor: fg.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: border),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 8)],
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: large ? 20 : 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botão que só dispara depois de segurado por [hold]. Evita encerrar a
/// sessão com um toque acidental (tremor, celular no bolso). Com leitor de
/// tela, o toque duplo chama [onAccessibleTap], que deve pedir confirmação.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.label,
    required this.holdingLabel,
    required this.onConfirmed,
    required this.onAccessibleTap,
    this.hold = const Duration(seconds: 2),
  });

  final String label;
  final String holdingLabel;
  final VoidCallback onConfirmed;
  final VoidCallback onAccessibleTap;
  final Duration hold;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(vsync: this, duration: widget.hold)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _progress.reset();
        widget.onConfirmed();
      }
    });

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _release() {
    if (_progress.isAnimating) _progress.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onAccessibleTap,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) => _progress.forward(),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            final holding = _progress.value > 0;
            return Container(
              height: 72,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.danger, width: 1.5),
              ),
              child: Stack(
                children: [
                  // Preenchimento que cresce enquanto o dedo segura.
                  FractionallySizedBox(
                    widthFactor: _progress.value,
                    heightFactor: 1,
                    child: ColoredBox(color: p.danger.withValues(alpha: 0.18)),
                  ),
                  Center(
                    child: Text(
                      holding ? widget.holdingLabel : widget.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.danger, fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class Muted extends StatelessWidget {
  const Muted(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: Palette.of(context).textMuted, fontSize: 14, height: 1.5));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  // Botões de largura total e empilhados, com espaço entre eles: alvo grande
  // para quem tem tremor e sem a ação destrutiva colada na de cancelar.
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(fontSize: 16, height: 1.4)),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(label: cancelLabel, onPressed: () => Navigator.pop(context, false)),
            const SizedBox(height: 16),
            AppButton(
              label: confirmLabel,
              variant: ButtonVariant.danger,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Mostra uma frase para a pessoa e manda o detalhe técnico só para o log.
void showError(BuildContext context, String message, [Object? error]) {
  if (error != null) debugPrint('$message ($error)');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Bloco de erro com frase humana, detalhe técnico recolhido e ação de repetir.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.title, required this.message, this.error, this.onRetry});

  final String title;
  final String message;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Section(
      title: title,
      children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Muted(message)),
        if (error != null)
          ExpansionTile(
            title: const Text('Ver detalhes', style: TextStyle(fontSize: 15)),
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            children: [Align(alignment: Alignment.centerLeft, child: SelectableText('$error'))],
          ),
        if (onRetry != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: AppButton(label: 'Tentar de novo', icon: LucideIcons.refreshCw, onPressed: onRetry),
          ),
      ],
    );
  }
}
