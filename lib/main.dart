import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'api.dart';
import 'models.dart';
import 'storage.dart';
import 'theme.dart';
import 'tools.dart';
import 'voice.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  final store = VektorStore();
  await store.load();
  final voice = VektorVoice();
  await voice.init();
  runApp(VektorApp(store: store, voice: voice));
}

class VektorApp extends StatelessWidget {
  final VektorStore store;
  final VektorVoice voice;
  const VektorApp({super.key, required this.store, required this.voice});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vektor',
      debugShowCheckedModeBanner: false,
      theme: vektorTheme(),
      home: ChatPage(store: store, voice: voice),
    );
  }
}

class ChatPage extends StatefulWidget {
  final VektorStore store;
  final VektorVoice voice;
  const ChatPage({super.key, required this.store, required this.voice});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  late final VektorApi _api;
  bool _busy = false;
  bool _listening = false;
  final _uuid = const Uuid();

  VektorStore get store => widget.store;
  VektorVoice get voice => widget.voice;

  @override
  void initState() {
    super.initState();
    _api = VektorApi(store);
  }

  Future<void> _send([String? forced]) async {
    final text = (forced ?? _ctrl.text).trim();
    if (text.isEmpty || _busy) return;
    if (forced == null) _ctrl.clear();
    final user = ChatMessage(id: _uuid.v4(), role: 'user', text: text);
    setState(() {
      store.messages.add(user);
      _busy = true;
    });
    _jump();
    await store.save();

    final hist = List<ChatMessage>.from(store.messages)..removeLast();
    final res = await _api.chat(text, history: hist);
    final bot = ChatMessage(
      id: _uuid.v4(),
      role: 'assistant',
      text: res.text,
      mode: store.modeId,
      ms: res.ms,
      error: res.error,
    );
    setState(() {
      store.messages.add(bot);
      _busy = false;
    });
    await store.save();
    _jump();
    if (store.ttsEnabled && res.error == null) {
      await voice.speak(res.text);
    }
  }

  Future<void> _mic() async {
    if (_listening) {
      await voice.stopListen();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    final text = await voice.listenOnce();
    setState(() => _listening = false);
    if (text != null && text.isNotEmpty) {
      _ctrl.text = text;
      await _send(text);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не расслышал. Повтори.')));
    }
  }

  void _jump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent + 100, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('VEKTOR', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 16)),
          Text('${store.mode.title} · CF Worker', style: const TextStyle(fontSize: 11, color: VK.muted)),
        ]),
        actions: [
          IconButton(
            tooltip: 'TTS on/off',
            onPressed: () async {
              setState(() => store.ttsEnabled = !store.ttsEnabled);
              await store.save();
              if (!store.ttsEnabled) await voice.stopSpeak();
            },
            icon: Icon(store.ttsEnabled ? Icons.volume_up : Icons.volume_off, color: store.ttsEnabled ? VK.ok : VK.muted),
          ),
          IconButton(tooltip: 'Режим', onPressed: _pickMode, icon: const Icon(Icons.bolt_outlined, color: VK.accent2)),
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: _Drawer(store: store, voice: voice, onChanged: () => setState(() {})),
      body: Column(children: [
        Expanded(
          child: store.messages.isEmpty
              ? const _Empty()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: store.messages.length + (_busy ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (_busy && i == store.messages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: VK.accent)),
                          SizedBox(width: 10),
                          Text('Вектор…', style: TextStyle(color: VK.muted, fontSize: 13)),
                        ]),
                      );
                    }
                    return _Bubble(msg: store.messages[i], onSpeak: () => voice.speak(store.messages[i].text));
                  },
                ),
        ),
        _Composer(
          controller: _ctrl,
          busy: _busy,
          listening: _listening,
          onSend: () => _send(),
          onMic: _mic,
        ),
      ]),
    );
  }

  Future<void> _pickMode() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: VK.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Режим', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          ...modes.map((m) => ListTile(
                title: Text(m.title),
                trailing: store.modeId == m.id ? const Icon(Icons.check, color: VK.ok) : null,
                onTap: () => Navigator.pop(ctx, m.id),
              )),
        ],
      ),
    );
    if (id != null) {
      setState(() => store.modeId = id);
      await store.save();
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('V', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: VK.accent2)),
          SizedBox(height: 8),
          Text('Vektor', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          SizedBox(height: 10),
          Text(
            'Микрофон · файлы · приложения · ZIP\nCloudflare Worker для моделей\n\n«открой youtube»\n«файлы» · «zip» · «запомни …»',
            textAlign: TextAlign.center,
            style: TextStyle(color: VK.muted, fontSize: 13, height: 1.45),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  final VoidCallback onSpeak;
  const _Bubble({required this.msg, required this.onSpeak});
  @override
  Widget build(BuildContext context) {
    final mine = msg.role == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.86),
        decoration: BoxDecoration(
          color: mine ? VK.userBubble : VK.botBubble,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: mine ? VK.accent.withOpacity(0.35) : VK.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(msg.text, style: const TextStyle(color: VK.text, fontSize: 14.5, height: 1.35)),
          if (!mine)
            Row(children: [
              Text(
                [if (msg.mode != null) msg.mode!, if (msg.ms != null) '${msg.ms} мс', if (msg.error != null) 'err'].join(' · '),
                style: TextStyle(color: msg.error != null ? VK.danger : VK.muted, fontSize: 10),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onSpeak,
                icon: const Icon(Icons.volume_up, size: 16, color: VK.accent2),
              ),
            ]),
        ]),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final bool listening;
  final VoidCallback onSend;
  final VoidCallback onMic;
  const _Composer({required this.controller, required this.busy, required this.listening, required this.onSend, required this.onMic});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        decoration: const BoxDecoration(color: VK.panel, border: Border(top: BorderSide(color: VK.border))),
        child: Row(children: [
          Material(
            color: listening ? VK.danger : VK.panel2,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: busy ? null : onMic,
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(listening ? Icons.mic : Icons.mic_none, color: listening ? Colors.white : VK.accent2),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              style: const TextStyle(color: VK.text),
              decoration: InputDecoration(
                hintText: listening ? 'Слушаю…' : 'Сообщение или команда…',
                hintStyle: const TextStyle(color: VK.muted),
                filled: true,
                fillColor: VK.panel2,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: VK.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: VK.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: VK.accent)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: busy ? VK.border : VK.accent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: busy ? null : onSend,
              borderRadius: BorderRadius.circular(14),
              child: const SizedBox(width: 48, height: 48, child: Icon(Icons.arrow_upward_rounded, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Drawer extends StatelessWidget {
  final VektorStore store;
  final VektorVoice voice;
  final VoidCallback onChanged;
  const _Drawer({required this.store, required this.voice, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: VK.panel,
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
          const ListTile(
            title: Text('VEKTOR', style: TextStyle(fontWeight: FontWeight.w900, color: VK.accent2, letterSpacing: 1.4)),
            subtitle: Text('Flutter · голос · файлы · CF', style: TextStyle(color: VK.muted, fontSize: 12)),
          ),
          const Divider(color: VK.border),
          ListTile(
            leading: const Icon(Icons.folder_open, color: VK.accent2),
            title: const Text('Файлы'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => FilesPage(store: store)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.memory, color: VK.accent2),
            title: const Text('Память'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => MemoryPage(store: store))).then((_) => onChanged());
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: VK.accent2),
            title: const Text('Настройки / Cloudflare'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(store: store))).then((_) => onChanged());
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: VK.danger),
            title: const Text('Очистить чат'),
            onTap: () async {
              store.messages.clear();
              await store.save();
              onChanged();
              Navigator.pop(context);
            },
          ),
          const Divider(color: VK.border),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Команды:\n• открой youtube / telegram\n• файлы / zip / импорт\n• сохрани файл name: текст\n• запомни …\n• calc 2+2',
              style: TextStyle(color: VK.muted, fontSize: 12, height: 1.45),
            ),
          ),
        ]),
      ),
    );
  }
}

