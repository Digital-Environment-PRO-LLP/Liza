import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_linkify/flutter_linkify.dart' show LinkableElement;
import 'package:highlight/highlight.dart' show highlight;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:matrix/matrix.dart';

import 'package:liza/utils/code_highlight_theme.dart';
import 'package:liza/utils/event_checkbox_extension.dart';
import 'package:liza/utils/platform_infos.dart';
import 'package:liza/widgets/avatar.dart';
import 'package:liza/widgets/future_loading_dialog.dart';
import 'package:liza/widgets/mxc_image.dart';
import '../../../utils/url_launcher.dart';
import 'linkified_span.dart';

// isForcedListArtifact живёт в utils/forced_list_artifact.dart; ре-экспорт —
// чтобы message_content.dart / media_caption.dart (импортят этот файл ради
// HtmlMessage) продолжали видеть функцию без второго импорта.
export 'package:liza/utils/forced_list_artifact.dart' show isForcedListArtifact;

class HtmlMessage extends StatefulWidget {
  final String html;
  final Room room;
  final Color textColor;
  final double fontSize;
  final TextStyle linkStyle;
  final void Function(LinkableElement) onOpen;
  final String? eventId;
  final Set<Event>? checkboxCheckedEvents;
  final bool limitHeight;

  /// Хвостовой inline-span (время сообщения) — добавляется в конец текста, чтобы
  /// «плыть» в конце последней строки (Liza-стиль). Время — обычным
  /// `TextSpan` (надёжно течёт по строке); галочка своих — маленьким `WidgetSpan`.
  final InlineSpan? trailingSpan;

  const HtmlMessage({
    super.key,
    required this.html,
    required this.room,
    required this.fontSize,
    required this.linkStyle,
    this.textColor = Colors.black,
    required this.onOpen,
    this.eventId,
    this.checkboxCheckedEvents,
    this.limitHeight = true,
    this.trailingSpan,
  });

  @override
  State<HtmlMessage> createState() => _HtmlMessageState();
}

class _HtmlMessageState extends State<HtmlMessage> {
  /// Пул распознавателей ссылок (см. [buildLinkifiedSpans]). Пересоздаётся на
  /// каждый build (спаны строятся заново), поэтому старые обязательно
  /// освобождаем — иначе утечка на горячем пути ленты.
  final List<GestureRecognizer> _linkRecognizers = [];

  @override
  void dispose() {
    disposeRecognizers(_linkRecognizers);
    super.dispose();
  }

  /// Keep in sync with: https://spec.matrix.org/latest/client-server-api/#mroommessage-msgtypes
  static const Set<String> allowedHtmlTags = {
    'font',
    'del',
    's',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'p',
    'a',
    'ul',
    'ol',
    'sup',
    'sub',
    'li',
    'b',
    'i',
    'u',
    'strong',
    'em',
    'strike',
    'code',
    'hr',
    'br',
    'div',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
    'caption',
    'pre',
    'span',
    'img',
    'details',
    'summary',
    // Not in the allowlist of the matrix spec yet but should be harmless:
    'ruby',
    'rp',
    'rt',
    'html',
    'body',
  };

  static const Set<String> ignoredHtmlTags = {'mx-reply'};

  /// We add line breaks before these tags:
  static const Set<String> blockHtmlTags = {
    'p',
    'ul',
    'ol',
    'pre',
    'div',
    'table',
    'details',
    'blockquote',
  };

  /// We add line breaks before these tags:
  static const Set<String> fullLineHtmlTag = {
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'li',
  };

  /// Adding line breaks before block elements.
  List<InlineSpan> _renderWithLineBreaks(
    dom.NodeList nodes,
    BuildContext context, {
    int depth = 1,
  }) {
    final onlyElements = nodes.whereType<dom.Element>().toList();
    return [
      for (var i = 0; i < nodes.length; i++) ...[
        // Actually render the node child:
        _renderHtml(nodes[i], context, depth: depth + 1),
        // Add linebreaks between blocks:
        if (nodes[i] is dom.Element &&
            onlyElements.indexOf(nodes[i] as dom.Element) <
                onlyElements.length - 1) ...[
          if (blockHtmlTags.contains((nodes[i] as dom.Element).localName))
            const TextSpan(text: '\n\n'),
          if (fullLineHtmlTag.contains((nodes[i] as dom.Element).localName))
            const TextSpan(text: '\n'),
        ],
      ],
    ];
  }

