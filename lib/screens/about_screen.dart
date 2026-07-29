import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app/theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _appVersion = '1.0.0';
  static const _appBuild = '1';

  static const _donationUrl = 'https://www.donationalerts.com/r/wenerking';

  static const _links = [
    _LinkRef(
      icon: Icons.code,
      label: 'GitHub',
      handle: '@H4F8',
      url: 'https://github.com/H4F8',
    ),
    _LinkRef(
      icon: Icons.developer_mode,
      label: 'Dev channel',
      handle: 't.me/XunKal1Dev',
      url: 'https://t.me/XunKal1Dev',
    ),
    _LinkRef(
      icon: Icons.campaign_outlined,
      label: 'Community',
      handle: 't.me/GodPassTGK',
      url: 'https://t.me/GodPassTGK',
    ),
  ];

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VscodeTheme.bg,
      appBar: AppBar(
        title: const Text('About'),
        backgroundColor: VscodeTheme.bgSidebar,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: VscodeTheme.fgMuted),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _section('AUTHOR & COMMUNITY'),
          ..._links.map(_buildLinkTile),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.favorite, color: Colors.redAccent, size: 18),
            title: const Text('Support author',
                style: TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            subtitle: const Text('Buy the developer a coffee',
                style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
            trailing: const Icon(Icons.open_in_new, size: 14, color: Colors.redAccent),
            onTap: () => _open(_donationUrl),
          ),
          const SizedBox(height: 16),
          _section('VERSION'),
          _infoTile('Version', _appVersion),
          _infoTile('Build', _appBuild),
          _infoTile('Platform', 'Flutter · Android'),
          const SizedBox(height: 16),
          _section('CREDITS'),
          _infoTile('Editor', 'Monaco Editor'),
          _infoTile('Framework', 'Flutter'),
          const SizedBox(height: 16),
          _section('LICENSE'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'Licensed under the Apache License, Version 2.0. You may use, '
              'modify, and distribute this software under the terms of the '
              'Apache-2.0 license. See LICENSE in the repository root for the '
              'full text. © 2026 XunKal1 (H4F8).',
              style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: VscodeTheme.bgInput,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.code, size: 32, color: VscodeTheme.accent),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('XunCode',
                  style: TextStyle(color: VscodeTheme.fg, fontSize: 18, fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text('Mobile code editor for Android',
                  style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(title,
      style: const TextStyle(fontSize: 11, color: VscodeTheme.fgLabel,
        letterSpacing: 1, fontWeight: FontWeight.w600)),
  );

  Widget _infoTile(String label, String value) => ListTile(
    tileColor: VscodeTheme.bgSidebar,
    dense: true,
    title: Text(label, style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
    trailing: Text(value, style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)),
  );

  Widget _buildLinkTile(_LinkRef link) => ListTile(
    tileColor: VscodeTheme.bgSidebar,
    dense: true,
    leading: Icon(link.icon, color: VscodeTheme.accent, size: 18),
    title: Text(link.label, style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
    subtitle: Text(link.handle,
      style: const TextStyle(color: VscodeTheme.accent, fontSize: 12)),
    trailing: const Icon(Icons.open_in_new, size: 14, color: VscodeTheme.fgMuted),
    onTap: () => _open(link.url),
  );
}

class _LinkRef {
  final IconData icon;
  final String label;
  final String handle;
  final String url;
  const _LinkRef({
    required this.icon,
    required this.label,
    required this.handle,
    required this.url,
  });
}
