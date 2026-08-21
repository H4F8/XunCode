import 'dart:convert';

/// Один язык программирования, который XunCode умеет ставить локально.
/// `builtin: true` означает, что описание зашито в код (см. [builtinLanguages]).
/// `builtin: false` — язык, добавленный пользователем через UI «Свои языки».
class Language {
  /// Уникальный ID, используется как имя папки и ключ в SharedPreferences.
  /// Должен быть [a-zA-Z0-9_-].
  final String id;
  final String name;
  final String version;

  /// Прямая ссылка на архив (`.tar.gz`, `.tar.xz` или `.zip`), который
  /// будет скачан и распакован в `<privateRoot>/languages/<id>/`.
  final String url;

  /// Имя пакетного менеджера: `pip`, `npm`, `cargo`, `gem`, `go`, … или null.
  final String? libManager;

  /// Базовый URL реестра. Для PyPI: `https://pypi.org/pypi/`,
  /// для npm: `https://registry.npmjs.org/`. Можно переопределить пользователем.
  final String? registry;

  /// Команда, через которую запускается код. Поддерживается плейсхолдер
  /// `%file%`. Путь относительный к корню распакованного языка
  /// (`<privateRoot>/languages/<id>/`).
  final String launchCommand;

  /// Иконка для UI. Material Icons codepoint в hex или null. Опционально.
  final String? icon;

  /// `false` — пользовательский, хранится в SharedPreferences.
  final bool builtin;

  const Language({
    required this.id,
    required this.name,
    required this.version,
    required this.url,
    this.libManager,
    this.registry,
    required this.launchCommand,
    this.icon,
    this.builtin = false,
  });

  Language copyWith({
    String? version,
    String? url,
    String? libManager,
    String? registry,
    String? launchCommand,
    bool? builtin,
  }) =>
      Language(
        id: id,
        name: name,
        version: version ?? this.version,
        url: url ?? this.url,
        libManager: libManager ?? this.libManager,
        registry: registry ?? this.registry,
        launchCommand: launchCommand ?? this.launchCommand,
        icon: icon,
        builtin: builtin ?? this.builtin,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'url': url,
        'libManager': libManager,
        'registry': registry,
        'launchCommand': launchCommand,
        'icon': icon,
        'builtin': builtin,
      };

  factory Language.fromJson(Map<String, Object?> j) => Language(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        version: j['version']?.toString() ?? '',
        url: j['url']?.toString() ?? '',
        libManager: j['libManager']?.toString(),
        registry: j['registry']?.toString(),
        launchCommand: j['launchCommand']?.toString() ?? '',
        icon: j['icon']?.toString(),
        builtin: j['builtin'] == true,
      );

  static String encodeList(List<Language> list) =>
      jsonEncode(list.map((l) => l.toJson()).toList());

  static List<Language> decodeList(String raw) {
    if (raw.isEmpty) return const [];
    final data = jsonDecode(raw);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((m) => Language.fromJson(Map<String, Object?>.from(m)))
        .toList();
  }
}

/// Дефолтный набор языков — официальные релизы, ARM64. Если пользователь
/// сидит на armv7 или x86_64, он сможет переопределить URL руками через
/// «Custom languages», но базовый набор оптимизирован под самый
/// распространённый Android-чипсет.
const List<Language> builtinLanguages = [
  Language(
    id: 'python',
    name: 'Python',
    version: '3.12.3',
    url: 'https://github.com/indygreg/python-build-standalone/releases/download/20240415/cpython-3.12.3+20240415-aarch64-unknown-linux-gnu-install_only.tar.gz',
    libManager: 'pip',
    registry: 'https://pypi.org/pypi/',
    launchCommand: './bin/python3 %file%',
    builtin: true,
  ),
  Language(
    id: 'nodejs',
    name: 'Node.js',
    version: '20.18.0',
    url: 'https://nodejs.org/dist/v20.18.0/node-v20.18.0-linux-arm64.tar.gz',
    libManager: 'npm',
    registry: 'https://registry.npmjs.org/',
    launchCommand: './bin/node %file%',
    builtin: true,
  ),
  Language(
    id: 'go',
    name: 'Go',
    version: '1.22.3',
    url: 'https://go.dev/dl/go1.22.3.linux-arm64.tar.gz',
    libManager: 'go',
    registry: 'https://proxy.golang.org/',
    launchCommand: './bin/go run %file%',
    builtin: true,
  ),
  Language(
    id: 'rust',
    name: 'Rust',
    version: '1.78.0',
    url: 'https://static.rust-lang.org/dist/rust-1.78.0-aarch64-unknown-linux-gnu.tar.gz',
    libManager: 'cargo',
    registry: 'https://crates.io/api/v1/',
    launchCommand: './rustc/bin/rustc %file% && ./%file%.out',
    builtin: true,
  ),
  Language(
    id: 'ruby',
    name: 'Ruby',
    version: '3.3.1',
    url: 'https://github.com/ruby/ruby-builder/releases/download/toolcache/ruby-3.3.1-ubuntu-22.04.tar.gz',
    libManager: 'gem',
    registry: 'https://rubygems.org/api/v1/',
    launchCommand: './bin/ruby %file%',
    builtin: true,
  ),
  Language(
    id: 'lua',
    name: 'Lua',
    version: '5.4.6',
    url: 'https://www.lua.org/ftp/lua-5.4.6.tar.gz',
    libManager: 'luarocks',
    registry: 'https://luarocks.org/',
    launchCommand: './lua %file%',
    builtin: true,
  ),
  Language(
    id: 'php',
    name: 'PHP',
    version: '8.3.6',
    url: 'https://www.php.net/distributions/php-8.3.6.tar.gz',
    libManager: 'composer',
    registry: 'https://packagist.org/',
    launchCommand: './bin/php %file%',
    builtin: true,
  ),
  Language(
    id: 'java',
    name: 'Java (OpenJDK)',
    version: '21.0.3',
    url: 'https://download.java.net/java/GA/jdk21.0.3/fa2202b3a4244742b1d7da8f15e7d1da/9/GPL/openjdk-21.0.3_linux-aarch64_bin.tar.gz',
    libManager: 'maven',
    registry: 'https://search.maven.org/solrsearch/select?q=',
    launchCommand: './bin/java %file%',
    builtin: true,
  ),
];
