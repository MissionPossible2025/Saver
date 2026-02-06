import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Status Saver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF25D366), // WhatsApp green
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
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
        scaffoldBackgroundColor: Colors.black,
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

  bool _isLoadingAfterPermission = false;

  Future<void> _openFolderInstructions() async {
    // Show a dedicated instruction screen first.
    // The system folder picker should open ONLY after user taps "Continue".
    final bool? shouldContinue = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const FolderInstructionScreen(),
      ),
    );

    if (shouldContinue == true && mounted) {
      await _requestFolderAccess();
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

      // Update permission state immediately (lightweight)
      // Do NOT load files yet - wait for app to fully resume
      setState(() {
        hasPermission = true;
        isCheckingPermission = false;
        isLoading = false; // Don't show loading yet
      });

      // Wait for next frame to ensure Activity is fully resumed
      // Minimal delay to prevent crashes while keeping app responsive
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Small delay to ensure Activity lifecycle is fully resumed
        // Reduced to 150ms - enough to prevent crashes, fast enough for good UX
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted && !_isLoadingAfterPermission) {
            _isLoadingAfterPermission = true;
            // Load items asynchronously without blocking
            _loadStatusItems().then((_) {
              _isLoadingAfterPermission = false;
            }).catchError((e) {
              _isLoadingAfterPermission = false;
              if (mounted) {
                setState(() {
                  errorMessage = 'Error loading statuses: $e';
                });
              }
            });
          }
        });
      });
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.message ?? 'Failed to request folder access';
          isCheckingPermission = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'Error: $e';
          isCheckingPermission = false;
        });
      }
    }
  }

  Future<void> _loadStatusItems() async {
    if (!Platform.isAndroid) {
      if (mounted) {
        setState(() {
          errorMessage = 'This app is only available for Android';
        });
      }
      return;
    }

    if (!hasPermission) {
      // Permission flow UI will be shown in _buildBody.
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
      return;
    }

    // Ensure we're mounted before updating state
    if (!mounted) return;

    // Update UI to show loading state immediately (responsive)
    if (mounted) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    // No delay here - platform channel is already async and non-blocking
    // File scanning happens on Android side, not blocking main thread

    try {
      // Perform file scanning asynchronously (platform channel is already async)
      // The actual file scanning happens on Android side, not blocking main thread
      final List<dynamic> result = await platform.invokeMethod('getStatusFiles');
      
      // Check mounted again after async operation
      if (!mounted) return;
      
      // Parse results in isolate to avoid blocking main thread during parsing
      // This is done in background isolate, not blocking UI
      final List<StatusItem> parsedItems = await compute(_parseStatusItems, result);
      
      if (!mounted) return;
      
      // Update state with results immediately (show placeholders)
      if (mounted) {
        setState(() {
          statusItems = parsedItems;
          isLoading = false;
        });

        // Inform Android that a refresh occurred so it can defer new thumbnail jobs by 300ms.
        // This uses Handler(Looper.getMainLooper()).postDelayed(...) on the native side.
        platform.invokeMethod('notifyRefresh').catchError((_) {});
      }
    } on PlatformException catch (e) {
      final msg = e.message ?? 'Failed to load status items';

      // Special handling for wrong-folder selection coming from Android
      if (msg.contains('SELECT_WHATSAPP_STATUSES_FOLDER:')) {
        if (!mounted) return;

        final String? action = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Text('Choose WhatsApp statuses folder'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop('close'),
                  ),
                ],
              ),
              content: const Text(
                'The folder you selected cannot show WhatsApp viewed statuses.\n\n'
                'Please navigate to:\n'
                'Android → media → com.whatsapp → WhatsApp → Media → .Statuses\n\n'
                'Do not create a new folder, and ignore any “Can’t use this folder” message on intermediate folders. '
                'Keep going until you reach the .Statuses folder, then tap “Use this folder”.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop('retry'),
                  child: const Text('Retry'),
                ),
              ],
            );
          },
        );

        if (!mounted) return;

        // Reset state
        setState(() {
          hasPermission = false;
          isLoading = false;
          errorMessage = null;
          statusItems = [];
        });

        // If user tapped Retry, open the instruction screen again so they can reselect.
        if (action == 'retry') {
          await _openFolderInstructions();
        }
        return;
      }

      if (mounted) {
        setState(() {
          errorMessage = msg;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'Error: $e';
          isLoading = false;
        });
      }
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Status Saver'),
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
      return Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!hasPermission) {
      return Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
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
                onPressed: _openFolderInstructions,
                child: const Text('Select Folder'),
              ),
              ],
            ),
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
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
        ),
      );
    }

    final imageItems = statusItems.where((item) => !item.isVideo).toList();
    final videoItems = statusItems.where((item) => item.isVideo).toList();
    final bool isImagesTab = _selectedTabIndex == 0;
    final List<StatusItem> visibleItems =
        isImagesTab ? imageItems : videoItems;

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
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
                      // Increase cacheExtent to keep more items alive for smooth scrolling
                      // This works with AutomaticKeepAliveClientMixin to persist loaded thumbnails
                      cacheExtent: 1000, // Cache 1000px worth of items (more for better UX)
                      itemBuilder: (context, index) {
                        final item = visibleItems[index];
                        // Use stable key based on URI + lastModified to prevent widget recreation
                        // This ensures widgets persist across tab switches and refreshes
                        return _LazyStatusItemCard(
                          key: ValueKey('${isImagesTab ? 'img' : 'vid'}_${item.uri}_${item.lastModified}'),
                          item: item,
                          onDownload: () => _downloadStatus(item),
                          onTap: () => _openPreview(item),
                        );
                      },
                    ),
        ),
      ],
      ),
    );
  }
}

