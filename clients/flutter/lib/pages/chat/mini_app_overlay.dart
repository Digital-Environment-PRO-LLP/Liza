import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/mini_app_manager.dart';
import 'package:liza/pages/chat/mini_app_web_view.dart';

/// Высота контента свёрнутой плашки (без bottom safe-area).
///
/// Эту же величину чат резервирует снизу под полем ввода
/// ([ChatInputRow]), чтобы плашка не перекрывала инпут.
const double kMiniAppCollapsedBarHeight = 26;

/// Глобальный overlay для miniApp — оборачивает child (Router) и рисует
/// поверх него свёрнутую плашку или развёрнутое окно miniApp.
///
/// Встраивается в LizaApp.builder, чтобы быть поверх любого экрана.
class MiniAppOverlay extends StatefulWidget {
  final Widget child;

  const MiniAppOverlay({required this.child, super.key});

  @override
  State<MiniAppOverlay> createState() => _MiniAppOverlayState();
}

class _MiniAppOverlayState extends State<MiniAppOverlay>
    with SingleTickerProviderStateMixin {
  final _manager = MiniAppManager.instance;

  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;

  // Ключи для сохранения состояния WebView каждого miniApp
  final Map<String, GlobalKey<MiniAppWebViewContentState>> _webViewKeys = {};

  // Drag offset для свайпа вниз
  double _dragOffset = 0;
  static const _minimizeThreshold = 150.0;
  static const _velocityThreshold = 200.0;

  // Локальный тост поверх листа mini App: ScaffoldMessenger тут бесполезен —
  // overlay смонтирован в LizaApp.builder ПОВЕРХ Router, и корневой SnackBar
  // рисуется ПОД листом (elevation 16, во весь экран).
  String? _toast;
  int _toastGen = 0;

  void _showToast(String message, {bool autoHide = true}) {
    final gen = ++_toastGen;
    setState(() => _toast = message);
    if (autoHide) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _toastGen == gen) setState(() => _toast = null);
      });
    }
  }

  Future<void> _shareActiveAppLink() async {
    final app = _manager.activeApp;
    if (app == null) return;
    final state = _webViewKeys[app.appId]?.currentState;
    if (state == null) return;
    _showToast(L10n.of(context).miniAppCreatingLink, autoHide: false);
    final msg = await state.copyInviteLink();
    if (mounted) _showToast(msg);
  }

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onManagerChanged);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    _slideController.dispose();
    super.dispose();
  }

  void _onManagerChanged() {
    if (_manager.hasApps && _manager.isExpanded) {
      _slideController.forward();
    } else {
      _slideController.reverse();
    }
    setState(() {});
  }

  GlobalKey<MiniAppWebViewContentState> _keyFor(String appId) {
    return _webViewKeys.putIfAbsent(
      appId,
      () => GlobalKey<MiniAppWebViewContentState>(),
    );
  }

  void _cleanupKeys() {
    final activeIds = _manager.apps.map((a) => a.appId).toSet();
    _webViewKeys.removeWhere((id, _) => !activeIds.contains(id));
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset =
          (_dragOffset + details.delta.dy).clamp(0.0, double.infinity);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_dragOffset > _minimizeThreshold ||
        details.velocity.pixelsPerSecond.dy > _velocityThreshold) {
      _manager.minimize();
    }
    setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    _cleanupKeys();

    final topPadding = MediaQuery.of(context).padding.top;
    final screenHeight = MediaQuery.of(context).size.height;
    // Лист стартует сразу под статус-баром — без лишнего зазора сверху, чтобы
    // интерфейс магазина занимал максимум высоты.
    final sheetTop = topPadding;

    return Stack(
      children: [
        // Основной UI приложения
        widget.child,

        // Свёрнутая плашка
        if (_manager.hasApps && !_manager.isExpanded)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _MiniAppCollapsedBar(manager: _manager),
          ),

        // Развёрнутый miniApp — Positioned + SlideTransition
        if (_manager.hasApps)
          Positioned(
            left: 0,
            right: 0,
            top: sheetTop + _dragOffset,
            height: (screenHeight - sheetTop - _dragOffset).clamp(0.0, screenHeight),
            child: SlideTransition(
              position: _slideAnimation,
              child: Material(
                elevation: 16,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                clipBehavior: Clip.antiAlias,
                color: Theme.of(context).colorScheme.surface,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        _MiniAppHeader(
                          app: _manager.activeApp,
                          manager: _manager,
                          onDragUpdate: _onDragUpdate,
                          onDragEnd: _onDragEnd,
                          onShareLink: _shareActiveAppLink,
                        ),
                        Expanded(child: _buildWebViewStack()),
                      ],
                    ),
                    if (_toast != null)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 32,
                        child: _MiniAppToast(text: _toast!),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWebViewStack() {
    final apps = _manager.apps;
    final activeId = _manager.activeAppId;
    final activeIndex = apps.indexWhere((a) => a.appId == activeId);

    if (apps.isEmpty) return const SizedBox.shrink();

    return IndexedStack(
      index: activeIndex >= 0 ? activeIndex : 0,
      children: [
        for (final app in apps)
          MiniAppWebViewContent(
            key: _keyFor(app.appId),
            appUrl: app.appUrl,
            appId: app.appId,
            appName: app.appName,
            room: app.room,
            appType: app.appType,
            onClose: () => _manager.close(app.appId),
            onMinimize: () => _manager.minimize(),
          ),
      ],
    );
  }
}

/// Свёрнутая плашка внизу экрана — компактная, как в Liza.
///
/// Один miniApp → тап разворачивает.
/// Несколько → тап показывает bottom sheet со списком для переключения.
class _MiniAppCollapsedBar extends StatelessWidget {
  final MiniAppManager manager;

  const _MiniAppCollapsedBar({required this.manager});

  void _onTap(BuildContext context) {
    if (manager.appCount <= 1) {
      manager.expand();
      return;
    }
    // Несколько miniApp — показываем выбор
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final app in manager.apps)
              ListTile(
                leading: const Icon(Icons.web_asset, size: 24),
                title: Text(app.appName),
                trailing: app.appId == manager.activeAppId
                    ? Icon(Icons.check_circle,
                        color: Theme.of(ctx).colorScheme.primary, size: 20)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  manager.expand(app.appId);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final activeApp = manager.activeApp;
    if (activeApp == null) return const SizedBox.shrink();

    final otherCount = manager.appCount - 1;
    final label = otherCount > 0
        ? L10n.of(context).miniAppAndOthers(activeApp.appName, otherCount)
        : activeApp.appName;

    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        padding: EdgeInsets.only(bottom: bottomPadding),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 4,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: SizedBox(
          height: kMiniAppCollapsedBarHeight,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(
                Icons.storefront_outlined,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              // Название
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.keyboard_arrow_up,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              // X — закрыть все
              SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 15),
                  onPressed: () => manager.closeAll(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 15,
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header развёрнутого miniApp — drag-handle, название, кнопки.
class _MiniAppHeader extends StatelessWidget {
  final MiniAppInstance? app;
  final MiniAppManager manager;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  /// Колбэк пункта меню «Скопировать ссылку» (создаёт invite на текущую
  /// страницу). null — меню не показываем.
  final VoidCallback? onShareLink;

  const _MiniAppHeader({
    required this.app,
    required this.manager,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.onShareLink,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appName = app?.appName ?? '';

    return GestureDetector(
      onVerticalDragUpdate: onDragUpdate,
      onVerticalDragEnd: onDragEnd,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title row
            SizedBox(
              height: 38,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, size: 22),
                    onPressed: () {
                      if (app != null) manager.close(app!.appId);
                    },
                  ),
                  Expanded(
                    child: Text(
                      appName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onShareLink != null)
                    PopupMenuButton<String>(
                      tooltip: L10n.of(context).miniAppMore,
                      icon: const Icon(Icons.more_vert, size: 22),
                      onSelected: (v) {
                        if (v == 'copy_link') onShareLink!();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem<String>(
                          value: 'copy_link',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.link, size: 20),
                              const SizedBox(width: 12),
                              Text(L10n.of(context).miniAppCopyLink),
                            ],
                          ),
                        ),
                      ],
                    ),
                  IconButton(
                    icon: const Icon(Icons.minimize, size: 22),
                    onPressed: () => manager.minimize(),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
          ],
        ),
      ),
    );
  }
}

/// Локальный тост поверх листа mini App (вместо ScaffoldMessenger, который тут
/// уходит под лист). Авто-скрытие — на стороне overlay.
class _MiniAppToast extends StatelessWidget {
  final String text;

  const _MiniAppToast({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Center(
        child: Material(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onInverseSurface,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
