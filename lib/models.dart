class ChatMessage {
  final String id;
  final String role; // user | assistant | system
  final String text;
  final DateTime at;
  final String? mode;
  final int? ms;
  final String? error;

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    DateTime? at,
    this.mode,
    this.ms,
    this.error,
  }) : at = at ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'text': text,
        'at': at.toIso8601String(),
        'mode': mode,
        'ms': ms,
        'error': error,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        role: j['role'] as String,
        text: j['text'] as String,
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        mode: j['mode'] as String?,
        ms: j['ms'] as int?,
        error: j['error'] as String?,
      );
}

class VektorMode {
  final String id;
  final String title;
  final String system;
  final double temperature;
  final int maxTokens;
  const VektorMode({
    required this.id,
    required this.title,
    required this.system,
    required this.temperature,
    required this.maxTokens,
  });
}

const modes = <VektorMode>[
  VektorMode(id: 'fast', title: 'Быстрый', system: 'Отвечай кратко и по делу.', temperature: 0.6, maxTokens: 700),
  VektorMode(id: 'think', title: 'Думающий', system: 'Рассуждай по шагам, затем дай чёткий итог.', temperature: 0.4, maxTokens: 2500),
  VektorMode(id: 'study', title: 'Учёба', system: 'Ты — терпеливый репетитор. Объясняй по шагам простым языком с примерами, затем задай 1–2 проверочных вопроса.', temperature: 0.4, maxTokens: 3000),
  VektorMode(id: 'deep', title: 'Глубокий', system: 'Сделай подробный разбор: допущения, варианты, риски, вывод.', temperature: 0.3, maxTokens: 6000),
  VektorMode(id: 'code', title: 'VKTR Code', system: 'Ты старший инженер: план, код, самопроверка. Пиши чистый код.', temperature: 0.2, maxTokens: 6000),
  VektorMode(id: 'voice', title: 'Разговорный', system: 'Отвечай как в живой беседе, 1–3 коротких предложения, без markdown.', temperature: 0.5, maxTokens: 500),
];