class FolderInstructionScreen extends StatelessWidget {
  const FolderInstructionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Status Folder'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This is required only once',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'We need folder access to show your viewed status photos and videos so you can preview and save them.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: mutedColor,
                    ),
              ),
              const SizedBox(height: 18),
              _StepRow(
                step: '1',
                text:
                    'In the next screen, navigate to the WhatsApp statuses folder.',
              ),
              const SizedBox(height: 10),
              _StepRow(
                step: '2',
                text: 'Tap “Use this folder”.',
              ),
              const SizedBox(height: 10),
              _StepRow(
                step: '3',
                text: 'Tap “Allow”.',
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Folder path to select',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Android → media → com.whatsapp → WhatsApp → Media → .Statuses',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: mutedColor,
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Status Saver only reads photos and videos inside the WhatsApp .Statuses folder. '
                      'No other chats, media or WhatsApp data are accessed or modified.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Privacy note',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'If you see a system message like “Can’t use this folder” or a suggestion to “Create new folder”, '
                'ignore it and keep going deeper until you reach the .Statuses folder. '
                'Creating a new folder will not show any statuses to download.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: mutedColor,
                      height: 1.35,
                    ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continue'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String step;
  final String text;

  const _StepRow({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            step,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
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

// Wrapper widget that handles visibility detection using viewport intersection
class _LazyStatusItemCard extends StatefulWidget {
  final StatusItem item;
  final VoidCallback onDownload;
  final VoidCallback? onTap;

  const _LazyStatusItemCard({
    super.key,
    required this.item,
    required this.onDownload,
    this.onTap,
  });

  @override
  State<_LazyStatusItemCard> createState() => _LazyStatusItemCardState();
}

class _LazyStatusItemCardState extends State<_LazyStatusItemCard> {
  final GlobalKey _key = GlobalKey();
  bool _isVisible = false;
  bool _hasCheckedInitialVisibility = false;

  @override
  void initState() {
    super.initState();
    // Check visibility after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkVisibility();
        _hasCheckedInitialVisibility = true;
      }
    });
  }

  void _checkVisibility() {
    if (!mounted) return;
    final RenderObject? renderObject = _key.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      final RenderBox box = renderObject;
      final position = box.localToGlobal(Offset.zero);
      final size = box.size;
      final screenHeight = MediaQuery.of(context).size.height;
      final screenWidth = MediaQuery.of(context).size.width;
      
      // Consider visible if within viewport + buffer for preloading
      // Buffer of 200px above and below viewport for smooth scrolling
      final buffer = 200.0;
      final isVisible = position.dy + size.height >= -buffer && 
                       position.dy <= screenHeight + buffer &&
                       position.dx + size.width >= -buffer &&
                       position.dx <= screenWidth + buffer;
      
      if (isVisible != _isVisible) {
        setState(() {
          _isVisible = isVisible;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use NotificationListener to detect scroll and update visibility
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification || 
            notification is ScrollEndNotification) {
          _checkVisibility();
        }
        return false;
      },
      child: StatusItemCard(
        key: _key,
        item: widget.item,
        onDownload: widget.onDownload,
        onTap: widget.onTap,
        isVisible: _isVisible,
      ),
    );
  }
}

