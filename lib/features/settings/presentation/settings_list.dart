import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'settings_widgets.dart';
import 'settings_row_layout.dart';

/// A fixed header and an independently scrolling, lazily built list.
class SettingsList extends StatefulWidget {
  const SettingsList({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    required this.empty,
    this.actions = const [],
    this.itemExtent,
    this.findChildIndexCallback,
  });

  final String title;
  final List<Widget> actions;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget empty;
  final double? itemExtent;
  final ChildIndexGetter? findChildIndexCallback;

  @override
  State<SettingsList> createState() => _SettingsListState();
}

class _SettingsListState extends State<SettingsList> {
  final _scroll = ScrollController();
  final _bodyKey = GlobalKey();
  double? _height;

  void _fitViewport() {
    if (!mounted) return;
    final body = _bodyKey.currentContext?.findRenderObject();
    if (body is! RenderBox || !body.attached) return;
    final viewport = RenderAbstractViewport.maybeOf(body);
    final outer = Scrollable.maybeOf(context)?.position;
    double remaining;
    if (viewport != null && outer != null && outer.hasViewportDimension) {
      var bottomPadding = 0.0;
      for (
        var parent = body.parent;
        parent != null && parent != viewport;
        parent = parent.parent
      ) {
        if (parent is RenderPadding) {
          bottomPadding += parent.padding
              .resolve(Directionality.of(context))
              .bottom;
        }
      }
      remaining =
          outer.viewportDimension -
          viewport.getOffsetToReveal(body, 0).offset -
          bottomPadding;
    } else {
      remaining =
          MediaQuery.sizeOf(context).height - body.localToGlobal(.zero).dy;
    }
    final height = math.max(240.0, remaining);
    if (_height == null || (_height! - height).abs() > .5) {
      setState(() => _height = height);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsSurface(
    padding: .zero,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final windowHeight = MediaQuery.sizeOf(context).height;
        if (!constraints.hasBoundedHeight) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitViewport());
        }
        final body = widget.itemCount == 0
            ? Center(
                child: Padding(padding: const .all(20), child: widget.empty),
              )
            : Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: ListView.builder(
                    controller: _scroll,
                    primary: false,
                    padding: .zero,
                    itemCount: widget.itemCount,
                    itemExtent: widget.itemExtent,
                    findChildIndexCallback: widget.findChildIndexCallback,
                    itemBuilder: widget.itemBuilder,
                  ),
                ),
              );
        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const .all(20),
              child: _ListHeader(title: widget.title, actions: widget.actions),
            ),
            const Divider(height: 1),
            if (constraints.hasBoundedHeight)
              Expanded(child: body)
            else
              SizedBox(
                key: _bodyKey,
                height: _height ?? math.max(240, windowHeight * .5),
                child: body,
              ),
          ],
        );
      },
    ),
  );
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.title, required this.actions});
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final label = Text(title, style: Theme.of(context).textTheme.titleMedium);
    if (actions.isEmpty) return label;
    return SettingsRowLayout(
      left: label,
      right: Wrap(
        alignment: .end,
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: .center,
        children: actions,
      ),
    );
  }
}
