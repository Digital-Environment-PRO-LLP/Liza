import 'package:alchemist/alchemist.dart';

import 'package:liza/widgets/mini_app_composer_button.dart';
import 'package:liza/widgets/mini_app_open_pill.dart';

// Страж реестра регрессии: ledger:RL-bot-miniapp-registry (см. tests/registry/).
// Golden Яруса 0 на кнопки быстрого доступа к mini App бота: пилюля «Открыть»
// (строка чата, chat_list_item) и кнопка «Открыть» (композер, chat_input_row).
//
// Рендерим РЕАЛЬНЫЕ виджеты [MiniAppOpenPill]/[MiniAppComposerButton] (те же,
// что в проде), а не их копии — правка стиля/иконки/размера/цвета в проде
// детерминированно роняет этот тест. Текст приходит параметром (label), поэтому
// виджеты чистые и golden-тестируются без Matrix Client и без localizations
// (реактивность/реестр/L10n держат вызывающие). Заменяет заблокированный ручной
// Ярус B (реальную сборку сейчас не запустить — 2 инстанса делят sqlite).
void main() {
  goldenTest(
    'кнопки mini App бота: пилюля «Открыть» + кнопка «Открыть»',
    fileName: 'bot_miniapp_buttons',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        GoldenTestScenario(
          name: 'pill Открыть (список чатов)',
          child: MiniAppOpenPill(label: 'Открыть', onTap: () {}),
        ),
        GoldenTestScenario(
          name: 'composer Открыть',
          child: MiniAppComposerButton(
            height: 48,
            label: 'Открыть',
            onTap: () {},
          ),
        ),
      ],
    ),
  );
}