class StatusItemCard extends StatefulWidget {
  final StatusItem item;
  final VoidCallback onDownload;
  final VoidCallback? onTap;
  final bool isVisible;

  const StatusItemCard({
    super.key,
    required this.item,
    required this.onDownload,
    this.onTap,
    this.isVisible = false,
  });

  @override
  State<StatusItemCard> createState() => _StatusItemCardState();
}

// Persistent cache for thumbnails - stores both image bytes and video thumbnail paths
// This cache persists across tab switches and scrolling
class _ThumbnailCacheSync {
  // Cache for video thumbnail file paths
  static final Map<String, String?> _videoCache = {};
  // Cache for image bytes (in-memory)
  static final Map<String, Uint8List?> _imageCache = {};
  
  static String? getVideoThumbnail(String uri, int lastModified) {
    final key = '$uri|$lastModified';
    return _videoCache[key];
  }
  
  static void setVideoThumbnail(String uri, int lastModified, String? path) {
    final key = '$uri|$lastModified';
    if (path != null) {
      _videoCache[key] = path;
    } else {
      _videoCache.remove(key);
    }
  }
  
  static Uint8List? getImageBytes(String uri, int lastModified) {
    final key = '$uri|$lastModified';
    return _imageCache[key];
  }
  
  static void setImageBytes(String uri, int lastModified, Uint8List? bytes) {
    final key = '$uri|$lastModified';
    if (bytes != null) {
      _imageCache[key] = bytes;
    } else {
      _imageCache.remove(key);
    }
  }
  
  static void clear() {
    // Don't clear on refresh - cache persists until app exit
  }
}

// Global throttling to limit concurrent thumbnail loads
// Very strict limits to prevent GPU/memory overload
class _ThumbnailLoader {
  static int _activeImageLoads = 0;
  static int _activeVideoLoads = 0;
  static const int _maxConcurrentImageLoads = 3;
  static const int _maxConcurrentVideoLoads = 2; // Limit concurrent video requests from Flutter
  static final List<Completer<void>> _waitingImages = [];
  static final List<Completer<void>> _waitingVideos = [];

  static Future<void> acquire({required bool isVideo}) async {
    if (isVideo) {
      if (_activeVideoLoads < _maxConcurrentVideoLoads) {
        _activeVideoLoads++;
        return;
      }
      final completer = Completer<void>();
      _waitingVideos.add(completer);
      return completer.future;
    } else {
      if (_activeImageLoads < _maxConcurrentImageLoads) {
        _activeImageLoads++;
        return;
      }
      final completer = Completer<void>();
      _waitingImages.add(completer);
      return completer.future;
    }
  }

  static void release({required bool isVideo}) {
    if (isVideo) {
      _activeVideoLoads--;
      if (_waitingVideos.isNotEmpty && _activeVideoLoads < _maxConcurrentVideoLoads) {
        _activeVideoLoads++;
        _waitingVideos.removeAt(0).complete();
      }
    } else {
      _activeImageLoads--;
      if (_waitingImages.isNotEmpty && _activeImageLoads < _maxConcurrentImageLoads) {
        _activeImageLoads++;
        _waitingImages.removeAt(0).complete();
      }
    }
  }
}

