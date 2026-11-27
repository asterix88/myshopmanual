part of '../inspection_screen.dart';

// The navy header: title, last update, section tabs and the model filter button.

class _Header extends StatelessWidget {
  const _Header({
    required this.subtitle,
    required this.sheetUrl,
    required this.sections,
    required this.section,
    required this.openCounts,
    required this.onSection,
    required this.search,
    required this.onSearch,
  });

  final String subtitle;
  final String sheetUrl;
  final List<String> sections;
  final String section;
  final Map<String, int> openCounts;
  final ValueChanged<String> onSection;
  final TextEditingController search;
  final VoidCallback onSearch;

  Future<void> _openSheet(BuildContext context) async {
    if (sheetUrl.isEmpty) return;
    final ok = await launchUrl(Uri.parse(sheetUrl), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) showError(context, 'Spreadsheet tidak bisa dibuka di HP ini');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _headerNavy,
      padding: EdgeInsets.fromLTRB(8, MediaQuery.paddingOf(context).top + 8, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: Colors.white,
                tooltip: 'Kembali',
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daily Inspection Monitoring',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600, height: 1.2),
                    ),
                    Text(subtitle, style: const TextStyle(color: _headerSoft, fontSize: 12)),
                  ],
                ),
              ),
              if (sheetUrl.isNotEmpty)
                Material(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    key: const Key('inspection-sheet-link'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openSheet(context),
                    child: const SizedBox(
                      height: 32,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(8, 0, 10, 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.language_rounded, size: 15, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Sheet', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            SizedBox(width: 4),
                            Icon(Icons.north_east_rounded, size: 14, color: Color(0xFFF08A1C)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (sections.length > 1) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    for (final s in sections)
                      Expanded(
                        child: GestureDetector(
                          key: Key('inspection-tab-$s'),
                          onTap: () => onSection(s),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: s == section ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(text: sectionLabel(s)),
                                TextSpan(
                                  text: '  ${openCounts[s] ?? 0}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: s == section ? const Color(0xFFB42318) : _headerSoft,
                                  ),
                                ),
                              ]),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: s == section ? _headerNavy : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 20, color: Color(0xFF6B7178)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const Key('inspection-search'),
                      controller: search,
                      onChanged: (_) => onSearch(),
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF1F2328)),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        filled: false,
                        hintText: 'Cari kode unit / temuan',
                        hintStyle: TextStyle(fontSize: 13, color: Color(0xFFA3A8AF)),
                      ),
                    ),
                  ),
                  if (search.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        search.clear();
                        onSearch();
                      },
                      child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF6B7178)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.text, this.icon, this.danger = false, this.onClose});

  final String text;
  final IconData? icon;
  final bool danger;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? AppColors.danger : AppColors.amber;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: danger ? AppColors.danger.withValues(alpha: 0.1) : AppColors.amberSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon ?? Icons.error_outline_rounded, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: fg))),
          if (onClose != null)
            GestureDetector(onTap: onClose, child: Icon(Icons.close_rounded, size: 16, color: fg)),
        ],
      ),
    );
  }
}

class _ModelButton extends StatelessWidget {
  const _ModelButton({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : AppColors.ink;
    return Material(
      color: active ? AppColors.navy : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: active ? AppColors.navy : AppColors.border),
      ),
      child: InkWell(
        key: const Key('inspection-model-filter'),
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.filter_list_rounded, size: 18, color: fg),
                const SizedBox(width: 6),
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Model: '),
                    TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  style: TextStyle(fontSize: 13, color: fg),
                ),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
