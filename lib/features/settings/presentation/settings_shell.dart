import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../about/presentation/about_page.dart';
import '../../about/presentation/licenses_view.dart';
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
    if (!const {'home', 'about', 'licenses'}.contains(category)) {
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
      if (!const {'home', 'about', 'licenses'}.contains(_category)) {
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
    child: Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(width: 280, child: _sidebar()),
            Expanded(
              child: Column(
                children: [
                  _header(),
                  Expanded(child: _body()),
                ],
              ),
            ),
          ],
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

  Widget _sidebar() {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const .fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            _search(),
            const SizedBox(height: 20),
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
              'Unavailable settings are previews',
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
      selected:
          (_category == id || id == 'about' && _category == 'licenses') &&
          _query.isEmpty,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: .circular(18)),
      leading: Icon(icon, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      contentPadding: const .symmetric(horizontal: 16),
      minTileHeight: 48,
      onTap: () => _navigate(id),
    ),
  );

  Widget _header() {
    final title = _query.isNotEmpty
        ? 'Search settings'
        : _page?.title ??
              switch (_category) {
                'home' => 'Home',
                'about' => 'About',
                'licenses' => 'Licenses',
                _ => widget.catalog.category(_category).title,
              };
    return Padding(
      padding: const .fromLTRB(32, 20, 32, 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: .w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_category == 'licenses' && _query.isEmpty) {
      return Padding(
        padding: const .fromLTRB(32, 8, 32, 24),
        child: const LicensesView(),
      );
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
    } else if (_page != null) {
      content = SettingsDetail(
        catalog: widget.catalog,
        page: _page!,
        onPage: _openPage,
      );
    } else if (_category == 'home') {
      content = SettingsHome(catalog: widget.catalog, onCategory: _navigate);
    } else if (_category == 'about') {
      content = AboutPage(onLicenses: () => _navigate('licenses'));
    } else {
      content = const SizedBox.shrink();
    }
    return SelectionArea(
      child: SingleChildScrollView(
        key: ValueKey(
          'content-$_category-${_page?.id}-${_query.trim().isNotEmpty}',
        ),
        padding: const .fromLTRB(32, 8, 32, 40),
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
