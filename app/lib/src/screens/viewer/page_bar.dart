part of '../viewer_screen.dart';

// The page number box and the nyel AI button at the bottom of the viewer.

/// The round nyel AI button over the page: the sparkle only, like the one
/// in the middle of the tab bar.
class _AiButton extends StatelessWidget {
  const _AiButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Tanya nyel AI tentang halaman ini',
      child: Material(
        key: const Key('viewer-ai'),
        color: AppColors.orange,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: const Color(0x66101828),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Center(child: AppIcon(AppGlyph.nyel, color: Colors.white, size: 28)),
          ),
        ),
      ),
    );
  }
}

/// The section being read and a page number box: type a page and press
/// enter to go there.
class _PageBar extends StatefulWidget {
  const _PageBar({required this.page, required this.pageCount, required this.section, required this.onJump});

  final int page;
  final int pageCount;
  final String? section;
  final ValueChanged<int> onJump;

  @override
  State<_PageBar> createState() => _PageBarState();
}

class _PageBarState extends State<_PageBar> {
  late final _field = TextEditingController(text: '${widget.page}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Leaving the box without pressing enter shows the current page again.
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _field.selection = TextSelection(baseOffset: 0, extentOffset: _field.text.length);
      } else {
        _field.text = '${widget.page}';
      }
    });
  }

  @override
  void didUpdateWidget(_PageBar old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.page != widget.page) _field.text = '${widget.page}';
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(String text) {
    final page = int.tryParse(text.trim());
    _focus.unfocus();
    if (page == null) return;
    widget.onJump(page.clamp(1, widget.pageCount));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.section ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
              const SizedBox(width: 10),
              Text('Hlm', style: TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(width: 6),
              SizedBox(
                width: 64,
                child: TextField(
                  key: const Key('page-input'),
                  controller: _field,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.go,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: _go,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.field,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              Text(' / ${widget.pageCount}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
