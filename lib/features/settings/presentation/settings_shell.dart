import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../about/presentation/about_page.dart';
import '../domain/settings_catalog.dart';
import 'settings_content.dart';
import 'settings_widgets.dart';

class SettingsShell extends StatefulWidget {
  const SettingsShell({super.key, required this.catalog});
  final SettingsCatalog catalog;

  @override
  State<SettingsShell> createState() => _SettingsShellState();
}

class _SettingsShellState extends State<SettingsShell> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _history = <({String category, String? page})>[];
  final _expandedCategories = <String>{};
  String _category = 'home';
  SettingsPageSpec? _page;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _navigate(String category, [SettingsPageSpec? page]) {
    if (category != 'home' && category != 'about') {
      page ??= widget.catalog.inCategory(category).first;
      _expandedCategories.add(category);
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
    _scaffoldKey.currentState?.closeDrawer();
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
      if (_category != 'home' && _category != 'about') {
        _expandedCategories.add(_category);
      }
      _page = location.page == null
          ? null
          : widget.catalog.page(location.page!);
    });
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyF, control: true):
          _searchFocus.requestFocus,
      const SingleActivator(LogicalKeyboardKey.keyE, control: true):
          _searchFocus.requestFocus,
      const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
      const SingleActivator(LogicalKeyboardKey.escape): () {
        _searchFocus.unfocus();
        if (_query.isNotEmpty) _back();
      },
    },
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        return Scaffold(
          key: _scaffoldKey,
          drawer: wide
              ? null
              : Drawer(width: 292, child: _sidebar(showSearch: false)),
          body: SafeArea(
            child: Row(
              children: [
                if (wide)
                  SizedBox(width: 280, child: _sidebar(showSearch: true)),
                Expanded(
                  child: Column(
                    children: [
                      _header(wide),
                      if (!wide)
                        Padding(
                          padding: const .fromLTRB(20, 0, 20, 12),
                          child: _search(),
                        ),
                      Expanded(child: _body(wide)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

  Widget _sidebar({required bool showSearch}) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const .fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            if (showSearch) ...[_search(), const SizedBox(height: 20)],
            Expanded(
              child: ListView(
                children: [
                  _navigationTile('home', 'Home', Icons.home_outlined),
                  const SizedBox(height: 6),
                  for (final category in widget.catalog.categories)
                    _categoryNavigation(category),
                ],
              ),
            ),
            const Divider(height: 24),
            _navigationTile('about', 'About', Icons.info_outline_rounded),
            const SizedBox(height: 8),
            const Text(
              'System integrations are not implemented',
              textAlign: .center,
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryNavigation(SettingsCategory category) {
    final expanded = _expandedCategories.contains(category.id);
    return Column(
      children: [
        Semantics(
          expanded: expanded,
          child: ListTile(
            key: ValueKey('nav-${category.id}'),
            selected: _category == category.id && _query.isEmpty,
            leading: Icon(categoryIcon(category.icon), size: 22),
            title: Text(category.title, style: const TextStyle(fontSize: 14)),
            shape: RoundedRectangleBorder(borderRadius: .circular(18)),
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() {
              if (expanded) {
                _expandedCategories.remove(category.id);
              } else {
                _expandedCategories.add(category.id);
              }
            }),
          ),
        ),
        if (expanded)
          for (final page in widget.catalog.inCategory(category.id))
            Padding(
              padding: const .only(left: 16),
              child: ListTile(
                key: ValueKey('nav-page-${page.id}'),
                selected: _page?.id == page.id && _query.isEmpty,
                selectedTileColor: Theme.of(context)
                    .colorScheme
                    .secondaryContainer,
                shape: RoundedRectangleBorder(borderRadius: .circular(14)),
                leading: Icon(pageIcon(page, category), size: 20),
                title: Text(page.title, style: const TextStyle(fontSize: 13)),
                minTileHeight: 44,
                onTap: () => _openPage(page),
              ),
            ),
      ],
    );
  }

  Widget _navigationTile(String id, String title, IconData icon) => Padding(
    padding: const .symmetric(vertical: 3),
    child: ListTile(
      key: ValueKey('nav-$id'),
      selected: _category == id && _query.isEmpty,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: .circular(18)),
      leading: Icon(icon, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      contentPadding: const .symmetric(horizontal: 16),
      minTileHeight: 48,
      onTap: () => _navigate(id),
    ),
  );

  Widget _header(bool wide) {
    final title = _query.isNotEmpty
        ? 'Search settings'
        : _page?.title ??
              switch (_category) {
                'home' => 'Home',
                'about' => 'About',
                _ => widget.catalog.category(_category).title,
              };
    return Padding(
      padding: .fromLTRB(wide ? 32 : 12, 20, wide ? 32 : 12, 16),
      child: Row(
        children: [
          if (!wide)
            IconButton(
              tooltip: 'Open navigation',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          IconButton(
            tooltip: 'Back',
            onPressed: _history.isNotEmpty || _query.isNotEmpty ? _back : null,
            icon: const Icon(Icons.arrow_back_rounded, size: 21),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                if (_page != null && _query.isEmpty)
                  Wrap(
                    crossAxisAlignment: .center,
                    children: [
                      InkWell(
                        onTap: () => _navigate(_category),
                        borderRadius: .circular(8),
                        child: Padding(
                          padding: const .symmetric(vertical: 4),
                          child: Text(
                            widget.catalog.category(_category).title,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 14),
                    ],
                  ),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: .w600),
                ),
              ],
            ),
          ),
          if (wide)
            const Chip(
              avatar: Icon(Icons.visibility_outlined, size: 16),
              label: Text('UI preview'),
            ),
        ],
      ),
    );
  }

  Widget _body(bool wide) {
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
    } else if (_page != null) {
      content = SettingsDetail(
        catalog: widget.catalog,
        page: _page!,
        onPage: _openPage,
      );
    } else if (_category == 'home') {
      content = SettingsHome(catalog: widget.catalog, onCategory: _navigate);
    } else if (_category == 'about') {
      content = const AboutPage();
    } else {
      content = const SizedBox.shrink();
    }
    return SelectionArea(
      child: SingleChildScrollView(
        key: ValueKey(
          'content-$_category-${_page?.id}-${_query.trim().isNotEmpty}',
        ),
        padding: .fromLTRB(wide ? 32 : 20, 8, wide ? 32 : 20, 40),
        child: Align(
          alignment: .topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: content,
          ),
        ),
      ),
    );
  }
}
