import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 下拉字段共用内容宽度规则；长选项限宽，并提供完整选中值的提示。
class AppDropdownField<T> extends StatefulWidget {
  const AppDropdownField({
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.decoration = const InputDecoration(),
    this.validator,
    this.borderRadius,
    this.isExpanded = true,
    this.isDense = true,
    super.key,
  });

  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final T? initialValue;
  final InputDecoration decoration;
  final FormFieldValidator<T>? validator;
  final BorderRadius? borderRadius;
  final bool isExpanded;
  final bool isDense;

  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends State<AppDropdownField<T>> {
  var _fieldKey = GlobalKey<FormFieldState<T>>();

  @override
  void didUpdateWidget(AppDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _fieldKey.currentState?.value;
    if (selected != null &&
        !widget.items.any((item) => item.value == selected)) {
      // initialValue 的变化由 Material 同步；仅移除内部已选项时重建字段。
      _fieldKey = GlobalKey<FormFieldState<T>>();
    }
  }

  String? _text(Widget child) => switch (child) {
    Text(:final data) => data,
    Tooltip(:final child?) => _text(child),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium;
    final padding =
        (widget.decoration.contentPadding ??
                theme.inputDecorationTheme.contentPadding ??
                const EdgeInsets.symmetric(horizontal: AppSpacing.sm))
            .resolve(Directionality.of(context));
    // 箭头、字段内边距和帮助按钮都需要独立空间，不能挤掉选中值。
    final chromeWidth =
        padding.horizontal +
        24 +
        AppSpacing.sm +
        (widget.decoration.suffixIcon == null
            ? 0
            : AppInteractionSizes.minimumHitTarget);
    var preferredWidth = 112.0;
    for (final text in [
      widget.decoration.labelText,
      widget.decoration.hintText,
      for (final item in widget.items) _text(item.child),
    ]) {
      if (text == null) continue;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      preferredWidth = math.max(preferredWidth, painter.width + chromeWidth);
      painter.dispose();
      if (preferredWidth >= AppContentWidths.shortField) break;
    }
    if (widget.items.any((item) => _text(item.child) == null)) {
      preferredWidth = AppContentWidths.shortField;
    }

    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 1,
        child: SizedBox(
          width: math.min(
            constraints.maxWidth,
            math.min(
              AppContentWidths.shortField,
              preferredWidth.ceilToDouble(),
            ),
          ),
          child: DropdownButtonFormField<T>(
            key: _fieldKey,
            initialValue: widget.initialValue,
            decoration: widget.decoration,
            items: widget.items,
            // 由 FormField 选择提示，避免父级不重建时仍显示旧值。
            selectedItemBuilder: (context) => [
              for (final item in widget.items)
                Tooltip(
                  message: _text(item.child) ?? '',
                  excludeFromSemantics: true,
                  child: item.child,
                ),
            ],
            onChanged: widget.onChanged,
            validator: widget.validator,
            borderRadius:
                widget.borderRadius ?? BorderRadius.circular(AppRadii.sm),
            isExpanded: widget.isExpanded,
            isDense: widget.isDense,
          ),
        ),
      ),
    );
  }
}
