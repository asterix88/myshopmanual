part of '../chat_screen.dart';

// The bottom of the chat: 'working' indicators and the input bar.

class _Working extends StatelessWidget {
  const _Working({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown above the input while the phone downloads the search indexes of
/// manuals that are not downloaded, in any state of the chat.
class _Preparing extends StatelessWidget {
  const _Preparing({required this.progress});

  final AiIndexProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final bytes = p.totalBytes == 0 ? null : (p.receivedBytes / p.totalBytes).clamp(0.0, 1.0);
    return Container(
      color: AppColors.navySoft,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Menyiapkan indeks AI: ${p.ready}/${p.total} manual'
            '${p.totalBytes == 0 ? '' : ' (${formatSize(p.receivedBytes)}/${formatSize(p.totalBytes)})'}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy),
          ),
          const SizedBox(height: 2),
          Text(
            'Jawaban sementara dari manual yang sudah terindeks',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: bytes, minHeight: 4, borderRadius: BorderRadius.circular(2)),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.onSend,
    required this.background,
    required this.fill,
    this.dimmed = false,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final VoidCallback onSend;

  /// The bar and the field, which follow the chat's mode.
  final Color background;
  final Color fill;

  /// Shown faded (today's questions are used up); the placeholder stays.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      child: SafeArea(
        top: false,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: dimmed ? 0.45 : 1,
          child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  // Enter on the keyboard starts a new line; the send button
                  // next to the field sends the question.
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: fill,
                    hintText: hint,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Kirim',
                onPressed: enabled ? onSend : null,
                icon: Icon(Icons.send_rounded, color: AppColors.navy),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
