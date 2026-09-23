{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // CanvasKit с НАШЕГО домена, а не с www.gstatic.com (2026-08-27).
    // По умолчанию движок тянет canvaskit.wasm (~7 МБ несжатыми) со
    // стороннего домена: лишние DNS+TLS на критическом пути, и первый
    // экран заложник чужой доступности — в замере с холодным кешем
    // canvaskit.wasm с gstatic отдавался 162 с. Локальные копии уже
    // лежат в build/web/canvaskit (кладёт flutter build web).
    canvasKitBaseUrl: "canvaskit/",
  },
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      // useColorEmoji НЕ включаем: флаг заставляет CanvasKit подгружать
      // NotoColorEmoji с fonts.gstatic.com — снова сторонний домен на
      // старте. Эмодзи рисует системный шрифт платформы (решение
      // 2026-08-01, см. RL-web-font-locale).
    });
    await appRunner.runApp();
  }
});
