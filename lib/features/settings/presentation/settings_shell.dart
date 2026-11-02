import '../../applications/presentation/external_tools_page.dart';
import '../../network/application/network_controller.dart';
import '../../network/presentation/known_networks_page.dart';
import '../../network/presentation/network_status_page.dart';
import '../../network/presentation/wifi_page.dart';
import '../../applications/application/applications_controller.dart';
import '../../applications/presentation/appimages_page.dart';
import '../../applications/presentation/installed_apps_page.dart';
import '../../default_apps/application/default_apps_controller.dart';
import '../../default_apps/presentation/default_apps_page.dart';

import 'dart:math' as math;

import 'package:remya_settings_client/settings_contract.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../about/presentation/about_page.dart';
import '../../about/presentation/licenses_view.dart';
import '../../fonts/application/fonts_controller.dart';
import '../../fonts/presentation/fonts_page.dart';
import '../domain/settings_catalog.dart';
import 'settings_content.dart';
import '../../integration/settings_scheduler.dart';
import 'settings_widgets.dart';

class SettingsShell extends StatefulWidget {
  const SettingsShell({
    super.key,
    required this.catalog,
    this.navigation,
    this.scheduler,
    this.status,
    this.topStatus,
    this.systemInformation,
  });
  final SettingsCatalog catalog;
  final SystemInformationReader? systemInformation;
  final Widget? status;
  final Widget? topStatus;
  final SettingsScheduler? scheduler;
  final ValueNotifier<String?>? navigation;

  @override
  State<SettingsShell> createState() => _SettingsShellState();
}

