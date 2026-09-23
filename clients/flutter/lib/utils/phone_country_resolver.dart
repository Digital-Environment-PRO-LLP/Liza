import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:liza/config/app_config.dart';
import 'package:liza/utils/phone_country.dart';

/// Уточнение страны по IP — точка расширения.
///
/// Локаль устройства даёт язык интерфейса, а не место нахождения: человек с
/// английской системой в Ереване получит `+1`. Уточнить это может только
/// сервер, который видит IP запроса.
///
/// Боевая реализация — [HttpPhoneCountryResolver] поверх ручки auth-proxy;
/// [NoopPhoneCountryResolver] оставлен для тестов и экранов, где сеть дёргать
/// незачем.
abstract class PhoneCountryResolver {
  /// `null` — уточнить не удалось, оставить страну из локали.
  Future<PhoneCountry?> resolveByIp();
}

class NoopPhoneCountryResolver implements PhoneCountryResolver {
  const NoopPhoneCountryResolver();

  @override
  Future<PhoneCountry?> resolveByIp() async => null;
}

/// Спрашивает страну у auth-proxy: `GET /api/geo/country` → `{"country": "AM"}`.
///
/// Страну определяет сервер по IP запроса (левый элемент `X-Forwarded-For`,
/// база DB-IP Country Lite смонтирована в контейнер) — клиент своего IP не
/// знает и в сторонние geoip-сервисы не ходит.
///
/// Уточнение НЕОБЯЗАТЕЛЬНОЕ: любой неуспех (таймаут, офлайн, 429, битый JSON,
/// `{"country": null}`, страна вне справочника из [kPhoneCountries]) — это
/// `null`, и поле остаётся с префиксом по локали. Экран входа не должен ни
/// ждать сеть, ни ломаться из-за неё, поэтому таймаут короткий.
class HttpPhoneCountryResolver implements PhoneCountryResolver {
  HttpPhoneCountryResolver({String? baseUrl, http.Client? httpClient})
      : baseUrl = baseUrl ?? AppConfig.authProxyBaseUrl,
        _httpClient = httpClient ?? http.Client();

  /// ХОСТ auth-proxy без схемы (`AppConfig.authProxyBaseUrl` — именно хост,
  /// а не URL). URL собираем через [Uri.https], как остальные сервисы
  /// проекта: `Uri.parse` от голого хоста дал бы ОТНОСИТЕЛЬНЫЙ адрес, и на
  /// вебе запрос ушёл бы на origin страницы (dev.web.liza.ru) вместо
  /// auth-proxy — фича молча не работала бы.
  final String baseUrl;

  final http.Client _httpClient;

  /// Экран входа рисуется сразу и живёт с префиксом по локали; уточнение
  /// приходит позже и только если человек ещё не тронул поле. Ждать дольше
  /// пары секунд бессмысленно — к тому моменту номер уже набирают.
  static const _timeout = Duration(seconds: 3);

  @override
  Future<PhoneCountry?> resolveByIp() async {
    try {
      final response = await _httpClient
          .get(Uri.https(baseUrl, '/api/geo/country'))
          .timeout(_timeout);
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map) return null;

      final iso = body['country'];
      if (iso is! String) return null;

      // Страны вне короткого справочника (он влияет только на
      // автоподстановку префикса) — не повод падать: оставляем локаль.
      return phoneCountryByIso(iso);
    } catch (_) {
      // Сознательно глотаем всё: сеть, таймаут, разбор JSON. Уточнение
      // необязательное, а альтернатива — сломанный экран входа.
      return null;
    }
  }
}
