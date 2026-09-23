import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:matrix/matrix.dart';
import 'package:http/http.dart' as http;

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/external_link_web_view.dart'
    show isPaymentReturnUrl;

/// Лёгкий платёжный WebView для оплаты из карточки бота (`com.liza.invoice`).
///
/// В отличие от [MiniAppWebViewContent] (mini App: bridge, initData, MainButton,
/// deep-link Tilda) — грузит ТОЛЬКО готовый `payment_url` формы Prodamus и
/// остаётся на платёжных хостах (`isProdamusPaymentHost`) + банковских 3DS. Не
/// несёт мост к Matrix-токену и не касается пути miniApp-оплаты
/// (`_handleOpenInvoice`, third_party routing) — отдельный, минимально рискованный
/// контур.
///
/// Статус оплаты опрашивается на СЕРВЕРЕ по `invoice_ref` (GET
/// `/bot-invoice-status?ref=...`, Bearer client-token) — членство в комнате
/// форсится сервером именно через `ref`. По `paid`/`failed`/таймауту WebView
/// закрывается, вызывающему возвращается статус.
class BotPaymentWebView extends StatefulWidget {
  final String paymentUrl;
  final String invoiceRef;

  /// База Liza Bot API для homeserver комнаты (per-homeserver!).
  final String lizaBotApiBase;

  /// Client-token Matrix (Bearer) для авторизации статус-запросов.
  final String accessToken;

  const BotPaymentWebView({
    required this.paymentUrl,
    required this.invoiceRef,
    required this.lizaBotApiBase,
    required this.accessToken,
    super.key,
  });

  /// Открывает платёжный WebView и ждёт результата.
  ///
  /// Возвращает финальный статус (`paid`/`failed`/`cancelled`) или `null`, если
  /// пользователь закрыл экран до разрешения оплаты.
  static Future<String?> open({
    required BuildContext context,
    required String paymentUrl,
    required String invoiceRef,
    required String lizaBotApiBase,
    required String accessToken,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => BotPaymentWebView(
          paymentUrl: paymentUrl,
          invoiceRef: invoiceRef,
          lizaBotApiBase: lizaBotApiBase,
          accessToken: accessToken,
        ),
      ),
    );
  }

  @override
  State<BotPaymentWebView> createState() => _BotPaymentWebViewState();
}

class _BotPaymentWebViewState extends State<BotPaymentWebView> {
  bool _isLoading = true;
  bool _polling = true;
  // Гарантирует ЕДИНСТВЕННЫЙ pop: _finish зовётся и из поллинга, и из крестика —
  // без флага гонка дала бы двойной Navigator.pop (закрытие чужого экрана).
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _pollStatus();
  }

  @override
  void dispose() {
    _polling = false;
    super.dispose();
  }

  /// Опрос статуса инвойса ТОЛЬКО по `ref` (сервер форсит проверку членства в
  /// комнате именно по ref; по invoice_id — не опрашиваем).
  Future<void> _pollStatus() async {
    final url = Uri.parse(widget.lizaBotApiBase).resolve(
      '/bot-invoice-status?ref=${Uri.encodeQueryComponent(widget.invoiceRef)}',
    );
    // 180 × 3с = 540с (9 мин) — синхронно с окном оплаты miniApp-пути.
    for (var i = 0; i < 180; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted || !_polling) return;
      try {
        final resp = await http.get(
          url,
          headers: {'Authorization': 'Bearer ${widget.accessToken}'},
        );
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final status = data['status'] as String?;
          if (status == 'paid') {
            _finish('paid');
            return;
          }
          if (status == 'failed') {
            _finish('failed');
            return;
          }
          // pending и прочее — продолжаем опрос.
        }
      } catch (e) {
        Logs().w('[BotPaymentWebView] polling status: $e');
      }
    }
    if (mounted && _polling) _finish('cancelled');
  }

  void _finish(String status) {
    if (!mounted || _finished) return;
    _finished = true;
    _polling = false;
    Navigator.of(context).pop(status);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(l10n.botInvoicePaymentTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          // Явный отказ пользователя от оплаты (не путать с таймаутом polling).
          onPressed: () => _finish('cancelled'),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.paymentUrl)),
              initialSettings: InAppWebViewSettings(
                allowFileAccess: false,
                allowFileAccessFromFileURLs: false,
                allowUniversalAccessFromFileURLs: false,
                geolocationEnabled: false,
                saveFormData: false,
                supportZoom: false,
                cacheEnabled: false,
                clearCache: true,
                useShouldOverrideUrlLoading: true,
              ),
              onLoadStop: (controller, url) {
                if (mounted && _isLoading) {
                  setState(() => _isLoading = false);
                }
              },
              onReceivedError: (controller, request, error) {
                if (request.isForMainFrame == true && mounted) {
                  setState(() => _isLoading = false);
                }
              },
              onPermissionRequest: (controller, request) async {
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.DENY,
                );
              },
              shouldOverrideUrlLoading: (controller, action) async {
                final url = action.request.url;
                if (url == null) return NavigationActionPolicy.CANCEL;
                if (url.scheme != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }
                // Возврат с формы Prodamus на наш urlSuccess/urlReturn: НЕ грузим
                // SPA магазина («Liza Wall») в платёжном окне — закрываем сразу и
                // возвращаем в чат. Иначе до следующего тика поллинга (≤3с) юзер
                // видит постороннюю ленту магазина (DEF-2). Подтверждение оплаты
                // придёт серверным сообщением (слой B/поллинг) независимо.
                if (isPaymentReturnUrl(url.toString())) {
                  _finish('paid');
                  return NavigationActionPolicy.CANCEL;
                }
                // Держим навигацию на платёжных хостах Prodamus + банковских 3DS
                // (любой https разрешён после старта оплаты, как в miniApp-пути:
                // 3DS-шлюзы банков живут на произвольных доменах).
                return NavigationActionPolicy.ALLOW;
              },
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: ColoredBox(
                color: colorScheme.surface,
                child: Center(
                  child: CircularProgressIndicator(color: colorScheme.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
