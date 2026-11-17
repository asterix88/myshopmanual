part of '../quiz_admin_screen.dart';

// Editing one quiz question.

/// Edit a question; returns the changed fields (with _publish when
/// "Simpan & terbitkan" was chosen).
class QuizEditScreen extends StatefulWidget {
  const QuizEditScreen({super.key, required this.question});

  final AdminQuestion question;

  @override
  State<QuizEditScreen> createState() => _QuizEditScreenState();
}

class _QuizEditScreenState extends State<QuizEditScreen> {
  late final QuizQuestion q = widget.question.question;
  late final _prompt = TextEditingController(text: q.prompt);
  late final _explain = TextEditingController(text: q.explain);
  late final _choices = [for (final c in q.choices) TextEditingController(text: c)];
  late int _answer = q.answer;
  late String _topic = q.topic;

  @override
  void dispose() {
    _prompt.dispose();
    _explain.dispose();
    for (final c in _choices) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _fields() => {
        'section': widget.question.section,
        'unit': q.unit ?? '',
        'topic': _topic,
        'type': q.type,
        'prompt': _prompt.text.trim(),
        'choices': [for (final c in _choices) c.text.trim()],
        'answer': _answer,
        'explain': _explain.text.trim(),
        'manual_id': q.manualId,
        'page': q.page,
      };

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const QuizBar(title: 'Ubah soal'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: quizTopics.containsKey(_topic) ? _topic : 'struktur',
            decoration: const InputDecoration(labelText: 'Topik'),
            items: [for (final t in quizTopics.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
            onChanged: (v) => setState(() => _topic = v ?? _topic),
          ),
          const SizedBox(height: 12),
          TextField(controller: _prompt, maxLines: null, decoration: const InputDecoration(labelText: 'Pertanyaan')),
          const SizedBox(height: 16),
          const SectionLabel('Pilihan (ketuk lingkaran untuk kunci jawaban)'),
          for (final (i, c) in _choices.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Jadikan kunci jawaban',
                    onPressed: () => setState(() => _answer = i),
                    icon: Icon(
                      i == _answer ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: i == _answer ? AppColors.green : AppColors.muted,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: c,
                      readOnly: q.type == 'bs',
                      decoration: InputDecoration(labelText: 'Pilihan ${'ABCD'[i.clamp(0, 3)]}'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          TextField(controller: _explain, maxLines: null, decoration: const InputDecoration(labelText: 'Penjelasan')),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, _fields()),
                child: const Text('Simpan'),
              ),
            ),
            if (widget.question.status != 'terbit') ...[
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, {..._fields(), '_publish': true}),
                  child: const Text('Simpan & terbitkan'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
