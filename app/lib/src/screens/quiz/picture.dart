part of '../quiz_screen.dart';

// A quiz question's picture and its full-screen zoom.

/// The picture of a "gambar" question: the manual's drawing with its numbers
/// and without its words. Tap to see it full screen and zoom in.
class QuizPicture extends StatefulWidget {
  const QuizPicture({super.key, required this.api, required this.questionId, this.height = 220});

  final QuizApi api;
  final String questionId;
  final double height;

  @override
  State<QuizPicture> createState() => _QuizPictureState();
}

class _QuizPictureState extends State<QuizPicture> {
  late Future<Uint8List> _bytes = widget.api.image(widget.questionId);

  @override
  void didUpdateWidget(QuizPicture old) {
    super.didUpdateWidget(old);
    if (old.questionId != widget.questionId) _bytes = widget.api.image(widget.questionId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        final bytes = snap.data;
        return Semantics(
          label: 'Gambar soal. Ketuk untuk perbesar',
          button: bytes != null,
          child: GestureDetector(
            onTap: bytes == null
                ? (snap.hasError ? () => setState(() => _bytes = widget.api.image(widget.questionId)) : null)
                : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _PictureZoom(bytes: bytes))),
            child: Container(
              height: widget.height,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes != null
                  ? Stack(
                      children: [
                        Positioned.fill(child: Image.memory(bytes, fit: BoxFit.contain, filterQuality: FilterQuality.medium)),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xB31F2328), borderRadius: BorderRadius.circular(8)),
                            child: const Text('Ketuk untuk perbesar', style: TextStyle(fontSize: 11, color: Colors.white)),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: snap.hasError
                          ? Text('Gagal dimuat. Ketuk lagi',
                              style: TextStyle(fontSize: 12, color: AppColors.muted))
                          : const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _PictureZoom extends StatelessWidget {
  const _PictureZoom({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const QuizBar(title: 'Gambar soal', close: true),
      body: InteractiveViewer(
        maxScale: 8,
        child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
      ),
    );
  }
}
