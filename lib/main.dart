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
        cardTheme: CardThemeData(
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
        cardTheme: CardThemeData(
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
  bool hasPermission = false;
  bool isCheckingPermission = true;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
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
      final bool permission =
          await platform.invokeMethod<bool>('hasPersistedPermission') ?? false;
      setState(() {
        hasPermission = permission;
        isCheckingPermission = false;
      });

      if (permission) {
        await _loadStatusItems();
      }
    } on PlatformException catch (e) {
      setState(() {
        errorMessage = e.message ?? 'Failed to check permission';
        isCheckingPermission = false;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
        isCheckingPermission = false;
        isLoading = false;
      });
    }
  }

  Future<void> _requestFolderAccess() async {
    try {
      final bool granted = await platform
              .invokeMethod<bool>('requestStatusFolderAccess') ??
          false;
      if (!granted) {
        return;
      }

      setState(() {
        hasPermission = true;
      });

      await _loadStatusItems();
    } on PlatformException catch (e) {
      setState(() {
        errorMessage = e.message ?? 'Failed to request folder access';
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
      });
    }
  }

  Future<void> _loadStatusItems() async {
    if (!Platform.isAndroid) {
      setState(() {
        errorMessage = 'This app is only available for Android';
      });
      return;
    }

    if (!hasPermission) {
      // Permission flow UI will be shown in _buildBody.
      setState(() {
        isLoading = false;
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final List<dynamic> result =
          await platform.invokeMethod('getStatusFiles');
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
        <String, dynamic>{
          'uri': item.uri,
          'name': item.name,
          'mimeType': item.mimeType,
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
    if (isCheckingPermission) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (!hasPermission) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.folder_open,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Grant WhatsApp Status Access',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Select the WhatsApp .Statuses folder to view and download statuses',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _requestFolderAccess,
                child: const Text('Select Folder'),
              ),
            ],
          ),
        ),
      );
    }

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
      // Permission granted but no files found.
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
                'Open WhatsApp status, then tap Refresh',
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
  final String name;
  final String mimeType;
  final String uri;
  final int size;
  final int lastModified;

  StatusItem({
    required this.name,
    required this.mimeType,
    required this.uri,
    required this.size,
    required this.lastModified,
  });

  factory StatusItem.fromMap(Map<dynamic, dynamic> map) {
    return StatusItem(
      name: map['name'] as String,
      mimeType: map['mimeType'] as String,
      uri: map['uri'] as String,
      size: map['size'] as int? ?? 0,
      lastModified: map['lastModified'] as int? ?? 0,
    );
  }

  bool get isVideo => mimeType.startsWith('video/');
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
    final isVideo = item.isVideo;
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


