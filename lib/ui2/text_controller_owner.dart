import 'package:flutter/widgets.dart';

/// Keeps a transient form's controller alive through its closing animation.
/// Navigation results can complete before the dialog/sheet subtree unmounts.
class TextControllerOwner extends StatefulWidget {
  const TextControllerOwner({
    super.key,
    this.initialText = '',
    required this.builder,
  });

  final String initialText;
  final Widget Function(TextEditingController) builder;

  @override
  State<TextControllerOwner> createState() => _TextControllerOwnerState();
}

class _TextControllerOwnerState extends State<TextControllerOwner> {
  late final controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(controller);
}
