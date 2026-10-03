import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';

/// Placeholder for the AI chat tab. The chat answers from the manuals in
/// the app and needs an internet connection; it is built in a later stage.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 14,
        shape: const Border(bottom: BorderSide(color: Color(0xFFE6E8EB))),
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', width: 42, height: 42),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tanya AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy)),
                Text(
                  'Jawaban dari manual di aplikasi',
                  style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Pill('SEGERA HADIR', background: AppColors.orangeSoft, foreground: AppColors.orangeText),
                const SizedBox(height: 10),
                const Text(
                  'Tanya soal teknis, AI menjawab dari manual',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Contoh: "Lampu hydraulic oil filter clogging nyala, apa yang harus dilakukan?" '
                  'Jawaban akan menyebut sumbernya, misalnya OMM hlm 87, dan bisa diketuk untuk membuka halamannya.',
                  style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF3A3F45)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      store.online == true ? Icons.wifi : Icons.wifi_off,
                      size: 18,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Fitur ini butuh internet. Membuka dan mencari manual tetap bisa offline.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