class _SettingsShellState extends State<SettingsShell> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _history = <({String category, String? page})>[];
  String _category = 'home';
  SettingsPageSpec? _page;
  String _query = '';
  bool _searchOpen = false;

  void _focusSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    widget.navigation?.addListener(_externalNavigation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _externalNavigation();
    });
  }

  void _externalNavigation() {
    final target = widget.navigation?.value;
    if (target == null) return;
    if (const {'home', 'about', 'licenses'}.contains(target)) {
      _navigate(target);
    } else {
      _openPage(
        widget.catalog.page(target == 'system-information' ? 'about' : target),
      );
    }
  }

  @override
  void dispose() {
    widget.navigation?.removeListener(_externalNavigation);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _navigate(String category, [SettingsPageSpec? page]) {
    widget.scheduler?.refresh();
    if (!const {'home', 'about', 'licenses'}.contains(category)) {
      page ??= widget.catalog.inCategory(category).first;
    }
    if (_category == category && _page?.id == page?.id && _query.isEmpty) {
      return;
    }
    setState(() {
      _history.add((category: _category, page: _page?.id));
      _category = category;
      _page = page;
      _query = '';
      _searchController.clear();
    });
  }

  void _openPage(SettingsPageSpec page) => _navigate(page.category, page);

  void _back() {
    if (_query.isNotEmpty) {
      setState(() {
        _query = '';
        _searchController.clear();
      });
      return;
    }
    if (_history.isEmpty) return;
    final location = _history.removeLast();
    setState(() {
      _category = location.category;
      _page = location.page == null
          ? null
          : widget.catalog.page(location.page!);
    });
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyF, control: true):
          _focusSearch,
      const SingleActivator(LogicalKeyboardKey.keyE, control: true):
          _focusSearch,
      const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
      const SingleActivator(LogicalKeyboardKey.escape): () {
        _searchFocus.unfocus();
        if (_query.isNotEmpty) _back();
      },
    },
    child: Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              SizedBox(
                width: constraints.maxWidth < 1000 ? 80 : 280,
                child: _sidebar(constraints.maxWidth < 1000),
              ),
              Expanded(
                child: Column(
                  children: [
                    ?widget.topStatus,
                    Expanded(
                      child: Stack(
                        key: const ValueKey('settings-main-content'),
                        fit: .expand,
                        children: [
                          _body(),
                          if (widget.status case final status?)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: status,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _search() => TextField(
    key: const ValueKey('settings-search'),
    controller: _searchController,
    focusNode: _searchFocus,
    decoration: InputDecoration(
      hintText: 'Find a setting',
      prefixIcon: const Icon(Icons.search_rounded, size: 21),
      suffixIcon: _query.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              onPressed: () => setState(() {
                _searchController.clear();
                _query = '';
              }),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      border: const OutlineInputBorder(
        borderSide: .none,
        borderRadius: .all(.circular(18)),
      ),
    ),
    onChanged: (value) => setState(() => _query = value.trim()),
  );

  Widget _sidebar(bool compact) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: .fromLTRB(compact ? 8 : 16, 24, compact ? 8 : 16, 16),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            if (compact)
              IconButton(
                tooltip: 'Find a setting',
                onPressed: () {
                  _focusSearch();
                },
                icon: const Icon(Icons.search_rounded),
              )
            else
              _search(),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: [
                  _navigationTile('home', 'Home', Icons.home_outlined, compact),
                  const SizedBox(height: 6),
                  for (final category in widget.catalog.categories)
                    _navigationTile(
                      category.id,
                      category.title,
                      categoryIcon(category.icon),
                      compact,
                    ),
                ],
              ),
            ),
            const Divider(height: 24),
            _navigationTile(
              'about',
              'About',
              Icons.info_outline_rounded,
              compact,
            ),
            const SizedBox(height: 8),
            if (!compact)
              const Text(
                'Unavailable settings are previews',
                textAlign: .center,
                style: TextStyle(fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }

  Widget _navigationTile(String id, String title, IconData icon, bool compact) {
    final colors = Theme.of(context).colorScheme;
    final selected =
        _category == id || id == 'about' && _category == 'licenses';
    return Padding(
      padding: const .symmetric(vertical: 3),
      child: compact
          ? IconButton.filledTonal(
              key: ValueKey('nav-$id'),
              tooltip: title,
              isSelected: selected,
              style: IconButton.styleFrom(
                backgroundColor: selected
                    ? colors.secondaryContainer
                    : Colors.transparent,
                foregroundColor: selected
                    ? colors.onSecondaryContainer
                    : colors.onSurfaceVariant,
                minimumSize: const Size(48, 48),
              ),
              onPressed: () => _navigate(id),
              icon: Icon(icon, size: 22),
            )
          : ListTile(
              key: ValueKey('nav-$id'),
              selected: selected && _query.isEmpty,
              selectedTileColor: colors.secondaryContainer,
              selectedColor: colors.onSecondaryContainer,
              shape: RoundedRectangleBorder(borderRadius: .circular(18)),
              leading: Icon(icon, size: 22),
              title: Text(title, style: const TextStyle(fontSize: 14)),
              contentPadding: const .symmetric(horizontal: 16),
              minTileHeight: 48,
              onTap: () => _navigate(id),
            ),
    );
  }

  Widget _header() {
    final title = _query.isNotEmpty
        ? 'Search settings'
        : switch (_category) {
            'home' => 'Home',
            'about' => 'About',
            'licenses' => 'Licenses',
            _ => widget.catalog.category(_category).title,
          };
    return Padding(
      padding: .fromLTRB(
        MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
        20,
        MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
        16,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          if (MediaQuery.sizeOf(context).width < 1000 &&
              (_searchOpen || _query.isNotEmpty))
            Padding(padding: const .only(bottom: 16), child: _search()),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: .w600),
          ),
          if (_page != null && _query.isEmpty) ...[
            const SizedBox(height: 16),
            _PageButtonGroup(
              category: widget.catalog.category(_category),
              pages: widget.catalog.inCategory(_category),
              selected: _page!.id,
              onPage: _openPage,
            ),
          ],
        ],
      ),
    );
  }

  Widget _body() {
    if (_category == 'licenses' && _query.isEmpty) {
      return Column(
        children: [
          _header(),
          const Expanded(
            child: Padding(
              padding: .fromLTRB(32, 8, 32, 24),
              child: LicensesView(),
            ),
          ),
        ],
      );
    }
    if (_query.trim().isEmpty &&
        _page?.id == 'installed' &&
        ApplicationsScope.maybeOf(context) != null) {
      return _installedBody(ApplicationsScope.maybeOf(context)!);
    }
    if (_query.trim().isEmpty && _page?.id == 'fonts') {
      if (FontsScope.maybeOf(context) case final controller?) {
        return _fontsBody(_page!, controller);
      }
    }
    final Widget content;
    if (_query.trim().isNotEmpty) {
      final results = widget.catalog.search(_query);
      content = Column(
        crossAxisAlignment: .stretch,
        children: [
          Text('${results.length} pages match "${_query.trim()}"'),
          const SizedBox(height: 16),
          if (results.isEmpty)
            const SettingsSurface(
              child: Column(
                children: [
                  Icon(Icons.search_off_rounded, size: 40),
                  SizedBox(height: 12),
                  Text('No settings found'),
                  SizedBox(height: 8),
                  Text('Try display, mouse, privacy, or a setting name.'),
                ],
              ),
            ),
          if (results.isNotEmpty)
            SettingsSurface(
              padding: .zero,
              child: Column(
                children: [
                  for (final page in results)
                    PageLink(
                      page: page,
                      icon: categoryIcon(
                        widget.catalog.category(page.category).icon,
                      ),
                      subtitle:
                          '${widget.catalog.category(page.category).title} · ${page.description}',
                      onTap: () => _openPage(page),
                    ),
                ],
              ),
            ),
        ],
      );
    } else if (const {
          'time-more',
          'system-more',
          'appearance-more',
        }.contains(_page?.id) &&
        ApplicationsScope.maybeOf(context) != null) {
      final controller = ApplicationsScope.maybeOf(context)!;
      content = ExternalToolsPage(
        read: () =>
            controller.readExternalTools(_page!.id.split('-more').first),
        open: controller.openExternalTool,
      );
    } else if (_page?.id == 'appimages' &&
        ApplicationsScope.maybeOf(context)?.appImages != null) {
      content = AppImagesPage(
        controller: ApplicationsScope.maybeOf(context)!.appImages!,
      );
    } else if (_networkPage(_page) case final page?) {
      content = page;
    } else if (_page?.id == 'defaults' &&
        DefaultAppsScope.maybeOf(context) != null) {
      content = DefaultAppsPage(
        key: const ValueKey('default-apps-page'),
        controller: DefaultAppsScope.maybeOf(context)!,
      );
    } else if (_page != null) {
      content = SettingsDetail(
        catalog: widget.catalog,
        page: _page!,
        systemInformation: widget.systemInformation,
        onPage: _openPage,
      );
    } else if (_category == 'home') {
      content = SettingsHome(catalog: widget.catalog, onCategory: _navigate);
    } else if (_category == 'about') {
      content = AboutPage(
        catalog: widget.catalog,
        onLicenses: () => _navigate('licenses'),
      );
    } else {
      content = const SizedBox.shrink();
    }
    return SelectionArea(
      child: SingleChildScrollView(
        key: ValueKey(
          'content-$_category-${_page?.id}-${_query.trim().isNotEmpty}',
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            _header(),
            Padding(
              padding: .fromLTRB(
                MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
                8,
                MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
                widget.status == null ? 40 : 144,
              ),
              child: Align(
                alignment: .topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: content,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _networkPage(SettingsPageSpec? page) {
    final controller = NetworkScope.maybeOf(context);
    if (page == null || controller == null) return null;
    return switch (page.id) {
      'network-status' => NetworkStatusPage(
        controller: controller,
        catalog: widget.catalog,
        page: page,
        onPage: _openPage,
      ),
      'wifi' => WifiPage(
        controller: controller,
        catalog: widget.catalog,
        page: page,
        onPage: _openPage,
      ),
      'known-networks' => KnownNetworksPage(controller: controller, page: page),
      _ => null,
    };
  }

  Widget _installedBody(ApplicationsController controller) {
    final gutter = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 32.0;
    return CustomScrollView(
      key: const ValueKey('content-installed'),
      slivers: [
        SliverToBoxAdapter(child: _header()),
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final side = math.max(
              gutter,
              (constraints.crossAxisExtent - 1080) / 2,
            );
            return SliverPadding(
              padding: .fromLTRB(
                side,
                8,
                side,
                widget.status == null ? 40 : 144,
              ),
              sliver: InstalledAppsPage(
                controller: controller,
                formatDate: controller.formatDate,
              ),
            );
          },
        ),
      ],
    );
  }

  /// Same frame as other pages, on slivers so the long font list stays lazy.
  Widget _fontsBody(SettingsPageSpec page, FontsController controller) {
    final gutter = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 32.0;
    return SelectionArea(
      child: CustomScrollView(
        key: const ValueKey('content-fonts'),
        slivers: [
          SliverToBoxAdapter(child: _header()),
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final side = math.max(
                gutter,
                (constraints.crossAxisExtent - 1080) / 2,
              );
              return SliverPadding(
                padding: .fromLTRB(
                  side,
                  8,
                  side,
                  widget.status == null ? 40 : 144,
                ),
                sliver: FontsPage(page: page, controller: controller),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PageButtonGroup extends StatelessWidget {
  const _PageButtonGroup({
    required this.category,
    required this.pages,
    required this.selected,
    required this.onPage,
  });
  final SettingsCategory category;
  final List<SettingsPageSpec> pages;
  final String selected;
  final ValueChanged<SettingsPageSpec> onPage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // material_ui has no connected button group; use its standard filled buttons.
    return Wrap(
      key: ValueKey('page-buttons-${category.id}'),
      spacing: 2,
      runSpacing: 6,
      children: [
        for (var i = 0; i < pages.length; i++)
          Semantics(
            selected: pages[i].id == selected,
            child: FilledButton.icon(
              key: ValueKey('nav-page-${pages[i].id}'),
              style: FilledButton.styleFrom(
                backgroundColor: pages[i].id == selected
                    ? colors.primary
                    : colors.secondaryContainer,
                foregroundColor: pages[i].id == selected
                    ? colors.onPrimary
                    : colors.onSecondaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: pages[i].id == selected
                      ? .circular(24)
                      : .horizontal(
                          left: .circular(i == 0 ? 24 : 8),
                          right: .circular(i == pages.length - 1 ? 24 : 8),
                        ),
                ),
              ),
              onPressed: () => onPage(pages[i]),
              icon: Icon(pageIcon(pages[i], category), size: 18),
              label: Text(pages[i].title),
            ),
          ),
      ],
    );
  }
}
