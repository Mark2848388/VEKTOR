import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'storage.dart';
import 'tools.dart';

class ChatResult {
  final String text;
  final int ms;
  final String? error;
  ChatResult({required this.text, required this.ms, this.error});
}

class VektorApi {
  final VektorStore store;
  final VektorTools tools = VektorTools();
  VektorApi(this.store);

  Future<ChatResult> chat(String userText, {required List<ChatMessage> history}) async {
    final sw = Stopwatch()..start();

    // memory
    final remember = RegExp(r'^\s*(запомни|remember)[:,]?\s+([\s\S]+)', caseSensitive: false).firstMatch(userText);
    if (remember != null) {
      store.addMemory(remember.group(2)!.trim());
      await store.save();
      sw.stop();
      return ChatResult(text: 'Запомнил.', ms: sw.elapsedMilliseconds);
    }

    // local tools: files / apps / zip
    try {
      final toolOut = await tools.handleCommand(userText);
      if (toolOut.isNotEmpty) {
        sw.stop();
        return ChatResult(text: toolOut, ms: sw.elapsedMilliseconds);
      }
    } catch (e) {
      sw.stop();
      return ChatResult(text: 'Инструмент: $e', ms: sw.elapsedMilliseconds, error: '$e');
    }

    // calc
    final calc = RegExp(r'^\s*(calc|посчитай)\s+(.+)$', caseSensitive: false).firstMatch(userText);
    if (calc != null) {
      try {
        final v = _eval(calc.group(2)!.replaceAll(' ', ''));
        sw.stop();
        return ChatResult(text: '${calc.group(2)} = $v', ms: sw.elapsedMilliseconds);
      } catch (e) {
        sw.stop();
        return ChatResult(text: 'Не посчитал: $e', ms: sw.elapsedMilliseconds, error: '$e');
      }
    }

    if (RegExp(r'^\s*(время|time)\s*$', caseSensitive: false).hasMatch(userText)) {
      sw.stop();
      return ChatResult(text: DateTime.now().toString(), ms: sw.elapsedMilliseconds);
    }

    final mode = store.mode;
    var base = store.cloudBase.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      sw.stop();
      return ChatResult(text: 'Worker URL пуст. Настройки → Cloudflare.', ms: sw.elapsedMilliseconds, error: 'no cloud');
    }

    final mem = store.searchMemory(userText);
    final sys = 'Ты — Вектор, личный ИИ-ассистент на телефоне пользователя. Отвечай по-русски, если не просят иначе. '
        'Можешь подсказывать команды: «открой youtube», «файлы», «zip», «сохрани файл name: текст», «запомни …». '
        '${mode.system}'
        '${mem.isEmpty ? '' : '\nИз памяти:\n${mem.map((e) => '- $e').join('\n')}'}';

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': sys},
      ...history.where((m) => m.role == 'user' || m.role == 'assistant').take(16).map((m) => {'role': m.role, 'content': m.text}),
      {'role': 'user', 'content': userText},
    ];

    final body = jsonEncode({
      'model': store.model,
      'temperature': mode.temperature,
      'max_tokens': mode.maxTokens,
      'messages': messages,
    });

    Future<http.Response> post(String u) => http
        .post(
          Uri.parse(u),
          headers: {'content-type': 'application/json', 'authorization': 'Bearer vektor'},
          body: body,
        )
        .timeout(const Duration(seconds: 90));

    // Prefer OpenAI-compatible path used by Vektor workers
    final candidates = <String>[
      if (base.endsWith('/v1')) '$base/chat/completions' else '$base/v1/chat/completions',
      '$base/chat/completions',
      base,
    ];

    try {
      http.Response? res;
      Object? lastErr;
      for (final u in candidates) {
        try {
          res = await post(u);
          if (res.statusCode != 404) break;
        } catch (e) {
          lastErr = e;
        }
      }
      sw.stop();
      if (res == null) {
        return ChatResult(text: 'Сеть: $lastErr', ms: sw.elapsedMilliseconds, error: '$lastErr');
      }
      if (res.statusCode >= 400) {
        final b = res.body.length > 240 ? res.body.substring(0, 240) : res.body;
        return ChatResult(text: 'Ошибка ${res.statusCode}: $b', ms: sw.elapsedMilliseconds, error: 'http ${res.statusCode}');
      }
      final data = jsonDecode(res.body);
      String text = '';
      if (data is Map && data['choices'] is List && (data['choices'] as List).isNotEmpty) {
        final c0 = (data['choices'] as List).first;
        text = c0['message']?['content']?.toString() ?? c0['text']?.toString() ?? '';
      } else if (data is Map && data['reply'] != null) {
        text = data['reply'].toString();
      } else {
        text = res.body;
      }
      if (text.trim().isEmpty) text = '(пустой ответ)';
      return ChatResult(text: text.trim(), ms: sw.elapsedMilliseconds);
    } on TimeoutException {
      sw.stop();
      return ChatResult(text: 'Таймаут Worker. Проверь интернет.', ms: sw.elapsedMilliseconds, error: 'timeout');
    } catch (e) {
      sw.stop();
      return ChatResult(text: 'Сеть: $e', ms: sw.elapsedMilliseconds, error: '$e');
    }
  }

  num _eval(String s) {
    if (!RegExp(r'^[\d+\-*/().]+$').hasMatch(s)) throw Exception('только 0-9 + - * / ( )');
    final nums = <double>[];
    final ops = <String>[];
    int prec(String o) => (o == '+' || o == '-') ? 1 : 2;
    void apply() {
      final b = nums.removeLast();
      final a = nums.removeLast();
      final o = ops.removeLast();
      if (o == '+') nums.add(a + b);
      if (o == '-') nums.add(a - b);
      if (o == '*') nums.add(a * b);
      if (o == '/') nums.add(a / b);
    }

    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (ch == '(') {
        ops.add(ch);
        i++;
      } else if (ch == ')') {
        while (ops.isNotEmpty && ops.last != '(') {
          apply();
        }
        ops.removeLast();
        i++;
      } else if ('+-*/'.contains(ch)) {
        while (ops.isNotEmpty && ops.last != '(' && prec(ops.last) >= prec(ch)) {
          apply();
        }
        ops.add(ch);
        i++;
      } else {
        final st = i;
        while (i < s.length && RegExp(r'[\d.]').hasMatch(s[i])) {
          i++;
        }
        nums.add(double.parse(s.substring(st, i)));
      }
    }
    while (ops.isNotEmpty) {
      apply();
    }
    return nums.single;
  }
}
