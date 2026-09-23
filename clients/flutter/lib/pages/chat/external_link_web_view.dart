import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:matrix/matrix.dart';

/// Лёгкий встроенный webview для ВНЕШНЕЙ ссылки (кнопка `open_link` карточки
/// `com.liza.miniapp.choice`, напр. «Стать продавцом» → Яндекс-форма).
///
/// СОЗНАТЕЛЬНО отдельный от [MiniAppWebView]: тот завязан на mini-app-контракт
/// (обязательный `init_data`-POST к Synapse, реестр app_id, allowlist навигации
/// только на домен приложения + платёжки, beacon аналитики D-γ). Для стороннего
/// сайта всё это неприменимо — здесь просто открываем `https`-страницу без
/// подписи, без beacon, без mini-app-мостов. Навигация разрешена только по
/// `http(s)` (любые `javascript:`/`intent:`/кастом-схемы блокируем).
class ExternalLinkWebView extends StatefulWidget {
  final String url;

  /// Закрывать webview при возврате с платёжной формы Prodamus (навигация на
  /// `…/payment/success` или `…/payment/return` — наши sentinel-эндпоинты
  /// urlSuccess/urlReturn). Нужно url-кнопке «Оплатить» бота: без этого форма
  /// после оплаты редиректит на SPA магазина (дефолтный экран «Liza Wall»), а по
  /// требованию пользователя окно оплаты должно ЗАКРЫТЬСЯ и вернуть в чат бота.
  final bool closeOnPaymentReturn;

  const ExternalLinkWebView({
    required this.url,
    this.closeOnPaymentReturn = false,
    super.key,
  });

  /// Открывает ссылку во встроенном webview. Принимает ТОЛЬКО `https`-URL
  /// (валидация на границе — URL приходит из события бота). Возвращает без
  /// действия, если схема не `https`.
  static Future<void> open({
    required BuildContext context,
    required String url,
    bool closeOnPaymentReturn = false,
  }) async {
    if (!isSafeHttpsUrl(url) || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExternalLinkWebView(
          url: url,
          closeOnPaymentReturn: closeOnPaymentReturn,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<ExternalLinkWebView> createState() => _ExternalLinkWebViewState();
}

/// Навигация ведёт на sentinel-эндпоинт возврата платёжки Prodamus
/// (`/payment/success` — urlSuccess, `/payment/return` — urlReturn). По этим
/// путям после оплаты форма редиректит в SPA магазина («Liza Wall»); ловим их,
/// чтобы вместо показа магазина закрыть webview и вернуть пользователя в чат бота.
///
/// Матч по ТОЧНОМУ пути (https) И по ТОЧНОМУ хосту нашего магазина: иначе сторонний
/// сайт с таким же путём (`https://evil.com/payment/success`, открытый url-кнопкой
/// бота) закрыл бы webview досрочно. Форма `mariconsult.payform.ru` и чужие домены
/// под условие НЕ подпадают.
/// Чистая функция — для стража (ledger:RL-payment-webview-return-close).
bool isPaymentReturnUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return false;
  if (!_paymentReturnPath.hasMatch(uri.path)) return false;
  return _paymentReturnHosts.contains(uri.host.toLowerCase());
}

final RegExp _paymentReturnPath = RegExp(r'^/payment/(success|return)/?$');

// domain-migration-legacy:flutter-payment-return-host
/// Хосты miniapp-store, куда уходят urlSuccess/urlReturn. Списком, а не суффиксом
/// зоны: под `*.apps.liza.laba.prodamus.tech` и `*.store.app.tech.liza.ru` живут
/// СТОРОННИЕ мини-аппы, и суффикс-матч дал бы им закрыть платёжный webview. Старый
/// хост держим, пока живут сборки ≤3758 и выставленные на нём счета — переезд
/// доменов, `docs/superpowers/specs/2026-09-15-domain-migration-owner-features-design.md`.
const Set<String> _paymentReturnHosts = {
  'store.liza.laba.prodamus.tech',
  'store.app.tech.liza.ru',
};

/// Только `https`-схема (не `http`, не `javascript:`, не кастом-схемы).
/// Вынесено чистой функцией для стража (ledger:RL-liza-welcome-greeting).
bool isSafeHttpsUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

class _ExternalLinkWebViewState extends State<ExternalLinkWebView> {
  double _progress = 0;
  // Единственный pop: цепочка редиректов на /payment/* может дёрнуть
  // shouldOverrideUrlLoading несколько раз до размонтирования — без флага второй
  // maybePop закрыл бы уже НЕ этот экран, а чат под ним (гонка).
  bool _closed = false;

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(widget.url)?.host ?? '';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        // Адресная строка: пользователь всегда видит хост, куда ведёт ссылка.
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                host,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        bottom: _progress > 0 && _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress, minHeight: 2),
              )
            : null,
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          allowFileAccess: false,
          allowFileAccessFromFileURLs: false,
          allowUniversalAccessFromFileURLs: false,
          geolocationEnabled: false,
          saveFormData: false,
          useShouldOverrideUrlLoading: true,
        ),
        shouldOverrideUrlLoading: (controller, action) async {
          final u = action.request.url?.toString();
          final scheme = action.request.url?.scheme.toLowerCase();
          // Возврат с платёжной формы: не грузим SPA магазина («Liza Wall») —
          // закрываем webview, пользователь оказывается обратно в чате бота
          // (там появится серверное подтверждение «Ваш заказ принят…»).
          if (widget.closeOnPaymentReturn && isPaymentReturnUrl(u)) {
            Logs().i('[ExternalLinkWebView] payment return — closing webview');
            if (mounted && !_closed) {
              _closed = true;
              Navigator.of(context).maybePop();
            }
            return NavigationActionPolicy.CANCEL;
          }
          // Пускаем ТОЛЬКО https (форма Яндекса и её редиректы — капча, passport,
          // CDN — все по https/HSTS). http не разрешаем: иначе замок в адресной
          // строке лгал бы над незашифрованной страницей (находка ревью N2).
          // Прочее (javascript:/intent:/mailto:) тоже блок.
          if (scheme == 'https') {
            return NavigationActionPolicy.ALLOW;
          }
          Logs().i('[ExternalLinkWebView] blocked scheme: $scheme ($u)');
          return NavigationActionPolicy.CANCEL;
        },
        onProgressChanged: (controller, progress) {
          if (mounted) setState(() => _progress = progress / 100);
        },
      ),
    );
  }
}
