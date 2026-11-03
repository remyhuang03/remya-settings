import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Measure both groups at their natural width; wrap only when they cannot fit together.
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

  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: constraints.maxWidth);

  bool _wrap(Size left, Size right, double width) =>
      left.width + 16 + right.width > width;

  Size _measure(Size left, Size right, BoxConstraints constraints) =>
      constraints.constrain(
        Size(
          constraints.hasBoundedWidth
              ? constraints.maxWidth
              : left.width + 16 + right.width,
          left.width + 16 + right.width > constraints.maxWidth
              ? left.height + 12 + right.height
              : math.max(left.height, right.height),
        ),
      );

  @override
  Size computeDryLayout(BoxConstraints constraints) => _measure(
    firstChild!.getDryLayout(_childConstraints(constraints)),
    lastChild!.getDryLayout(_childConstraints(constraints)),
    constraints,
  );

  @override
  void performLayout() {
    final left = firstChild!;
    final right = lastChild!;
    left.layout(_childConstraints(constraints), parentUsesSize: true);
    right.layout(_childConstraints(constraints), parentUsesSize: true);
    size = _measure(left.size, right.size, constraints);
    final wrap = _wrap(left.size, right.size, size.width);
    (left.parentData! as _SettingsRowParentData).offset = Offset(
      0,
      wrap ? 0 : (size.height - left.size.height) / 2,
    );
    (right.parentData! as _SettingsRowParentData).offset = Offset(
      size.width - right.size.width,
      wrap ? left.size.height + 12 : (size.height - right.size.height) / 2,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
