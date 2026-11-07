import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Label on the left and control on the right. A long label wraps beside the
/// control while it keeps a readable width, and stacks above it when narrow.
class SettingsRowLayout extends MultiChildRenderObjectWidget {
  SettingsRowLayout({super.key, required Widget left, required Widget right})
    : super(children: [left, right]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSettingsRowLayout();
}

class _SettingsRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSettingsRowLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SettingsRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SettingsRowParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SettingsRowParentData) {
      child.parentData = _SettingsRowParentData();
    }
  }

  static const _gap = 16.0;
  static const _stackGap = 12.0;

  /// Narrower labels stack above their control instead of wrapping beside it.
  static const _minLabelWidth = 280.0;

  /// Returns the label constraints for a side-by-side row, or null to stack.
  BoxConstraints? _besideConstraints(
    Size naturalLeft,
    Size right,
    BoxConstraints constraints,
  ) {
    if (!constraints.hasBoundedWidth) return const BoxConstraints();
    final available = constraints.maxWidth - right.width - _gap;
    return naturalLeft.width <= available || available >= _minLabelWidth
        ? BoxConstraints(maxWidth: available)
        : null;
  }

  Size _size(Size left, Size right, bool beside, BoxConstraints constraints) =>
      constraints.constrain(
        Size(
          constraints.hasBoundedWidth
              ? constraints.maxWidth
              : left.width + _gap + right.width,
          beside
              ? math.max(left.height, right.height)
              : left.height + _stackGap + right.height,
        ),
      );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final full = BoxConstraints(maxWidth: constraints.maxWidth);
    final right = lastChild!.getDryLayout(full);
    final natural = firstChild!.getDryLayout(full);
    final beside = _besideConstraints(natural, right, constraints);
    final left = beside == null ? natural : firstChild!.getDryLayout(beside);
    return _size(left, right, beside != null, constraints);
  }

  @override
  void performLayout() {
    final left = firstChild!;
    final right = lastChild!;
    final full = BoxConstraints(maxWidth: constraints.maxWidth);
    right.layout(full, parentUsesSize: true);
    left.layout(full, parentUsesSize: true);
    final beside = _besideConstraints(left.size, right.size, constraints);
    if (beside != null && left.size.width > beside.maxWidth) {
      left.layout(beside, parentUsesSize: true);
    }
    size = _size(left.size, right.size, beside != null, constraints);
    (left.parentData! as _SettingsRowParentData).offset = Offset(
      0,
      beside == null ? 0 : (size.height - left.size.height) / 2,
    );
    (right.parentData! as _SettingsRowParentData).offset = Offset(
      size.width - right.size.width,
      beside == null
          ? left.size.height + _stackGap
          : (size.height - right.size.height) / 2,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
