import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化 Supabase
  await Supabase.initialize(
    url: 'https://zivvlwjsjcyujmrenekg.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InppdnZsd2pzamN5dWptcmVuZWtnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI1MDQ2OTEsImV4cCI6MjA4ODA4MDY5MX0.IRZ-Kd_emp5eKWv7dssYcOf4qT4Ev_qgch7GVzNbMkU',
  );

  runApp(const MinimalistNotesApp());
}

final supabase = Supabase.instance.client;

// --- 模型类 (Model) ---
class Note {
  final String id;
  final String title;
  final String content;
  final String category;
  final DateTime createdAt;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.createdAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      // 使用 ?? 确保 Null 安全，防止 type 'Null' is not a subtype of type 'String' 错误
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      category: (json['category'] ?? 'Other').toString(),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
    );
  }
}

// --- 主应用 (Main App) ---
class MinimalistNotesApp extends StatelessWidget {
  const MinimalistNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minimalist Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF9F9F9),
        primaryColor: Colors.yellow[700],
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.yellow,
          surface: const Color(0xFFF9F9F9),
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF9F9F9),
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black87),
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      home: const NoteListScreen(),
    );
  }
}

// --- 列表页面 (List Screen) ---
class NoteListScreen extends StatefulWidget {
  const NoteListScreen({super.key});

  @override
  State<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends State<NoteListScreen> {
  List<Note> _notes = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchNotes();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // 修复了查询逻辑：确保先构建完所有过滤条件再 await 执行
  Future<void> _fetchNotes([String query = '']) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      // 1. 开始构建查询
      var queryBuilder = supabase.from('notes').select();
      
      // 2. 如果有搜索关键词，链式添加 or 过滤
      if (query.isNotEmpty) {
        queryBuilder = queryBuilder.or('title.ilike.%$query%,content.ilike.%$query%');
      }

      // 3. 添加排序并最终执行查询 (await)
      final List<dynamic> data = await queryBuilder.order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _notes = data.map((json) => Note.fromJson(json as Map<String, dynamic>)).toList();
        });
      }
    } catch (e) {
      debugPrint('Fetch Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchQuery = query;
      _fetchNotes(query);
    });
  }

  Future<void> _createNote() async {
    try {
      final data = await supabase.from('notes').insert({
        'title': '',
        'content': '',
        'category': 'Other',
      }).select().single();

      final newNote = Note.fromJson(data);
      
      if (mounted) {
        setState(() {
          _notes.insert(0, newNote);
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NoteDetailScreen(note: newNote),
          ),
        ).then((_) => _fetchNotes(_searchQuery));
      }
    } catch (e) {
      debugPrint('Error creating note: $e');
    }
  }

  Future<void> _deleteNote(String id) async {
    // 乐观更新 UI
    setState(() {
      _notes.removeWhere((note) => note.id == id);
    });

    try {
      await supabase.from('notes').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting note: $e');
      _fetchNotes(_searchQuery); // 出错时回滚刷新
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.month}/${date.day}';
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Work': return Colors.blue[100]!;
      case 'Life': return Colors.green[100]!;
      default: return Colors.grey[200]!;
    }
  }

  Color _getCategoryTextColor(String category) {
    switch (category) {
      case 'Work': return Colors.blue[800]!;
      case 'Life': return Colors.green[800]!;
      default: return Colors.grey[800]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          // 列表区域
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.yellow))
                : _notes.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty ? 'No notes yet' : 'No notes found',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _notes.length,
                        itemBuilder: (context, index) {
                          final note = _notes[index];
                          return Dismissible(
                            key: Key(note.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20.0),
                              color: Colors.red,
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) => _deleteNote(note.id),
                            child: ListTile(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => NoteDetailScreen(note: note),
                                  ),
                                ).then((_) => _fetchNotes(_searchQuery));
                              },
                              title: Text(
                                note.title.isEmpty ? 'New Note' : note.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              subtitle: Row(
                                children: [
                                  Text(_formatDate(note.createdAt)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _getCategoryColor(note.category),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      note.category,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: _getCategoryTextColor(note.category),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      note.content.isEmpty ? 'No additional text' : note.content,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNote,
        backgroundColor: Colors.yellow[700],
        elevation: 2,
        child: const Icon(Icons.edit_square, color: Colors.black87),
      ),
    );
  }
}

// --- 详情页面 (Detail Screen) ---
class NoteDetailScreen extends StatefulWidget {
  final Note note;

  const NoteDetailScreen({super.key, required this.note});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late String _category;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _contentController = TextEditingController(text: widget.note.content);
    _category = widget.note.category;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onNoteChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        await supabase.from('notes').update({
          'title': _titleController.text,
          'content': _contentController.text,
          'category': _category,
        }).eq('id', widget.note.id);
      } catch (e) {
        debugPrint('Error updating note: $e');
      }
    });
  }

  void _updateCategory(String newCategory) {
    setState(() {
      _category = newCategory;
    });
    _onNoteChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () async {
              try {
                await supabase.from('notes').delete().eq('id', widget.note.id);
                if (mounted) Navigator.pop(context);
              } catch (e) {
                debugPrint('Delete error: $e');
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 分类选择器
              Row(
                children: ['Work', 'Life', 'Other'].map((cat) {
                  final isSelected = _category == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      onSelected: (_) => _updateCategory(cat),
                      selectedColor: Colors.black87,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black54,
                        fontSize: 12,
                      ),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? Colors.black87 : Colors.grey[300]!,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // 标题输入
              TextField(
                controller: _titleController,
                onChanged: (_) => _onNoteChanged(),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                decoration: const InputDecoration(
                  hintText: 'Title',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.black26),
                ),
              ),
              // 内容输入
              Expanded(
                child: TextField(
                  controller: _contentController,
                  onChanged: (_) => _onNoteChanged(),
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.5,
                    color: Colors.black87,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Start typing...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.black26),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
