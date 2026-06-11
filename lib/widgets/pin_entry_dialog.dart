import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';

/// Modal dialog that collects a 4-8 digit PIN.
///
/// [onSubmit] is called with the entered PIN. Return null on success — the
/// dialog pops with the PIN as its result — or an error message to show
/// inline (the field shakes and the dialog stays open for another attempt).
class PinEntryDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String confirmLabel;
  final Future<String?> Function(String pin) onSubmit;

  const PinEntryDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.confirmLabel = 'Unlock',
    required this.onSubmit,
  });

  @override
  State<PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<PinEntryDialog>
    with SingleTickerProviderStateMixin {
  static final _pinPattern = RegExp(r'^\d{4,8}$');

  final _controller = TextEditingController();
  late final AnimationController _shakeController;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _shake() => _shakeController.forward(from: 0);

  Future<void> _submit() async {
    final pin = _controller.text;
    if (!_pinPattern.hasMatch(pin)) {
      setState(() => _error = 'Enter a 4-8 digit PIN');
      _shake();
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await widget.onSubmit(pin);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(pin);
      return;
    }
    setState(() {
      _submitting = false;
      _error = error;
    });
    _controller.clear();
    _shake();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NullFeedTheme.cardColor,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.subtitle != null) ...[
            Text(
              widget.subtitle!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
          ],
          AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) {
              final t = _shakeController.value;
              final offset = math.sin(t * math.pi * 4) * 8 * (1 - t);
              return Transform.translate(
                offset: Offset(offset, 0),
                child: child,
              );
            },
            child: TextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: 'PIN',
                counterText: '',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                color: NullFeedTheme.errorColor,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