class FilesPage extends StatefulWidget {
  final VektorStore store;
  const FilesPage({super.key, required this.store});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  final tools = VektorTools();
  List<String> files = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await tools.listFiles();
    setState(() => files = list.map((e) => e.path).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Файлы'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: () async {
              await tools.importFile();
              await _reload();
            },
          ),
          IconButton(
            icon: const Icon(Icons.archive),
            onPressed: () async {
              final path = await tools.buildZip();
              await tools.sharePath(path);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ZIP: $path')));
            },
          ),
        ],
      ),
      body: files.isEmpty
          ? const Center(child: Text('Пусто — импорт или «сохрани файл»', style: TextStyle(color: VK.muted)))
          : ListView.builder(
              itemCount: files.length,
              itemBuilder: (_, i) {
                final path = files[i];
                final name = path.split('/').last;
                return ListTile(
                  title: Text(name),
                  subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: VK.muted)),
                  onTap: () => tools.openPath(path),
                  trailing: IconButton(icon: const Icon(Icons.share, size: 20), onPressed: () => tools.sharePath(path)),
                );
              },
            ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final VektorStore store;
  const SettingsPage({super.key, required this.store});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController cloud;
  late final TextEditingController model;
  @override
  void initState() {
    super.initState();
    cloud = TextEditingController(text: widget.store.cloudBase);
    model = TextEditingController(text: widget.store.model);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloudflare / модель')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Worker URL (твой CF)', style: TextStyle(color: VK.muted, fontSize: 12)),
        TextField(controller: cloud, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 12),
        const Text('Model id', style: TextStyle(color: VK.muted, fontSize: 12)),
        TextField(controller: model, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            widget.store.cloudBase = cloud.text.trim();
            widget.store.model = model.text.trim().isEmpty ? widget.store.model : model.text.trim();
            await widget.store.save();
            if (mounted) Navigator.pop(context);
          },
          child: const Text('Сохранить'),
        ),
        const SizedBox(height: 12),
        Text('Сейчас: ${widget.store.cloudBase}', style: const TextStyle(color: VK.muted, fontSize: 11)),
      ]),
    );
  }
}

class MemoryPage extends StatefulWidget {
  final VektorStore store;
  const MemoryPage({super.key, required this.store});
  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  final ctrl = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final mem = widget.store.memory;
    return Scaffold(
      appBar: AppBar(title: const Text('Память')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Запись', filled: true, fillColor: VK.panel2))),
            FilledButton(
              onPressed: () async {
                widget.store.addMemory(ctrl.text);
                ctrl.clear();
                await widget.store.save();
                setState(() {});
              },
              child: const Text('ADD'),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: mem.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(mem[i], style: const TextStyle(fontSize: 13)),
              trailing: IconButton(
                icon: const Icon(Icons.close, color: VK.danger, size: 18),
                onPressed: () async {
                  setState(() => widget.store.memory.removeAt(i));
                  await widget.store.save();
                },
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
