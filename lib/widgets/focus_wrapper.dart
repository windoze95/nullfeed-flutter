import 'package:flutter/material.dart';
import '../config/theme.dart';

/// A wrapper widget that provides tvOS focus engine integration.
/// On tvOS, this widget responds to Siri Remote focus/swipe navigation
/// by scaling up and adding a highlight border when focused.
class FocusWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final bool autofocus;
  final double focusScale;

  const FocusWrapper({
    super.key,
    required this.child,
    this.onSelect,
    this.autofocus = false,
    this.focusScale = 1.05,
  });

  @override
  State<FocusWrapper> createState() => _FocusWrapperState();
}

class _FocusWrapperState extends State<FocusWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.focusScale,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    setState(() => _isFocused = focused);
    if (focused) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      onKeyEvent: (node, event) {
        // Handle select/enter key on tvOS
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.select) {
          widget.onSelect?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: _isFocused
                  ? Border.all(
                      color: NullFeedTheme.primaryColor,
                      width: 3,
                    )
                  : null,
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: NullFeedTheme.primaryColor.withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
