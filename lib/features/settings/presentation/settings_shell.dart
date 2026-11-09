import '../../storage/application/storage_controller.dart';
import '../../storage/presentation/storage_page.dart';
import '../../storage/presentation/cleanup_page.dart';
import '../../power/presentation/battery_usage_page.dart';
import '../../power/presentation/power_page.dart';
import '../../camera/application/camera_controller.dart';
import '../../camera/presentation/camera_page.dart';
import '../../updates/application/updates_controller.dart';
import '../../updates/presentation/active_hours_page.dart';
import '../../updates/presentation/updates_page.dart';
import '../../sound/application/sound_controller.dart';
import '../../sound/presentation/sound_page.dart';
import '../../account/application/account_controller.dart';
import '../../account/presentation/account_information_page.dart';
import '../../bluetooth/application/bluetooth_controller.dart';
import '../../bluetooth/presentation/bluetooth_page.dart';
import '../../applications/presentation/external_tools_page.dart';
import '../../network/application/network_controller.dart';
import '../../network/presentation/known_networks_page.dart';
import '../../network/presentation/network_status_page.dart';
import '../../network/presentation/wifi_page.dart';
import '../../network/presentation/airplane_page.dart';
import '../../network/presentation/ethernet_page.dart';
import '../../network/presentation/hotspot_page.dart';
import '../../network/presentation/proxy_page.dart';
import '../../network/presentation/vpn_page.dart';
import '../../applications/application/applications_controller.dart';
import '../../applications/presentation/appimages_page.dart';
import '../../applications/presentation/installed_apps_page.dart';
import '../../default_apps/application/default_apps_controller.dart';
import '../../startup/application/startup_controller.dart';
import '../../startup/presentation/startup_page.dart';
import '../../input/presentation/keyboard_shortcuts_page.dart';
import '../../input/presentation/mouse_page.dart';
import '../../input/presentation/touchpad_page.dart';
import '../../multitasking/presentation/multitasking_page.dart';
import '../../workspaces/presentation/workspaces_page.dart';
import '../../window_appearance/presentation/window_appearance_page.dart';
import '../../animations/presentation/animations_page.dart';
import '../../themes/presentation/cursor_page.dart';
import '../../themes/presentation/themes_page.dart';
import '../../text_size/presentation/text_size_page.dart';
import '../../language/presentation/language_page.dart';
import '../../default_apps/presentation/default_apps_page.dart';