  InlineSpan _renderCodeBlockNode(dom.Node node) {
    if (node is! dom.Element) {
      return TextSpan(text: node.text);
    }
    final style =
        atomOneDarkTheme[node.className.split('-').last] ??
        atomOneDarkTheme['root'];

    return TextSpan(
      children: node.nodes.map(_renderCodeBlockNode).toList(),
      style: style,
    );
  }

  /// Transforms a Node to an InlineSpan.
  InlineSpan _renderHtml(dom.Node node, BuildContext context, {int depth = 1}) {
    final fontSize = widget.fontSize;
    final textColor = widget.textColor;
    final linkStyle = widget.linkStyle;
    // We must not render elements nested more than 100 elements deep:
    if (depth >= 100) return const TextSpan();

    if (node is dom.Element &&
        ignoredHtmlTags.contains(node.localName?.toLowerCase())) {
      return const TextSpan();
    }

    // This is a text node or not permitted node, so we render it as text:
    if (node is! dom.Element || !allowedHtmlTags.contains(node.localName)) {
      var text = node.text ?? '';
      // Single linebreak nodes between Elements are ignored:
      if (text == '\n') text = '';

      // Автоопределённые ссылки в тексте: тап открывает, правый клик/долгое
      // нажатие — меню ссылки (LABA-1965). Заменяет LinkifySpan, чтобы навесить
      // на каждую ссылку свой распознаватель с контекстным меню.
      return TextSpan(
        children: buildLinkifiedSpans(
          context: context,
          text: text,
          // Явный стиль (паритет с media_caption/poll): сырой TextSpan без style
          // в офскрин-снимке пузыря (toImageSync для контекстного меню)
          // подхватывает ambient DefaultTextStyle, который вне Material
          // резолвится в Flutter _errorTextStyle → жёлтая двойная линия.
          textStyle: TextStyle(
            color: textColor,
            fontSize: fontSize,
            decoration: TextDecoration.none,
          ),
          linkStyle: linkStyle,
          onOpen: widget.onOpen,
          recognizerPool: _linkRecognizers,
        ),
      );
    }

    switch (node.localName) {
      case 'br':
        return const TextSpan(text: '\n');
      case 'a':
        final href = node.attributes['href'];
        if (href == null) continue block;
        final matrixId = node.attributes['href']
            ?.parseIdentifierIntoParts()
            ?.primaryIdentifier;
        if (matrixId != null) {
          if (matrixId.sigil == '@') {
            final user = widget.room.unsafeGetUserFromMemoryOrFallback(matrixId);
            return WidgetSpan(
              child: MatrixPill(
                key: Key('user_pill_$matrixId'),
                name: user.calcDisplayname(),
                avatar: user.avatarUrl,
                uri: href,
                outerContext: context,
                fontSize: fontSize,
                color: linkStyle.color,
              ),
            );
          }
          if (matrixId.sigil == '#' || matrixId.sigil == '!') {
            final room = matrixId.sigil == '!'
                ? widget.room.client.getRoomById(matrixId)
                : widget.room.client.getRoomByAlias(matrixId);
            return WidgetSpan(
              child: MatrixPill(
                name: room?.getLocalizedDisplayname() ?? matrixId,
                avatar: room?.avatar,
                uri: href,
                outerContext: context,
                fontSize: fontSize,
                color: linkStyle.color,
              ),
            );
          }
        }
        return WidgetSpan(
          child: Tooltip(
            message: href,
            child: InkWell(
              splashColor: Colors.transparent,
              onTap: () => UrlLauncher(context, href, node.text).launchUrl(),
              // Правый клик (desktop/web) и долгое нажатие (mobile) по HTML-
              // ссылке — меню ссылки вместо меню сообщения (LABA-1965). InkWell
              // сам член арены и выигрывает у GestureDetector пузыря.
              onSecondaryTapDown: PlatformInfos.isMobile
                  ? null
                  : (_) => showLinkContextMenu(context, href),
              onLongPress: PlatformInfos.isMobile
                  ? () => showLinkContextMenu(context, href)
                  : null,
              child: Text.rich(
                TextSpan(
                  children: _renderWithLineBreaks(
                    node.nodes,
                    context,
                    depth: depth,
                  ),
                  style: linkStyle,
                ),
                style: const TextStyle(height: 1.25),
              ),
            ),
          ),
        );
      case 'li':
        if (!{'ol', 'ul'}.contains(node.parent?.localName)) {
          continue block;
        }
        final eventId = widget.eventId;

        final isCheckbox = node.className == 'task-list-item';
        final checkboxIndex = isCheckbox
            ? node.rootElement
                      .getElementsByClassName('task-list-item')
                      .indexOf(node) +
                  1
            : null;
        final checkedByReaction = !isCheckbox
            ? null
            : widget.checkboxCheckedEvents?.firstWhereOrNull(
                (event) => event.checkedCheckboxId == checkboxIndex,
              );
        final staticallyChecked = !isCheckbox
            ? false
            : node.children.first.attributes['checked'] == 'true';

        return WidgetSpan(
          child: Padding(
            padding: EdgeInsets.only(left: fontSize),
            child: Text.rich(
              TextSpan(
                children: [
                  if (!isCheckbox) ...[
                    if (node.parent?.localName == 'ul')
                      const TextSpan(text: '• '),
                    if (node.parent?.localName == 'ol')
                      TextSpan(
                        text:
                            '${(node.parent?.nodes.whereType<dom.Element>().toList().indexOf(node) ?? 0) + (int.tryParse(node.parent?.attributes['start'] ?? '1') ?? 1)}. ',
                      ),
                  ],
                  if (node.className == 'task-list-item')
                    WidgetSpan(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: SizedBox.square(
                          dimension: fontSize + 2,
                          child: CupertinoCheckbox(
                            checkColor: textColor,
                            side: BorderSide(color: textColor),
                            activeColor: textColor.withAlpha(64),
                            value:
                                staticallyChecked || checkedByReaction != null,
                            onChanged:
                                eventId == null ||
                                    checkboxIndex == null ||
                                    staticallyChecked ||
                                    !widget.room.canSendDefaultMessages ||
                                    (checkedByReaction != null &&
                                        checkedByReaction.senderId !=
                                            widget.room.client.userID)
                                ? null
                                : (_) => showFutureLoadingDialog(
                                    context: context,
                                    future: () => checkedByReaction != null
                                        ? widget.room.redactEvent(
                                            checkedByReaction.eventId,
                                          )
                                        : widget.room.checkCheckbox(
                                            eventId,
                                            checkboxIndex,
                                          ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ..._renderWithLineBreaks(node.nodes, context, depth: depth),
                ],
                style: TextStyle(fontSize: fontSize, color: textColor),
              ),
            ),
          ),
        );
      case 'blockquote':
        return WidgetSpan(
          child: Container(
            padding: const EdgeInsets.only(left: 8.0),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: textColor, width: 5)),
            ),
            child: Text.rich(
              TextSpan(
                children: _renderWithLineBreaks(
                  node.nodes,
                  context,
                  depth: depth,
                ),
              ),
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: fontSize,
                color: textColor,
              ),
            ),
          ),
        );
      case 'code':
        final isInline = node.parent?.localName != 'pre';
        final lang =
            node.className
                .split(' ')
                .singleWhereOrNull(
                  (className) => className.startsWith('language-'),
                )
                ?.split('language-')
                .last ??
            'md';
        final highlightedHtml = highlight
            .parse(node.text, language: lang)
            .toHtml();
        final element = parser.parse(highlightedHtml).body;
        if (element == null) {
          return const TextSpan(text: 'Unable to render code block!');
        }

        return WidgetSpan(
          child: Material(
            color: atomOneBackgroundColor,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: hightlightTextColor),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: isInline
                  ? const EdgeInsets.symmetric(horizontal: 4.0)
                  : const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Text.rich(
                TextSpan(children: [_renderCodeBlockNode(element)]),
                selectionColor: hightlightTextColor.withAlpha(128),
              ),
            ),
          ),
        );
      case 'img':
        final mxcUrl = Uri.tryParse(node.attributes['src'] ?? '');
        if (mxcUrl == null || mxcUrl.scheme != 'mxc') {
          return TextSpan(text: node.attributes['alt']);
        }

        final width = double.tryParse(node.attributes['width'] ?? '');
        final height = double.tryParse(node.attributes['height'] ?? '');
        const defaultDimension = 64.0;
        final actualWidth = width ?? height ?? defaultDimension;
        final actualHeight = height ?? width ?? defaultDimension;

        return WidgetSpan(
          child: SizedBox(
            width: actualWidth,
            height: actualHeight,
            child: MxcImage(
              uri: mxcUrl,
              width: actualWidth,
              height: actualHeight,
              isThumbnail: (actualWidth * actualHeight) > (256 * 256),
            ),
          ),
        );
      case 'hr':
        return const WidgetSpan(child: Divider());
      case 'details':
        var obscure = true;
        return WidgetSpan(
          child: StatefulBuilder(
            builder: (context, setState) => InkWell(
              splashColor: Colors.transparent,
              onTap: () => setState(() {
                obscure = !obscure;
              }),
              child: Text.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      child: Icon(
                        obscure ? Icons.arrow_right : Icons.arrow_drop_down,
                        size: fontSize * 1.2,
                        color: textColor,
                      ),
                    ),
                    if (obscure)
                      ...node.nodes
                          .where(
                            (node) =>
                                node is dom.Element &&
                                node.localName == 'summary',
                          )
                          .map(
                            (node) => _renderHtml(node, context, depth: depth),
                          )
                    else
                      ..._renderWithLineBreaks(
                        node.nodes,
                        context,
                        depth: depth,
                      ),
                  ],
                ),
                style: TextStyle(fontSize: fontSize, color: textColor),
              ),
            ),
          ),
        );
      case 'span':
        if (!node.attributes.containsKey('data-mx-spoiler')) {
          continue block;
        }
        var obscure = true;
        return WidgetSpan(
          child: StatefulBuilder(
            builder: (context, setState) => InkWell(
              splashColor: Colors.transparent,
              onTap: () => setState(() {
                obscure = !obscure;
              }),
              child: Text.rich(
                TextSpan(
                  children: _renderWithLineBreaks(
                    node.nodes,
                    context,
                    depth: depth,
                  ),
                ),
                style: TextStyle(
                  fontSize: fontSize,
                  color: textColor,
                  backgroundColor: obscure ? textColor : null,
                ),
              ),
            ),
          ),
        );
      block:
      default:
        return TextSpan(
          style: switch (node.localName) {
            'body' => TextStyle(fontSize: fontSize, color: textColor),
            'a' => linkStyle,
            // `b` и `strike` есть в allowedHtmlTags, но раньше отсутствовали
            // здесь — жирное от чужих клиентов рисовалось обычным, а `<strike>`
            // не зачёркивалось (ключ `strikethrough` — не HTML-тег, мёртвая
            // ветка). INV-E11: рендер обязан покрывать всё, что понимает парсер.
            'strong' || 'b' => const TextStyle(fontWeight: FontWeight.bold),
            'em' || 'i' => const TextStyle(fontStyle: FontStyle.italic),
            'del' || 's' || 'strike' => const TextStyle(
              decoration: TextDecoration.lineThrough,
            ),
            'u' => const TextStyle(decoration: TextDecoration.underline),
            'h1' => TextStyle(fontSize: fontSize * 1.6, height: 2),
            'h2' => TextStyle(fontSize: fontSize * 1.5, height: 2),
            'h3' => TextStyle(fontSize: fontSize * 1.4, height: 2),
            'h4' => TextStyle(fontSize: fontSize * 1.3, height: 1.75),
            'h5' => TextStyle(fontSize: fontSize * 1.2, height: 1.75),
            'h6' => TextStyle(fontSize: fontSize * 1.1, height: 1.5),
            'span' => TextStyle(
              color:
                  node.attributes['color']?.hexToColor ??
                  node.attributes['data-mx-color']?.hexToColor ??
                  textColor,
              backgroundColor: node.attributes['data-mx-bg-color']?.hexToColor,
            ),
            'sup' => const TextStyle(
              fontFeatures: [FontFeature.superscripts()],
            ),
            'sub' => const TextStyle(fontFeatures: [FontFeature.subscripts()]),
            _ => null,
          },
          children: _renderWithLineBreaks(node.nodes, context, depth: depth),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Спаны (и их распознаватели ссылок) строятся заново — освобождаем прошлые.
    // Известное ограничение паттерна «dispose-in-build»: ре-билд во время
    // удержания пальца (до порога long-press) синхронно отклонит активный жест
    // ссылки — меню может не открыться с первого раза. Полный фикс (диф-пул по
    // URL) архитектурно тяжелее; на практике ре-билд ленты под пальцем редок.
    disposeRecognizers(_linkRecognizers);
    final element = parser.parse(widget.html).body ?? dom.Element.html('');
    final root = _renderHtml(element, context);
    final trailingSpan = widget.trailingSpan;
    // ЕДИНАЯ страховка от жёлтой _errorTextStyle-декорации (двойное подчёркивание
    // 0xFFFFFF00): пузырь сообщения рисуется под `BubbleBackground` (CustomPaint)
    // БЕЗ близкого Material-предка, поэтому его ambient DefaultTextStyle может
    // оказаться корневым `_errorTextStyle` (WidgetsApp.textStyle) — тогда любой
    // текст без своего `decoration` наследует жёлтую линию (видно в офскрин-снимке
    // контекстного меню, `toImageSync`). `DefaultTextStyle.merge` кладёт чистый
    // `decoration: none` как ambient для ВСЕГО поддерева — включая вложенные
    // `Text.rich` внутри `WidgetSpan` (blockquote/li/details/spoiler/<a>), которые
    // НЕ наследуют стиль корневого `Text.rich` (WidgetSpan разрывает span-дерево).
    // Намеренные декорации (<u>/<del>/ссылки/pill) задают свой decoration и
    // перекрывают этот none.
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: Text.rich(
        trailingSpan == null ? root : TextSpan(children: [root, trailingSpan]),
        style: TextStyle(
          fontSize: widget.fontSize,
          color: widget.textColor,
          decoration: TextDecoration.none,
        ),
        maxLines: null,
        selectionColor: widget.textColor.withAlpha(128),
      ),
    );
  }
}

class MatrixPill extends StatelessWidget {
  final String name;
  final BuildContext outerContext;
  final Uri? avatar;
  final String uri;
  final double? fontSize;
  final Color? color;

  const MatrixPill({
    super.key,
    required this.name,
    required this.outerContext,
    this.avatar,
    required this.uri,
    required this.fontSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashColor: Colors.transparent,
      onTap: UrlLauncher(outerContext, uri).launchUrl,
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              child: Padding(
                padding: const EdgeInsets.only(right: 4.0),
                child: Avatar(mxContent: avatar, name: name, size: 16),
              ),
            ),
            TextSpan(
              text: name,
              style: TextStyle(
                color: color,
                decorationColor: color,
                decoration: TextDecoration.underline,
                fontSize: fontSize,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  Color? get hexToColor {
    var hexCode = this;
    if (hexCode.startsWith('#')) hexCode = hexCode.substring(1);
    if (hexCode.length == 6) hexCode = 'FF$hexCode';
    final colorValue = int.tryParse(hexCode, radix: 16);
    return colorValue == null ? null : Color(colorValue);
  }
}

extension on dom.Element {
  dom.Element get rootElement => parent?.rootElement ?? this;
}
