import 'package:flutter/material.dart';

import 'package:liza/pages/auth_select/auth_select_view.dart';
import 'package:liza/utils/auth_proxy_login_helper.dart';
import 'package:liza/utils/auth_proxy_service.dart';
import 'package:liza/utils/localized_exception_extension.dart';
import 'package:liza/utils/pending_invite_code.dart';
import 'package:liza/widgets/liza_app.dart';
import 'package:liza/widgets/matrix.dart';

/// Data passed via GoRouter extra to the select page.
class AuthSelectExtra {
  final String sessionState;
  final AuthProxyService authProxyService;

  const AuthSelectExtra({
    required this.sessionState,
    required this.authProxyService,
  });
}

class AuthSelectPage extends StatefulWidget {
  final AuthSelectExtra extra;
  const AuthSelectPage({required this.extra, super.key});

  @override
  AuthSelectController createState() => AuthSelectController();
}

class AuthSelectController extends State<AuthSelectPage> {
  AuthSelectListResponse? selectData;
  String? error;
  bool isLoading = true;
  bool isSelecting = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      final data = await widget.extra.authProxyService.getAccounts(
        sessionState: widget.extra.sessionState,
      );

      // Само-регистрация задепрекейчена → если аккаунт один, сразу логинимся.
      if (data.accounts.length == 1) {
        await selectAccount(data.accounts.first.serverName);
        return;
      }

      if (mounted) {
        setState(() {
          selectData = data;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toLocalizedString(context);
          isLoading = false;
        });
      }
    }
  }

  Future<void> selectAccount(String serverName) async {
    setState(() {
      isSelecting = true;
      error = null;
    });
    try {
      final tokenResponse =
          await widget.extra.authProxyService.selectAccount(
        sessionState: widget.extra.sessionState,
        serverName: serverName,
      );

      final matrixState = Matrix.of(context);
      final client = await matrixState.getLoginClient();
      await completeAuthProxyLogin(
        client: client,
        tokenResponse: tokenResponse,
        sessionState: widget.extra.sessionState,
        authProxyService: widget.extra.authProxyService,
      );
      // Backend может вернуть inviteCode в /api/auth/select — подхватим, если
      // фронт ещё не успел установить его сам (например, юзер открыл приложение
      // напрямую по deep-link до того, как HomeserverPicker маунтнулся).
      if (tokenResponse.inviteCode != null &&
          PendingInviteCode.current == null) {
        PendingInviteCode.set(tokenResponse.inviteCode);
      }
      // Если был invite — redeem навигирует сам в нужную комнату через
      // глобальный LizaApp.router; mounted-проверка не нужна (страница может
      // анмаунтнуться после client.login из-за onLoginStateChanged).
      final redeemed = await redeemPendingInviteAfterLogin();
      if (redeemed) return;
      // onLoginStateChanged stream может стрельнуть до того, как
      // _registerSubs зарегистрирует listener — навигируем явно.
      final isDeveloper = matrixState.isCurrentUserDeveloper;
      final router = LizaApp.router;
      // Ждём кадр между pop: go_router применяет pop к конфигурации только на
      // следующем кадре, и второй pop по тому же маршруту роняет «Future
      // already completed» (тот же класс, что в MatrixState.handleLoginStateChange).
      // 8 — защитный потолок: обычно хватает 1–2 pop; без кадров (фон) каждый
      // шаг ограничен 500 мс, поэтому хуже ~4 с, а не вечного ожидания.
      for (var i = 0; i < 8 && router.canPop(); i++) {
        router.pop();
        await WidgetsBinding.instance.endOfFrame.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {},
        );
      }
      router.go(isDeveloper ? '/backup' : '/rooms');
    } on AuthProxyException catch (e) {
      setState(() {
        error = e.serverError ?? e.message;
      });
    } catch (e) {
      setState(() {
        error = e.toLocalizedString(context);
      });
    } finally {
      if (mounted) {
        setState(() => isSelecting = false);
      }
    }
  }

  void retry() => _loadAccounts();

  @override
  Widget build(BuildContext context) => AuthSelectView(this);
}
