import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../models/plugin.dart';
import '../services/plugin_runtime.dart';
import '../services/plugin_service.dart';
import 'plugin_details_screen.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with SingleTickerProviderStateMixin {
  List<Plugin> _plugins = [];
  Set<String> _installedIds = {};
  bool _loading = true;
  String _query = '';
  String? _selectedTag;
  String _sortBy = 'popular'; // popular | rating | recent | name
  final _searchCtrl = TextEditingController();
  late final AnimationController _fadeCtrl;

  static const _sortOptions = [
    ('popular', 'Most popular'),
    ('rating', 'Top rated'),
    ('recent', 'Recently updated'),
    ('name', 'Name (A–Z)'),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() => _loading = true);
    final results = await Future.wait([
      PluginService.fetchMarketplace(query: _query, forceRefresh: forceRefresh),
      PluginService.listInstalled(),
    ]);
    if (!mounted) return;
    setState(() {
      _plugins = results[0] as List<Plugin>;
      _installedIds =
          (results[1] as List<InstalledPlugin>).map((p) => p.id).toSet();
      _loading = false;
    });
    _fadeCtrl.forward(from: 0);
  }

  Future<void> _install(Plugin plugin) async {
    setState(() => _installedIds = {..._installedIds, plugin.id});
    try {
      final installed = await PluginService.installFromGithub(plugin.githubUrl);
      await PluginRuntime.instance.activate(installed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text('${plugin.name} installed')),
        ]),
        backgroundColor: VscodeTheme.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ));
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _installedIds = _installedIds.where((id) => id != plugin.id).toSet());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text('Install failed: $e')),
        ]),
        backgroundColor: VscodeTheme.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ));
    }
  }

  Future<void> _uninstall(Plugin plugin) async {
    await PluginRuntime.instance.deactivate(plugin.id);
    await PluginService.uninstall(plugin.id);
    if (!mounted) return;
    setState(() =>
        _installedIds = _installedIds.where((id) => id != plugin.id).toSet());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${plugin.name} removed'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ));
  }

  void _openDetails(Plugin plugin) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PluginDetailsScreen(plugin: plugin)),
    ).then((_) => _load());
  }

  List<Plugin> get _allTags => _plugins;

  List<String> get _availableTags {
    final set = <String>{};
    for (final p in _plugins) {
      set.addAll(p.tags);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<Plugin> get _filtered {
    var list = _plugins.where((p) {
      if (_selectedTag != null && !p.tags.contains(_selectedTag)) return false;
      return true;
    }).toList();
    switch (_sortBy) {
      case 'rating':
        list.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case 'recent':
        list.sort((a, b) => b.version.compareTo(a.version));
        break;
      case 'name':
        list.sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'popular':
      default:
        list.sort((a, b) => b.downloads.compareTo(a.downloads));
    }
    return list;
  }

  List<Plugin> get _featured {
    final sorted = [..._plugins]
      ..sort((a, b) => (b.rating * 100 + b.downloads)
          .compareTo(a.rating * 100 + a.downloads));
    return sorted.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: VscodeTheme.bg,
      appBar: AppBar(
        title: const Text('Marketplace'),
        backgroundColor: VscodeTheme.bgSidebar,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: VscodeTheme.fgMuted),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildSearch(),
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: VscodeTheme.accent))
          : _plugins.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: VscodeTheme.accent,
                  onRefresh: () => _load(forceRefresh: true),
                  child: CustomScrollView(
                    slivers: [
                      if (_featured.isNotEmpty) _buildFeatured(_featured),
                      _buildFilters(),
                      _buildTagBar(),
                      _buildResultsHeader(filtered.length),
                      if (filtered.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _NoMatches(),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 320,
                              mainAxisExtent: 230,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => _PluginCard(
                                plugin: filtered[i],
                                installed:
                                    _installedIds.contains(filtered[i].id),
                                onTap: () => _openDetails(filtered[i]),
                                onInstall: () => _install(filtered[i]),
                                onUninstall: () => _uninstall(filtered[i]),
                              ),
                              childCount: filtered.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSearch() {
    return Container(
      decoration: BoxDecoration(
        color: VscodeTheme.bgInput,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: VscodeTheme.border),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          const Icon(Icons.search, size: 16, color: VscodeTheme.fgMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search extensions…',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
              onSubmitted: (v) {
                setState(() => _query = v);
                _load();
              },
            ),
          ),
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              color: VscodeTheme.fgMuted,
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _query = '');
                _load();
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildFeatured(List<Plugin> featured) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.star_rounded,
                  size: 16, color: VscodeTheme.yellow),
              const SizedBox(width: 6),
              Text('Featured',
                  style: TextStyle(
                      color: VscodeTheme.fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4)),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: featured.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _FeaturedCard(
                  plugin: featured[i],
                  installed: _installedIds.contains(featured[i].id),
                  onTap: () => _openDetails(featured[i]),
                  onInstall: () => _install(featured[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            const Icon(Icons.sort, size: 14, color: VscodeTheme.fgMuted),
            const SizedBox(width: 6),
            Text('Sort:',
                style: TextStyle(
                    color: VscodeTheme.fgMuted, fontSize: 11)),
            const SizedBox(width: 6),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _sortOptions.map((opt) {
                    final active = _sortBy == opt.$1;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _Pill(
                        label: opt.$2,
                        active: active,
                        onTap: () => setState(() => _sortBy = opt.$1),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagBar() {
    final tags = _availableTags;
    if (tags.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tags.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              if (i == 0) {
                return _Pill(
                  label: 'All',
                  active: _selectedTag == null,
                  onTap: () => setState(() => _selectedTag = null),
                );
              }
              final t = tags[i - 1];
              return _Pill(
                label: t,
                active: _selectedTag == t,
                onTap: () => setState(() => _selectedTag = t),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildResultsHeader(int count) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Text('$count extension${count == 1 ? '' : 's'}',
                style: TextStyle(
                    color: VscodeTheme.fgMuted,
                    fontSize: 11,
                    letterSpacing: 0.5)),
            const Spacer(),
            if (_selectedTag != null)
              TextButton.icon(
                onPressed: () => setState(() => _selectedTag = null),
                icon: const Icon(Icons.clear, size: 12),
                label: Text('Clear filter',
                    style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: VscodeTheme.fgMuted,
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.extension_off_outlined,
              size: 64, color: VscodeTheme.fgMuted),
          const SizedBox(height: 16),
          const Text('No extensions found',
              style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('The marketplace is online — pull to refresh',
              style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
          const SizedBox(height: 8),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Pill(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? VscodeTheme.accent : VscodeTheme.bgInput,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? VscodeTheme.accent : VscodeTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : VscodeTheme.fgLabel,
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  final Plugin plugin;
  final bool installed;
  final VoidCallback onTap;
  final VoidCallback onInstall;
  const _FeaturedCard({
    required this.plugin,
    required this.installed,
    required this.onTap,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              VscodeTheme.accent.withOpacity(0.25),
              VscodeTheme.bgSidebar,
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: VscodeTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _PluginIcon(iconUrl: plugin.icon, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plugin.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: VscodeTheme.fg,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    Text('by ${plugin.author}',
                        style: const TextStyle(
                            color: VscodeTheme.fgMuted, fontSize: 11)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                plugin.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: VscodeTheme.fgLabel, fontSize: 12, height: 1.4),
              ),
            ),
            Row(children: [
              const Icon(Icons.star_rounded,
                  size: 12, color: VscodeTheme.yellow),
              const SizedBox(width: 3),
              Text(plugin.rating.toStringAsFixed(1),
                  style: const TextStyle(
                      color: VscodeTheme.fg, fontSize: 11)),
              const SizedBox(width: 8),
              const Icon(Icons.download_outlined,
                  size: 12, color: VscodeTheme.fgMuted),
              const SizedBox(width: 3),
              Text(_formatDownloads(plugin.downloads),
                  style: const TextStyle(
                      color: VscodeTheme.fgMuted, fontSize: 11)),
              const Spacer(),
              if (installed)
                const _InstalledBadge()
              else
                TextButton(
                  onPressed: onInstall,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: VscodeTheme.accent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text('Install',
                      style: TextStyle(fontSize: 11)),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  final Plugin plugin;
  final bool installed;
  final VoidCallback onTap;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;
  const _PluginCard({
    required this.plugin,
    required this.installed,
    required this.onTap,
    required this.onInstall,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: VscodeTheme.bgSidebar,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: installed ? VscodeTheme.green : VscodeTheme.border,
            width: installed ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _PluginIcon(iconUrl: plugin.icon, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plugin.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: VscodeTheme.fg,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    Text('v${plugin.version}',
                        style: const TextStyle(
                            color: VscodeTheme.fgMuted, fontSize: 11)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                plugin.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: VscodeTheme.fgLabel, fontSize: 12, height: 1.4),
              ),
            ),
            if (plugin.tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: plugin.tags
                    .take(3)
                    .map((t) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: VscodeTheme.bgInput,
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: VscodeTheme.border),
                          ),
                          child: Text(t,
                              style: const TextStyle(
                                  color: VscodeTheme.fgMuted, fontSize: 10)),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.star_rounded,
                  size: 12, color: VscodeTheme.yellow),
              const SizedBox(width: 3),
              Text(plugin.rating.toStringAsFixed(1),
                  style: const TextStyle(
                      color: VscodeTheme.fg, fontSize: 11)),
              const SizedBox(width: 4),
              Text('(${plugin.reviewsCount})',
                  style: const TextStyle(
                      color: VscodeTheme.fgMuted, fontSize: 10)),
              const SizedBox(width: 8),
              const Icon(Icons.download_outlined,
                  size: 12, color: VscodeTheme.fgMuted),
              const SizedBox(width: 3),
              Text(_formatDownloads(plugin.downloads),
                  style: const TextStyle(
                      color: VscodeTheme.fgMuted, fontSize: 11)),
              const Spacer(),
              if (installed)
                IconButton(
                  onPressed: onUninstall,
                  icon: const Icon(Icons.check_circle, size: 18),
                  color: VscodeTheme.green,
                  tooltip: 'Uninstall',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                )
              else
                IconButton(
                  onPressed: onInstall,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  color: VscodeTheme.accent,
                  tooltip: 'Install',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _PluginIcon extends StatelessWidget {
  final String? iconUrl;
  final double size;
  const _PluginIcon({required this.iconUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: VscodeTheme.bgInput,
        borderRadius: BorderRadius.circular(6),
      ),
      child: (iconUrl != null && iconUrl!.isNotEmpty)
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                iconUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(Icons.extension,
                    color: VscodeTheme.accent, size: size * 0.55),
              ),
            )
          : Icon(Icons.extension,
              color: VscodeTheme.accent, size: size * 0.55),
    );
  }
}

class _InstalledBadge extends StatelessWidget {
  const _InstalledBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: VscodeTheme.green.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VscodeTheme.green),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check, size: 10, color: VscodeTheme.green),
        const SizedBox(width: 4),
        Text('Installed',
            style: TextStyle(
                color: VscodeTheme.green,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.filter_alt_off_outlined,
              size: 48, color: VscodeTheme.fgMuted),
          const SizedBox(height: 12),
          const Text('No matches for the current filter',
              style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

String _formatDownloads(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toString();
}
