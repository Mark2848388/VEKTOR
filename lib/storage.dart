import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class VektorStore {
  /// Your Cloudflare Worker (from Vektor config.js)
  static const defaultCloud = 'https://throbbing-grass-315c.claudebote8.workers.dev';

  String cloudBase = defaultCloud;
  String model = 'openai/gpt-oss-120b';
  String modeId = 'fast';
  bool ttsEnabled = true;
  List<ChatMessage> messages = [];
  List<String> memory = [];

  VektorMode get mode => modes.firstWhere((m) => m.id == modeId, orElse: () => modes.first);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    cloudBase = p.getString('cloud') ?? defaultCloud;
    model = p.getString('model') ?? model;
    modeId = p.getString('mode') ?? 'fast';
    ttsEnabled = p.getBool('tts') ?? true;
    memory = p.getStringList('memory') ?? [];
    final raw = p.getString('messages');
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        messages = list.map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      } catch (_) {}
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('cloud', cloudBase);
    await p.setString('model', model);
    await p.setString('mode', modeId);
    await p.setBool('tts', ttsEnabled);
    await p.setStringList('memory', memory);
    await p.setString('messages', jsonEncode(messages.map((m) => m.toJson()).toList()));
  }

  void addMemory(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    memory.insert(0, t);
    if (memory.length > 100) memory = memory.sublist(0, 100);
  }

  List<String> searchMemory(String q, {int k = 4}) {
    final query = q.toLowerCase();
    if (query.isEmpty) return memory.take(k).toList();
    final scored = <(String, int)>[];
    for (final t in memory) {
      final low = t.toLowerCase();
      var s = 0;
      for (final w in query.split(RegExp(r'\s+'))) {
        if (w.length > 2 && low.contains(w)) s++;
      }
      if (s > 0) scored.add((t, s));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    if (scored.isEmpty) return memory.take(k).toList();
    return scored.take(k).map((e) => e.$1).toList();
  }
}
