class Plugin {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String githubUrl;
  final double rating;
  final int reviewsCount;
  final int downloads;
  final String? icon;
  final List<String> tags;
  final List<String> platforms;

  const Plugin({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    required this.githubUrl,
    this.rating = 0.0,
    this.reviewsCount = 0,
    this.downloads = 0,
    this.icon,
    this.tags = const [],
    this.platforms = const ['android'],
  });

  factory Plugin.fromJson(Map<String, dynamic> j) => Plugin(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        version: (j['version'] ?? '1.0.0').toString(),
        author: (j['author'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        githubUrl: (j['githubUrl'] ?? '').toString(),
        rating: (j['rating'] is num) ? (j['rating'] as num).toDouble() : 0.0,
        reviewsCount: (j['reviewsCount'] is num) ? (j['reviewsCount'] as num).toInt() : 0,
        downloads: (j['downloads'] is num) ? (j['downloads'] as num).toInt() : 0,
        icon: j['icon']?.toString(),
        tags: (j['tags'] is List)
            ? (j['tags'] as List).map((e) => e.toString()).toList()
            : const [],
        platforms: (j['platforms'] is List)
            ? (j['platforms'] as List).map((e) => e.toString()).toList()
            : const ['android'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'author': author,
        'description': description,
        'githubUrl': githubUrl,
        'rating': rating,
        'reviewsCount': reviewsCount,
        'downloads': downloads,
        'icon': icon,
        'tags': tags,
        'platforms': platforms,
      };
}

class InstalledPlugin {
  final String id;
  final String version;
  final String localPath;
  final String githubUrl;
  final Map<String, dynamic> manifest;

  const InstalledPlugin({
    required this.id,
    required this.version,
    required this.localPath,
    required this.githubUrl,
    required this.manifest,
  });

  String get name => (manifest['name'] ?? id).toString();
  String get author => (manifest['author'] ?? '').toString();
  String get description => (manifest['description'] ?? '').toString();
  String get mainFile => (manifest['main'] ?? 'main.js').toString();
  List<String> get permissions =>
      (manifest['permissions'] is List)
          ? (manifest['permissions'] as List).map((e) => e.toString()).toList()
          : const [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'localPath': localPath,
        'githubUrl': githubUrl,
        'manifest': manifest,
      };

  factory InstalledPlugin.fromJson(Map<String, dynamic> j) => InstalledPlugin(
        id: (j['id'] ?? '').toString(),
        version: (j['version'] ?? '').toString(),
        localPath: (j['localPath'] ?? '').toString(),
        githubUrl: (j['githubUrl'] ?? '').toString(),
        manifest: (j['manifest'] is Map)
            ? Map<String, dynamic>.from(j['manifest'] as Map)
            : <String, dynamic>{},
      );
}

class Review {
  final String id;
  final String author;
  final int rating;
  final String text;
  final String date;

  const Review({
    required this.id,
    required this.author,
    required this.rating,
    required this.text,
    required this.date,
  });

  factory Review.fromJson(Map<String, dynamic> j) => Review(
        id: (j['id'] ?? '').toString(),
        author: (j['author'] ?? 'Anonymous').toString(),
        rating: (j['rating'] is num) ? (j['rating'] as num).toInt() : 0,
        text: (j['text'] ?? j['review'] ?? '').toString(),
        date: (j['date'] ?? j['createdAt'] ?? '').toString(),
      );
}
