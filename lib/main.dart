import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
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
  int _selectedTabIndex = 0; // 0 = Images, 1 = Videos

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

  void _openPreview(StatusItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatusPreviewPage(item: item),
      ),
    );
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

    final imageItems = statusItems.where((item) => !item.isVideo).toList();
    final videoItems = statusItems.where((item) => item.isVideo).toList();
    final bool isImagesTab = _selectedTabIndex == 0;
    final List<StatusItem> visibleItems =
        isImagesTab ? imageItems : videoItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _StatusTabs(
            selectedIndex: _selectedTabIndex,
            onChanged: (index) {
              setState(() {
                _selectedTabIndex = index;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Only viewed statuses appear here',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: isLoading
              ? const _ShimmerStatusGrid()
              : visibleItems.isEmpty
                  ? _EmptyTabState(
                      isImagesTab: isImagesTab,
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: visibleItems.length,
                      itemBuilder: (context, index) {
                        final item = visibleItems[index];
                        return StatusItemCard(
                          item: item,
                          onDownload: () => _downloadStatus(item),
                          onTap: () => _openPreview(item),
                        );
                      },
                    ),
        ),
      ],
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
  final VoidCallback? onTap;

  const StatusItemCard({
    super.key,
    required this.item,
    required this.onDownload,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = item.isVideo;
    final sizeInMB = (item.size / (1024 * 1024)).toStringAsFixed(2);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!isVideo)
                    Image.file(
                      File(item.uri),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color:
                              Theme.of(context).colorScheme.surfaceVariant,
                          child: const Icon(
                            Icons.image,
                            size: 48,
                          ),
                        );
                      },
                    )
                  else
                    Container(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: const Icon(
                        Icons.videocam,
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
                    '$sizeInMB MB · ${isVideo ? 'Video' : 'Image'}',
                    style:
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download'),
                    style: FilledButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _StatusTabs({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    Widget buildTab(String label, int index) {
      final bool isSelected = selectedIndex == index;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (!isSelected) {
              onChanged(index);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: isSelected
                  ? colorScheme.primary.withOpacity(0.12)
                  : Colors.transparent,
            ),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          buildTab('Images', 0),
          buildTab('Videos', 1),
        ],
      ),
    );
  }
}

class _EmptyTabState extends StatelessWidget {
  final bool isImagesTab;

  const _EmptyTabState({required this.isImagesTab});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isImagesTab
                  ? Icons.photo_library_outlined
                  : Icons.video_library_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              isImagesTab
                  ? 'No image statuses found'
                  : 'No video statuses found',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Open the ${isImagesTab ? 'image' : 'video'} statuses in WhatsApp, then tap Refresh.\nOnly viewed statuses appear here.',
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
}

class _ShimmerStatusGrid extends StatelessWidget {
  const _ShimmerStatusGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: 6,
      itemBuilder: (context, index) {
        return const _ShimmerStatusCard();
      },
    );
  }
}

class _ShimmerStatusCard extends StatelessWidget {
  const _ShimmerStatusCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Expanded(
            child: _ShimmerBox(),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ShimmerLine(widthFactor: 0.8),
                SizedBox(height: 6),
                _ShimmerLine(widthFactor: 0.4),
                SizedBox(height: 12),
                _ShimmerLine(widthFactor: 0.6, height: 36),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox();

  @override
  Widget build(BuildContext context) {
    return const _ShimmerBase();
  }
}

class _ShimmerLine extends StatelessWidget {
  final double widthFactor;
  final double height;

  const _ShimmerLine({
    required this.widthFactor,
    this.height = 12,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: SizedBox(
        height: height,
        child: const _ShimmerBase(),
      ),
    );
  }
}

class _ShimmerBase extends StatefulWidget {
  const _ShimmerBase();

  @override
  State<_ShimmerBase> createState() => _ShimmerBaseState();
}

class _ShimmerBaseState extends State<_ShimmerBase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor =
        Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6);
    final highlightColor =
        Theme.of(context).colorScheme.surface.withOpacity(0.9);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (Rect bounds) {
            final double shimmerPosition = _controller.value * 2 - 1;
            return LinearGradient(
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [0.1, 0.5, 0.9],
              begin: Alignment(-1 - shimmerPosition, 0),
              end: Alignment(1 + shimmerPosition, 0),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: Container(
            color: baseColor,
          ),
        );
      },
    );
  }
}

class StatusPreviewPage extends StatefulWidget {
  final StatusItem item;

  const StatusPreviewPage({super.key, required this.item});

  @override
  State<StatusPreviewPage> createState() => _StatusPreviewPageState();
}

class _StatusPreviewPageState extends State<StatusPreviewPage> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.item.isVideo) {
      _videoController = VideoPlayerController.file(
        File(widget.item.uri),
      )
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isVideoInitialized = true;
            });
            _videoController?.play();
          }
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.item.isVideo;

    return Scaffold(
      appBar: AppBar(
        title: Text(isVideo ? 'Video preview' : 'Image preview'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: isVideo
              ? _buildVideoPreview()
              : _buildImagePreview(),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return InteractiveViewer(
      child: Image.file(
        File(widget.item.uri),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.broken_image, size: 72),
              SizedBox(height: 12),
              Text('Unable to load image'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVideoPreview() {
    if (!_isVideoInitialized || _videoController == null) {
      return const CircularProgressIndicator();
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
        const SizedBox(height: 16),
        IconButton.filled(
          iconSize: 40,
          onPressed: () {
            if (_videoController!.value.isPlaying) {
              _videoController!.pause();
            } else {
              _videoController!.play();
            }
            setState(() {});
          },
          icon: Icon(
            _videoController!.value.isPlaying
                ? Icons.pause
                : Icons.play_arrow,
          ),
        ),
      ],
    );
  }
}


