import XCTest

/// Живой прогон AC-14/AC-15 RL-ios-uiscene-lifecycle против установленной Liza
/// (запуск — `run.sh`). Жалоба 2026-09-22: сборки 3764/3765 падали при каждом
/// сворачивании. Детектор — PID процесса (пишет хост-поллер `run.sh`), а не
/// `XCUIApplication.state` и не `.ips`: state после краша ещё секунды отдаёт
/// runningForeground, а одинаковые краш-отчёты iOS подряд не пишет.
final class LizaLifecycleTests: XCTestCase {
  let liza = XCUIApplication(bundleIdentifier: "ru.prodamus.liza")
  let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

  override func setUp() { continueAfterFailure = false }

  private func log(_ s: String) { print("LIZA-AC: \(s)") }

  /// PID живого процесса Liza (launchd), 0 — процесса нет. `XCUIApplication.state`
  /// здесь не годится: после краша он ещё секунды отдаёт runningForeground.
  private func pid() -> Int {
    // Хост-скрипт каждые 0.5 с пишет pid в файл внутри контейнера хоста теста.
    let url = URL(fileURLWithPath: "/tmp/liza-lifecycle-pid")
    let s = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
  }

  private var basePid = 0

  private func assertAlive(_ step: String) {
    let p = pid()
    log("\(step): pid=\(p) (ожидали \(basePid))")
    XCTAssertEqual(p, basePid, "\(step): процесс сменился/умер — краш")
  }

  private func foreground(_ step: String) {
    liza.activate()
    XCTAssertTrue(liza.wait(for: .runningForeground, timeout: 20), "\(step): не вышло на передний план")
    sleep(4)
    if basePid == 0 { basePid = pid(); log("\(step): basePid=\(basePid)") }
  }

  private func openURLCold(_ url: String) {
    liza.terminate()
    XCTAssertTrue(liza.wait(for: .notRunning, timeout: 10))
    XCUIDevice.shared.system.open(URL(string: url)!)
    let open = springboard.buttons["Открыть"]
    if open.waitForExistence(timeout: 8) { open.tap(); log("tap Открыть") }
    XCTAssertTrue(liza.wait(for: .runningForeground, timeout: 30), "\(url): не запустилось")
    sleep(3)
    basePid = pid(); log("cold \(url): basePid=\(basePid)")
    sleep(10)
    assertAlive("cold \(url) после запуска")
        XCUIDevice.shared.press(.home)
    sleep(20)
    assertAlive("cold \(url) → Home")
  }

  func test1_HomeThreeTimes() {
    liza.terminate()
    foreground("старт")
    sleep(15)
    basePid = pid(); log("старт: basePid=\(basePid)")
    for i in 1...3 {
      XCUIDevice.shared.press(.home)
      sleep(20)
      assertAlive("Home #\(i)")
      foreground("возврат #\(i)")
    }
  }

  func test2_LockScreen() {
    foreground("старт")
    basePid = pid(); log("lock старт: basePid=\(basePid)")
    XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
    sleep(20)
    assertAlive("Lock")
    XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
    sleep(2)
    XCUIDevice.shared.press(.home)
    sleep(20)
    foreground("после разблокировки")
    assertAlive("Unlock")
  }

  func test3_ColdStartLizaURL() { openURLCold("liza://test") }

  func test4_ColdStartShareMediaURL() { openURLCold("ShareMedia-ru.prodamus.liza://dataUrl=ShareKey#text") }

  func test5_ColdStartShareFromPhotos() {
    liza.terminate()
    XCTAssertTrue(liza.wait(for: .notRunning, timeout: 10))
    let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
    photos.launch()
    sleep(4)
    // Первый запуск Фото на iOS 27 — экран «что нового» с «Продолжить».
    for _ in 0..<3 where photos.buttons["Продолжить"].exists { photos.buttons["Продолжить"].tap(); sleep(2) }
    // Фото восстанавливает прошлый экран (открытый снимок) — возвращаемся в медиатеку.
    for _ in 0..<3 where !photos.images.matching(identifier: "PXGGridLayout-Info").firstMatch.exists {
      if photos.buttons["Назад"].exists { photos.buttons["Назад"].tap() } else if photos.buttons["Медиатека"].exists { photos.buttons["Медиатека"].tap() }
      sleep(2)
    }
    // Первое фото в медиатеке.
    let cell = photos.images.matching(identifier: "PXGGridLayout-Info").firstMatch
    XCTAssertTrue(cell.waitForExistence(timeout: 15), "нет фото в медиатеке")
    for _ in 0..<4 {
      cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      sleep(3)
      if photos.buttons["Поделиться"].exists || photos.buttons["Share"].exists { break }
    }
    if !(photos.buttons["Поделиться"].exists || photos.buttons["Share"].exists) {
      // iOS 27: касание ячейки сетки не открывает снимок — режим выбора.
      photos.buttons["Выбрать"].tap(); sleep(2)
      cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); sleep(2)
      log("select mode: \(photos.buttons.allElementsBoundByIndex.map { $0.label })")
    }
    let share = photos.buttons["Поделиться"].exists ? photos.buttons["Поделиться"] : photos.buttons["Share"]
    XCTAssertTrue(share.waitForExistence(timeout: 10), "нет кнопки Поделиться")
    share.tap()
    sleep(3)
    // Иконка расширения в ряду приложений share-листа.
    var target = photos.cells["Liza"]
    if !target.exists { target = photos.buttons["Liza"] }
    if !target.exists {
      // Ряд прокручивается — ищем свайпом.
      for _ in 0..<4 where !target.exists {
        photos.collectionViews.firstMatch.swipeLeft(); sleep(1)
        target = photos.cells["Liza"].exists ? photos.cells["Liza"] : photos.buttons["Liza"]
      }
    }
    XCTAssertTrue(target.exists, "Liza нет в share-листе")
    target.tap()
    // Окно расширения Liza Share: «Опубликовать» → расширение открывает основное
    // приложение ShareMedia-URL'ом. Кнопка живёт в удалённом view — ищем и в Фото, и в SpringBoard.
    var post = photos.buttons["Опубликовать"]
    if !post.waitForExistence(timeout: 10) { post = springboard.buttons["Опубликовать"] }
    XCTAssertTrue(post.waitForExistence(timeout: 5), "нет кнопки Опубликовать в Liza Share")
    post.tap(); log("tap Опубликовать")
    let open = springboard.buttons["Открыть"]
    if open.waitForExistence(timeout: 6) { open.tap(); log("tap Открыть") }
    XCTAssertTrue(liza.wait(for: .runningForeground, timeout: 40), "Share: Liza не открылась")
    sleep(3)
    basePid = pid(); log("share: basePid=\(basePid)")
    sleep(10)
    assertAlive("Share → Liza после запуска")
    XCUIDevice.shared.press(.home)
    sleep(20)
    assertAlive("Share → Liza → Home")
  }
}
