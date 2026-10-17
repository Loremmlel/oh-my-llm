import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_input_label.dart';

/// 沿用原生文本编辑与表单校验，仅统一外置标签。
class AppTextField extends StatefulWidget {
  const AppTextField({
    this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.initialValue,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.autofocus = false,
    this.readOnly = false,
    this.enabled,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.expands = false,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.style,
    super.key,
  }) : _form = false;

  const AppTextField.form({
    this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.initialValue,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.autofocus = false,
    this.readOnly = false,
    this.enabled,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.expands = false,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.style,
    super.key,
  }) : _form = true;

  final bool _form;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final String? initialValue;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;
  final bool autofocus, readOnly, autocorrect, enableSuggestions, expands;
  final bool? enabled;
  final int? maxLines, minLines, maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged, onSubmitted;
  final VoidCallback? onTap;
  final TextStyle? style;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focus = widget.focusNode ?? _focus;
    final decoration = AppInputLabel.fieldDecoration(widget.decoration);
    final field = widget._form
        ? TextFormField(
            controller: widget.controller,
            focusNode: focus,
            decoration: decoration,
            initialValue: widget.initialValue,
            validator: widget.validator,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            textCapitalization: widget.textCapitalization,
            textAlign: widget.textAlign,
            textAlignVertical: widget.textAlignVertical,
            autofocus: widget.autofocus,
            readOnly: widget.readOnly,
            enabled: widget.enabled,
            autocorrect: widget.autocorrect,
            enableSuggestions: widget.enableSuggestions,
            maxLines: widget.maxLines,
            minLines: widget.minLines,
            maxLength: widget.maxLength,
            expands: widget.expands,
            inputFormatters: widget.inputFormatters,
            onChanged: widget.onChanged,
            onFieldSubmitted: widget.onSubmitted,
            onTap: widget.onTap,
            style: widget.style,
          )
        : TextField(
            controller: widget.controller,
            focusNode: focus,
            decoration: decoration,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            textCapitalization: widget.textCapitalization,
            textAlign: widget.textAlign,
            textAlignVertical: widget.textAlignVertical,
            autofocus: widget.autofocus,
            readOnly: widget.readOnly,
            enabled: widget.enabled,
            autocorrect: widget.autocorrect,
            enableSuggestions: widget.enableSuggestions,
            maxLines: widget.maxLines,
            minLines: widget.minLines,
            maxLength: widget.maxLength,
            expands: widget.expands,
            inputFormatters: widget.inputFormatters,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            onTap: widget.onTap,
            style: widget.style,
          );
    return AppInputLabel(
      decoration: widget.decoration,
      expands: widget.expands,
      onLabelTap: widget.enabled == false ? null : focus.requestFocus,
      child: field,
    );
  }
}