import 'package:remya_settings_client/settings_contract.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../about/presentation/about_page.dart';
import '../../about/presentation/licenses_view.dart';
import '../../appearance/presentation/bar_appearance_page.dart';
import '../../fonts/application/fonts_controller.dart';
import '../../fonts/presentation/fonts_page.dart';
import '../../notifications/presentation/notifications_page.dart';
import '../domain/settings_catalog.dart';
import 'settings_content.dart';
import 'settings_category_group.dart';
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
    this.account,
    this.sound,
    this.client,
    this.cameras,
    this.updates,
  });
  final AccountController? account;
  final SoundController? sound;
  final SettingsClient? client;
  final CameraController? cameras;
  final UpdatesController? updates;
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
                      child: LayoutBuilder(
                        key: const ValueKey('settings-main-content'),
                        builder: (context, constraints) => _body(),
                      ),
                    ),
                    ?widget.status,
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
                  for (final group in SettingsCategoryGroup.values) ...[
                    if (!compact)
                      Padding(
                        padding: const .fromLTRB(12, 14, 8, 8),
                        child: Text(
                          group.title,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      )
                    else
                      const SizedBox(height: 14),
                    Material(
                      key: ValueKey('nav-group-${group.name}'),
                      color: colors.surfaceContainer,
                      borderRadius: .circular(24),
                      clipBehavior: .antiAlias,
                      child: Column(
                        crossAxisAlignment: .stretch,
                        children: [
                          for (final category in group.categories(
                            widget.catalog,
                          ))
                            _navigationTile(
                              category.id,
                              category.title,
                              categoryIcon(category.icon),
                              compact,
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  _navigationTile(
                    'about',
                    'About',
                    Icons.info_outline_rounded,
                    compact,
                  ),
                ],
              ),
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
    final categoryIconWidget = const {'home', 'about'}.contains(id)
        ? Icon(icon, size: 22)
        : SettingsCategoryIcon(category: widget.catalog.category(id), size: 34);
    return Padding(
      padding: const .symmetric(vertical: 2),
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
              icon: categoryIconWidget,
            )
          : ListTile(
              key: ValueKey('nav-$id'),
              selected: selected && _query.isEmpty,
              selectedTileColor: colors.secondaryContainer,
              selectedColor: colors.onSecondaryContainer,
              shape: RoundedRectangleBorder(borderRadius: .circular(18)),
              leading: categoryIconWidget,
              title: Text(title, style: const TextStyle(fontSize: 14)),
              contentPadding: const .symmetric(horizontal: 12),
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
          if (_page != null &&
              _query.isEmpty &&
              widget.catalog.inCategory(_category).length > 1) ...[
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
                          '${widget.catalog.category(page.category).title}\n${page.description}',
                      onTap: () => _openPage(page),
                    ),
                ],
              ),
            ),
        ],
      );
    } else if (const {
          'sound-volume',
          'volume-mixer',
          'sound-devices',
        }.contains(_page?.id) &&
        widget.sound != null) {
      content = SoundPage(controller: widget.sound!, page: _page!);
    } else if (NotificationsPage.pageIds.contains(_page?.id) &&
        widget.client != null) {
      content = NotificationsPage(
        key: ValueKey(_page!.id),
        client: widget.client!,
        catalog: widget.catalog,
        page: _page!,
        onPage: _openPage,
      );
    } else if (_inputPage(_page) case final page?) {
      content = page;
    } else if (_page?.id == 'remya-bar' && widget.client != null) {
      content = BarAppearancePage(client: widget.client!, page: _page!);
    } else if (_page?.id == 'battery-usage' && widget.client != null) {
      content = BatteryUsagePage(client: widget.client!, page: _page!);
    } else if ((_page?.id == 'power' || _page?.id == 'battery-saver') &&
        widget.client != null) {
      content = PowerPage(
        key: ValueKey(_page!.id),
        catalog: widget.catalog,
        page: _page!,
        client: widget.client!,
        onPage: (id) => _openPage(widget.catalog.page(id)),
      );
    } else if (_page?.id == 'cameras' && widget.cameras != null) {
      content = CameraPage(controller: widget.cameras!);
    } else if (_page?.id == 'updates' && widget.updates != null) {
      content = UpdatesPage(controller: widget.updates!);
    } else if (_page?.id == 'active-hours' && widget.updates != null) {
      content = ActiveHoursPage(controller: widget.updates!);
    } else if (_page?.id == 'storage' &&
        StorageScope.maybeOf(context) != null) {
      content = StoragePage(
        controller: StorageScope.maybeOf(context)!,
        onPage: (id) => _openPage(widget.catalog.page(id)),
      );
    } else if (_page?.id == 'cleanup' &&
        StorageScope.maybeOf(context) != null) {
      content = CleanupPage(controller: StorageScope.maybeOf(context)!);
    } else if (_page?.id == 'installed' &&
        ApplicationsScope.maybeOf(context) != null) {
      final controller = ApplicationsScope.maybeOf(context)!;
      content = InstalledAppsPage(
        controller: controller,
        formatDate: controller.formatDate,
      );
    } else if (_page?.id == 'fonts' && FontsScope.maybeOf(context) != null) {
      content = FontsPage(
        page: _page!,
        controller: FontsScope.maybeOf(context)!,
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
    } else if (_page?.id == 'airplane' && widget.client != null) {
      content = AirplanePage(client: widget.client!);
    } else if (_page?.id == 'proxy' && widget.client != null) {
      content = ProxyPage(client: widget.client!);
    } else if (_page?.id == 'bluetooth' &&
        BluetoothScope.maybeOf(context) != null) {
      content = BluetoothPage(controller: BluetoothScope.maybeOf(context)!);
    } else if (_networkPage(_page) case final page?) {
      content = page;
    } else if (_page?.id == 'your-info' && widget.account != null) {
      content = AccountInformationPage(
        page: _page!,
        controller: widget.account!,
      );
    } else if (_page?.id == 'startup' &&
        StartupScope.maybeOf(context) != null) {
      content = StartupPage(
        key: const ValueKey('startup-page'),
        controller: StartupScope.maybeOf(context)!,
      );
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
        client: widget.client,
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
                40,
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

  Widget? _inputPage(SettingsPageSpec? page) {
    final client = widget.client;
    if (page == null || client == null) return null;
    final key = ValueKey('input-${page.id}');
    final catalog = widget.catalog;
    return switch (page.id) {
      'mouse' => MousePage(
        key: key,
        catalog: catalog,
        page: page,
        client: client,
      ),
      'touchpad' => TouchpadPage(
        key: key,
        catalog: catalog,
        page: page,
        client: client,
      ),
      'keyboard-shortcuts' => KeyboardShortcutsPage(
        key: key,
        catalog: catalog,
        page: page,
        client: client,
      ),
      'multitasking' => MultitaskingPage(
        key: key,
        catalog: catalog,
        page: page,
        client: client,
      ),
      'language' => LanguagePage(
        key: key,
        catalog: catalog,
        page: page,
        client: client,
      ),
      'workspaces' => WorkspacesPage(
        key: key,
        catalog: catalog,
        page: page,
        client: client,
      ),
      'window-appearance' => WindowAppearancePage(
        key: key,
        catalog: catalog,
        page: page,
        client: client,
      ),
      'animations' => AnimationsPage(
        key: key,
        catalog: catalog,
        page: page,
        client: client,
      ),
      'cursor' => CursorPage(
        key: key,
        catalog: catalog,
        page: page,
        client: client,
        onPage: _openPage,
      ),
      'themes' => ThemesPage(
        key: key,
        catalog: catalog,
        page: page,
        client: client,
        onPage: _openPage,
      ),
      'text-size' => TextSizePage(
        key: key,
        catalog: catalog,
        page: page,
        client: client,
        onPage: _openPage,
      ),
      _ => null,
    };
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
      'ethernet' => EthernetPage(controller: controller),
      'vpn' => VpnPage(controller: controller),
      'hotspot' => HotspotPage(controller: controller),
      _ => null,
    };
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