// Mixin to keep widgets alive once loaded - prevents reloading when scrolling back
class _StatusItemCardState extends State<StatusItemCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => _thumbnailLoaded; // Keep alive once thumbnail is loaded
  
  bool _thumbnailLoaded = false;
  
  void _markThumbnailLoaded() {
    if (!_thumbnailLoaded) {
      _thumbnailLoaded = true;
      updateKeepAlive(); // Notify framework to keep this widget alive
    }
  }

  static const _platform = MethodChannel('com.whatsappstatus.downloader/channel');
  Uint8List? _imageBytes;
  String? _videoThumbnailPath;
  bool _isLoadingThumbnail = false; // Start with false - show placeholder initially
  bool _hasError = false;
  bool _isLoadingStarted = false;
  bool _isCancelled = false;
  bool _cacheChecked = false;
  late final String _videoThumbRequestId = UniqueKey().toString();

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  // Check both in-memory cache and disk cache synchronously
  void _checkCache() {
    if (widget.item.isVideo) {
      // Check in-memory cache first (instant)
      final cachedPath = _ThumbnailCacheSync.getVideoThumbnail(
        widget.item.uri, 
        widget.item.lastModified
      );
      if (cachedPath != null) {
        _videoThumbnailPath = cachedPath;
        _isLoadingThumbnail = false;
        _cacheChecked = true;
        _markThumbnailLoaded(); // Mark as loaded so widget stays alive
        return;
      }
      
      // Check disk cache async (fast file existence check)
      _cacheChecked = true;
      _checkDiskCache();
    } else {
      // For images, check in-memory cache synchronously
      final cachedBytes = _ThumbnailCacheSync.getImageBytes(
        widget.item.uri, 
        widget.item.lastModified
      );
      if (cachedBytes != null) {
        _imageBytes = cachedBytes;
        _isLoadingThumbnail = false;
        _cacheChecked = true;
        _markThumbnailLoaded(); // Mark as loaded so widget stays alive
        return;
      }
      _cacheChecked = true;
    }
  }

  // Fast async cache check for video thumbnails - populates static cache for future builds
  Future<void> _checkDiskCache() async {
    try {
      final String? cachedPath = await _platform.invokeMethod<String>(
        'checkVideoThumbnailCache',
        <String, dynamic>{
          'uri': widget.item.uri,
          'lastModified': widget.item.lastModified,
        },
      );
      
      // Update static cache for synchronous access in future builds
      if (cachedPath != null) {
        _ThumbnailCacheSync.setVideoThumbnail(
          widget.item.uri, 
          widget.item.lastModified, 
          cachedPath
        );
        
        if (mounted && !_isCancelled) {
          setState(() {
            _videoThumbnailPath = cachedPath;
            _isLoadingThumbnail = false;
          });
          _markThumbnailLoaded();
          return;
        }
      }
    } catch (e) {
      // Cache check failed, proceed with placeholder
    }
    
    // Cache miss - don't trigger loading here, let didUpdateWidget handle it when visible
  }

  @override
  void didUpdateWidget(StatusItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When visibility changes, start loading if visible and not already loaded
    if (widget.isVisible && !oldWidget.isVisible) {
      _startLoadingIfNeeded();
    }
    // Don't cancel when going off-screen - keep thumbnails loaded for smooth scrolling
  }

  void _startLoadingIfNeeded() {
    // Don't start if already loading, cancelled, or already loaded
    if (_isLoadingStarted || _isCancelled) return;
    
    // Check if thumbnail is already loaded (from cache or previous load)
    final bool alreadyLoaded = widget.item.isVideo 
        ? (_videoThumbnailPath != null)
        : (_imageBytes != null);
    
    if (alreadyLoaded) {
      _markThumbnailLoaded();
      return; // Already have thumbnail, no need to load
    }
    
    // Mark as started immediately to prevent duplicate calls
    _isLoadingStarted = true;
    
    // Small delay to batch loads and prioritize UI rendering
    // Videos get slightly longer delay to prevent overload
    final delay = widget.item.isVideo 
        ? const Duration(milliseconds: 100) // Videos: wait 100ms after visible
        : const Duration(milliseconds: 50); // Images: wait 50ms after visible
    
    Future.delayed(delay, () {
      if (mounted && !_isCancelled && widget.isVisible && _isLoadingStarted) {
        _loadThumbnail();
      } else {
        // Reset if cancelled or not visible
        _isLoadingStarted = false;
      }
    });
  }

  @override
  void dispose() {
    _isCancelled = true;
    // Only cancel video thumbnail generation if not yet loaded
    if (widget.item.isVideo && _videoThumbnailPath == null) {
      _platform.invokeMethod('cancelVideoThumbnail', <String, dynamic>{
        'requestId': _videoThumbRequestId,
      }).catchError((_) {});
    }
    super.dispose();
  }

  Future<void> _loadThumbnail() async {
    if (widget.item.isVideo) {
      await _loadVideoThumbnail();
    } else {
      await _loadImageBytes();
    }
  }

  Future<void> _loadImageBytes() async {
    // Check if cancelled before starting
    if (_isCancelled || !mounted) {
      _isLoadingStarted = false;
      return;
    }

    // Check cache again (might have been loaded by another instance)
    final cachedBytes = _ThumbnailCacheSync.getImageBytes(
      widget.item.uri, 
      widget.item.lastModified
    );
    if (cachedBytes != null) {
      if (mounted && !_isCancelled) {
        setState(() {
          _imageBytes = cachedBytes;
          _isLoadingThumbnail = false;
          _hasError = false;
        });
        _markThumbnailLoaded();
        _isLoadingStarted = false;
      }
      return;
    }

    // Acquire lock to limit concurrent loads (images are fast)
    await _ThumbnailLoader.acquire(isVideo: false);
    try {
      // Check again after acquiring lock
      if (_isCancelled || !mounted) {
        _isLoadingStarted = false;
        return;
      }

      setState(() {
        _isLoadingThumbnail = true;
        _hasError = false;
      });

      // Read file bytes (platform channel is async, doesn't block main thread)
      final Uint8List? bytes = await _platform.invokeMethod<Uint8List>(
        'readFileBytes',
        <String, dynamic>{'uri': widget.item.uri},
      );

      if (_isCancelled || !mounted) {
        _isLoadingStarted = false;
        return;
      }

      if (bytes == null) {
        if (mounted && !_isCancelled) {
          setState(() {
            _isLoadingThumbnail = false;
            _hasError = true;
          });
        }
        _isLoadingStarted = false;
        return;
      }

      // Cache the bytes for future use (persists across tab switches)
      _ThumbnailCacheSync.setImageBytes(
        widget.item.uri, 
        widget.item.lastModified, 
        bytes
      );

      // Use original bytes - Image.memory handles async decoding efficiently
      if (mounted && !_isCancelled) {
        setState(() {
          _imageBytes = bytes;
          _isLoadingThumbnail = false;
          _hasError = false;
        });
        _markThumbnailLoaded(); // Keep widget alive now that thumbnail is loaded
      }
    } catch (e) {
      if (mounted && !_isCancelled) {
        setState(() {
          _isLoadingThumbnail = false;
          _hasError = true;
        });
      }
    } finally {
      _ThumbnailLoader.release(isVideo: false);
      _isLoadingStarted = false;
    }
  }

  Future<void> _loadVideoThumbnail() async {
    // Only generate if cache miss (thumbnail not already loaded)
    if (_videoThumbnailPath != null) {
      _markThumbnailLoaded();
      _isLoadingStarted = false;
      return;
    }
    
    // Check cache again (might have been loaded by another instance)
    final cachedPath = _ThumbnailCacheSync.getVideoThumbnail(
      widget.item.uri, 
      widget.item.lastModified
    );
    if (cachedPath != null) {
      if (mounted && !_isCancelled) {
        setState(() {
          _videoThumbnailPath = cachedPath;
          _isLoadingThumbnail = false;
          _hasError = false;
        });
        _markThumbnailLoaded();
        _isLoadingStarted = false;
      }
      return;
    }
    
    // Acquire lock to limit concurrent requests (Android also limits decode to 2 threads)
    await _ThumbnailLoader.acquire(isVideo: true);
    try {
      if (_isCancelled || !mounted) {
        _isLoadingStarted = false;
        return;
      }

      setState(() {
        _isLoadingThumbnail = true;
        _hasError = false;
      });

      // Video thumbnail generation must NOT run on Flutter UI thread.
      // Delegate to Android: background ExecutorService (fixed pool) + disk cache + cancellation.
      final String? thumbnailPath = await _platform.invokeMethod<String>(
        'getVideoThumbnail',
        <String, dynamic>{
          'requestId': _videoThumbRequestId,
          'uri': widget.item.uri,
          'lastModified': widget.item.lastModified,
        },
      );

      if (_isCancelled || !mounted) {
        _isLoadingStarted = false;
        return;
      }

      if (mounted && !_isCancelled) {
        // Update static cache for future synchronous access (persists across tab switches)
        if (thumbnailPath != null) {
          _ThumbnailCacheSync.setVideoThumbnail(
            widget.item.uri, 
            widget.item.lastModified, 
            thumbnailPath
          );
        }
        
        setState(() {
          _videoThumbnailPath = thumbnailPath;
          _isLoadingThumbnail = false;
          _hasError = thumbnailPath == null;
        });
        _markThumbnailLoaded(); // Keep widget alive now that thumbnail is loaded
      }
    } catch (e) {
      if (mounted && !_isCancelled) {
        setState(() {
          _isLoadingThumbnail = false;
          _hasError = true;
        });
      }
    } finally {
      _ThumbnailLoader.release(isVideo: true);
      _isLoadingStarted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    final isVideo = widget.item.isVideo;
    final sizeInMB = (widget.item.size / (1024 * 1024)).toStringAsFixed(2);
    
    // Trigger loading if visible and not already loaded/loading
    if (widget.isVisible && _cacheChecked && !_isLoadingStarted && !_isCancelled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isVisible) {
          _startLoadingIfNeeded();
        }
      });
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_hasError)
                    Container(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: Icon(
                        isVideo ? Icons.videocam : Icons.image,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else if (!isVideo && _imageBytes != null)
                    Image.memory(
                      _imageBytes!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          child: const Icon(
                            Icons.image,
                            size: 48,
                          ),
                        );
                      },
                    )
                  else if (isVideo && _videoThumbnailPath != null)
                    Image.file(
                      File(_videoThumbnailPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          child: const Icon(
                            Icons.videocam,
                            size: 48,
                          ),
                        );
                      },
                    )
                  else
                    // Placeholder only shown on cache miss (for videos) or before image load
                    Container(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: Icon(
                        isVideo ? Icons.videocam : Icons.image,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    widget.item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$sizeInMB MB · ${isVideo ? 'Video' : 'Image'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: widget.onDownload,
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
  static const _platform = MethodChannel('com.whatsappstatus.downloader/channel');
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoLoading = false;
  String? _errorMessage;
  Uint8List? _imageBytes;
  bool _isImageLoading = true;
  File? _tempVideoFile;

  @override
  void initState() {
    super.initState();
    if (widget.item.isVideo) {
      _loadVideoPreview();
    } else {
      _loadImagePreview();
    }
  }

  Future<void> _loadImagePreview() async {
    try {
      setState(() {
        _isImageLoading = true;
        _errorMessage = null;
      });

      final Uint8List? bytes = await _platform.invokeMethod<Uint8List>(
        'readFileBytes',
        <String, dynamic>{'uri': widget.item.uri},
      );

      if (mounted) {
        setState(() {
          _imageBytes = bytes;
          _isImageLoading = false;
          if (bytes == null) {
            _errorMessage = 'Unable to load image';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImageLoading = false;
          _errorMessage = 'Unable to load image: $e';
        });
      }
    }
  }

  Future<void> _loadVideoPreview() async {
    try {
      setState(() {
        _isVideoLoading = true;
        _errorMessage = null;
      });

      // Copy content URI to temp file for video_player
      final Uint8List? bytes = await _platform.invokeMethod<Uint8List>(
        'readFileBytes',
        <String, dynamic>{'uri': widget.item.uri},
      );

      if (bytes == null) {
        throw Exception('Failed to read video file');
      }

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${widget.item.name}');
      await tempFile.writeAsBytes(bytes);

      if (mounted) {
        _videoController = VideoPlayerController.file(tempFile);
        await _videoController!.initialize();
        
        if (mounted) {
          setState(() {
            _isVideoInitialized = true;
            _isVideoLoading = false;
            _tempVideoFile = tempFile;
          });
          _videoController?.play();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
          _errorMessage = 'Unable to load video: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    // Clean up temp file
    _tempVideoFile?.delete().catchError((_) {});
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
    if (_isImageLoading) {
      return const CircularProgressIndicator();
    }

    if (_errorMessage != null || _imageBytes == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image, size: 72),
          const SizedBox(height: 12),
          Text(_errorMessage ?? 'Unable to load image'),
        ],
      );
    }

    return InteractiveViewer(
      child: Image.memory(
        _imageBytes!,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildVideoPreview() {
    if (_isVideoLoading) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading video...'),
        ],
      );
    }

    if (_errorMessage != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 72),
          const SizedBox(height: 12),
          Text(_errorMessage!),
        ],
      );
    }

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

// Helper functions to run in isolates (off main thread)

/// Parse status items in isolate to avoid blocking main thread
List<StatusItem> _parseStatusItems(List<dynamic> result) {
  return result.map((item) => StatusItem.fromMap(item)).toList();
}


