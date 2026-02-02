import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhatsApp Status Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF25D366), // WhatsApp green
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF25D366),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      home: const StatusDownloaderScreen(),
    );
  }
}

class StatusDownloaderScreen extends StatefulWidget {
  const StatusDownloaderScreen({super.key});

  @override
  State<StatusDownloaderScreen> createState() => _StatusDownloaderScreenState();
}

class _StatusDownloaderScreenState extends State<StatusDownloaderScreen> {
  static const platform = MethodChannel('com.whatsappstatus.downloader/channel');
  List<StatusItem> statusItems = [];
  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStatusItems();
  }

  Future<void> _loadStatusItems() async {
    if (!Platform.isAndroid) {
      setState(() {
        errorMessage = 'This app is only available for Android';
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final List<dynamic> result = await platform.invokeMethod('getStatusItems');
      setState(() {
        statusItems = result.map((item) => StatusItem.fromMap(item)).toList();
        isLoading = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        errorMessage = e.message ?? 'Failed to load status items';
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _downloadStatus(StatusItem item) async {
    try {
      final String result = await platform.invokeMethod(
        'downloadStatus',
        {
          'path': item.path,
          'name': item.name,
          'type': item.type,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Download failed'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp Status Downloader'),
        centerTitle: true,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadStatusItems,
        child: _buildBody(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadStatusItems,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadStatusItems,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (statusItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'No status items found',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Make sure you have WhatsApp status items available',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: statusItems.length,
      itemBuilder: (context, index) {
        return StatusItemCard(
          item: statusItems[index],
          onDownload: () => _downloadStatus(statusItems[index]),
        );
      },
    );
  }
}

class StatusItem {
  final String path;
  final String name;
  final String type; // 'image' or 'video'
  final int size;
  final int lastModified;

  StatusItem({
    required this.path,
    required this.name,
    required this.type,
    required this.size,
    required this.lastModified,
  });

  factory StatusItem.fromMap(Map<dynamic, dynamic> map) {
    return StatusItem(
      path: map['path'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      size: map['size'] as int? ?? 0,
      lastModified: map['lastModified'] as int? ?? 0,
    );
  }
}

class StatusItemCard extends StatelessWidget {
  final StatusItem item;
  final VoidCallback onDownload;

  const StatusItemCard({
    super.key,
    required this.item,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = item.type == 'video';
    final sizeInMB = (item.size / (1024 * 1024)).toStringAsFixed(2);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  child: isVideo
                      ? const Icon(
                          Icons.videocam,
                          size: 48,
                        )
                      : const Icon(
                          Icons.image,
                          size: 48,
                        ),
                ),
                if (isVideo)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.play_circle_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '$sizeInMB MB',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Download'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


