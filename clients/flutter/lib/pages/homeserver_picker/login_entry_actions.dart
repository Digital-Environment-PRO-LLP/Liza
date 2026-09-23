import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/phone_country.dart';
import 'package:liza/utils/phone_country_resolver.dart';
import 'package:liza/utils/phone_input_formatter.dart';

/// Кнопки/поле ввода первого экрана.
///
/// Режим один для всех: «нет доступа» больше не показывается до OIDC —
/// человек сначала регистрируется в ProdamusID (это повышает конверсию), и
/// только вернувшись без аккаунта видит экран сироты (`AuthOutcomeView`).
class LoginEntryActions extends StatefulWidget {
  const LoginEntryActions({
    super.key,
    required this.isLoading,
    required this.onRegister,
    required this.onSignIn,
    this.onSubmitPhone,
    this.countryResolver,
    this.initialCountry,
    this.density = 1.0,
  });

  final bool isLoading;
  final VoidCallback onRegister;
  final VoidCallback onSignIn;

  /// Ввод телефона прямо на первом экране. Не null в prod/dev-клиентах —
  /// первый экран и экран телефона объединены, отдельной кнопки-старта нет.
  final ValueChanged<String>? onSubmitPhone;

  /// Уточнение страны по IP через auth-proxy. `null` — не уточнять вовсе
  /// (тесты и экраны без сети); боевой резолвер передаёт вызывающий, см.
  /// [HttpPhoneCountryResolver].
  final PhoneCountryResolver? countryResolver;

  /// Страна, подставляемая вместо определённой по локали, — только для тестов.
  final PhoneCountry? initialCountry;

  /// Коэффициент вертикальной плотности (1.0 — просторно, меньше — тесно).
  /// Задаёт его экран по высоте вьюпорта, см. `HomeserverPickerView`.
  final double density;

  @override
  State<LoginEntryActions> createState() => _LoginEntryActionsState();
}

class _LoginEntryActionsState extends State<LoginEntryActions> {
  final TextEditingController _phone = TextEditingController();

  /// Живая маска: раскладывает цифры по формату страны прямо при вводе.
  final PhoneInputFormatter _mask = PhoneInputFormatter();

  /// Человек уже правил поле — автоподстановка префикса больше не вмешивается,
  /// иначе асинхронный ответ по IP затирал бы набранный код страны.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    if (widget.onSubmitPhone == null) return;
    _applyCountry(widget.initialCountry ?? phoneCountryFromLocale());
    _refineByIp();
  }

  String _placeholder = kDefaultPhoneCountry.example;

  /// Подставляет код страны и ставит курсор за ним — набирать человек
  /// продолжает с национальной части.
  void _applyCountry(PhoneCountry country) {
    final prefix = '${country.prefix} ';
    _mask.country = country;
    _phone.value = TextEditingValue(
      text: prefix,
      selection: TextSelection.collapsed(offset: prefix.length),
    );
    _placeholder = country.example;
  }

  Future<void> _refineByIp() async {
    final resolver = widget.countryResolver;
    if (resolver == null) return;
    final country = await resolver.resolveByIp();
    if (!mounted || country == null || _touched) return;
    setState(() => _applyCountry(country));
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String? get _e164 => normalizeToE164(_phone.text);

  /// Кнопка включается по ДЛИНЕ набранного, а не по полной валидности:
  /// серая кнопка не объясняет, что не так с номером. Отказ показывается
  /// текстом при нажатии — см. [_submit].
  bool get _isComplete => _phone.text.replaceAll(RegExp(r'\D'), '').length >= 8;

  /// Отказ по введённому номеру. `null` — поля ошибки нет вовсе (место под
  /// неё не резервируется, иначе блок стал бы выше в обычном состоянии).
  String? _phoneError;

  void _submit() {
    final onSubmitPhone = widget.onSubmitPhone;
    if (onSubmitPhone == null || widget.isLoading) return;
    final phone = _e164;
    if (phone == null) {
      // Номер не разобран — тот же отказ, что вернул бы сервер, но сразу и
      // на этом же экране. Раньше человек уезжал на экран ожидания кода и
      // читал «Введите корректный номер телефона» уже там (LABA-2531).
      setState(() => _phoneError = L10n.of(context).demoAuthInvalidPhone);
      return;
    }
    onSubmitPhone(phone);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final onSubmitPhone = widget.onSubmitPhone;

    if (onSubmitPhone != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.demoAuthPhoneFieldTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8 * widget.density),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              // Плюс, цифры и разделители. Лимит длины считается в ЦИФРАХ
              // внутри маски: прежний лимит в 24 символа считал и пробелы с
              // дефисами, и в поле влезал номер, который никогда не уйдёт
              // (LABA-2524).
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\-\s]')),
              // Маска — последней: она пересобирает уже отфильтрованное
              // значение целиком (см. PhoneInputFormatter).
              _mask,
            ],
            style: theme.textTheme.titleMedium,
            decoration: InputDecoration(
              // Подсказка формата, пока поле пустое; дальше человек видит
              // ту же раскладку уже на своих цифрах.
              hintText: _placeholder,
              // Заметно бледнее введённого текста: раньше плейсхолдер читался
              // как уже набранный номер. Берём цвет темы, а не хардкод —
              // иначе в тёмной теме подсказка исчезала бы совсем.
              hintStyle: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.38,
                ),
              ),
              filled: true,
              fillColor: theme.colorScheme.surface,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18 * widget.density,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.4),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
            onChanged: (value) => setState(() {
              _touched = true;
              // Человек правит номер — прежний отказ больше не про него.
              _phoneError = null;
              // Человек стёр подставленный код и вписал свой — маска обязана
              // перестроиться под новую страну, иначе немецкий номер
              // раскладывался бы по российскому формату.
              final typed = phoneCountryByDialPrefix(value);
              if (typed != null) {
                _mask.country = typed;
                _placeholder = typed.example;
              }
            }),
            onSubmitted: (_) => _submit(),
          ),
          SizedBox(height: 8 * widget.density),
          // Ошибка рисуется УСЛОВНО, без зарезервированного места: пустой
          // слот поднял бы высоту блока в обычном состоянии (её стережёт
          // login_entry_layout_test). Обычный Text, а не errorText поля —
          // так ошибки подаются во всём этом флоу (DemoAuthScaffold).
          if (_phoneError != null) ...[
            Text(
              _phoneError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            SizedBox(height: 8 * widget.density),
          ],
          Text(
            l10n.demoAuthPhoneCaption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 20 * widget.density),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              padding: EdgeInsets.symmetric(vertical: 18 * widget.density),
              shape: const StadiumBorder(),
              textStyle: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: widget.isLoading || !_isComplete ? null : _submit,
            child: widget.isLoading
                ? const LinearProgressIndicator()
                : Text(l10n.demoAuthContinue),
          ),
          SizedBox(height: 28 * widget.density),
          const _LegalNotice(),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          onPressed: widget.isLoading ? null : widget.onRegister,
          child: widget.isLoading
              ? const LinearProgressIndicator()
              : Text(l10n.register),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: widget.isLoading ? null : widget.onSignIn,
          child: Text(
            l10n.signInExistingAccount,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Юридическая сноска под кнопкой: согласие с условиями и политикой.
///
/// Ссылки ведут на разные документы (`AppConfig.termsUrl` / `privacyUrl`).
class _LegalNotice extends StatelessWidget {
  const _LegalNotice();

  /// Метки-подстановки: по ним фраза режется на части, чтобы порядок слов
  /// задавал перевод, а не код — в разных языках ссылки стоят по-разному.
  static const _termsMark = '\u0001';
  static const _privacyMark = '\u0002';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    final base = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final link = base?.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.onSurfaceVariant,
    );

    final template = l10n.demoAuthLegalNotice(_termsMark, _privacyMark);
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isEmpty) return;
      spans.add(TextSpan(text: buffer.toString(), style: base));
      buffer.clear();
    }

    for (final rune in template.runes) {
      final char = String.fromCharCode(rune);
      if (char == _termsMark) {
        flush();
        spans.add(
          TextSpan(
            text: l10n.demoAuthTermsLink,
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => launchUrl(AppConfig.termsUrl),
          ),
        );
      } else if (char == _privacyMark) {
        flush();
        spans.add(
          TextSpan(
            text: l10n.demoAuthPrivacyLink,
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => launchUrl(AppConfig.privacyUrl),
          ),
        );
      } else {
        buffer.write(char);
      }
    }
    flush();

    return Text.rich(TextSpan(children: spans), textAlign: TextAlign.center);
  }
}
