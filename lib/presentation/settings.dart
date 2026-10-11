import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/backup.dart';
import '../domain/records.dart';
import '../domain/fonts.dart';
import 'controller.dart';
import 'forms.dart';
import 'motion.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(diaryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Аккаунт'),
                  subtitle: Text(c.client.auth.currentUser?.email ?? ''),
                ),
                ListTile(
                  title: const Text('Тема'),
                  trailing: DropdownButton<String>(
                    value: c.theme,
                    items: const [
                      DropdownMenuItem(value: 'dark', child: Text('Темная')),
                      DropdownMenuItem(value: 'light', child: Text('Светлая')),
                      DropdownMenuItem(
                        value: 'system',
                        child: Text('Системная'),
                      ),
                    ],
                    onChanged: (v) async {
                      try {
                        await c.saveSettings({'theme': v});
                      } catch (e) {
                        if (context.mounted) message(context, e);
                      }
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Шрифт'),
                  subtitle: Text(diaryFonts[c.font]!),
                  trailing: const Icon(Icons.text_fields),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    useSafeArea: true,
                    showDragHandle: true,
                    sheetAnimationStyle: sheetMotion(context),
                    builder: (sheetContext) => ListView(
                      shrinkWrap: true,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Выберите шрифт'),
                        ),
                        for (final font in diaryFonts.entries)
                          ListTile(
                            title: Text(
                              font.value,
                              style: TextStyle(
                                fontFamily: font.key,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              'Сводка · Завтрак · 1 750 ккал',
                              style: TextStyle(fontFamily: font.key),
                            ),
                            trailing: font.key == c.font
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () async {
                              try {
                                await c.saveSettings({'font': font.key});
                                if (sheetContext.mounted)
                                  Navigator.pop(sheetContext);
                              } catch (e) {
                                if (sheetContext.mounted)
                                  message(sheetContext, e);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Синхронизация'),
                  subtitle: Text(
                    '${c.operations.length} операций ожидают отправки\n${c.sync?.error ?? 'Последняя успешная: ${c.sync?.lastSuccess?.toLocal().toString() ?? 'еще не выполнена'}'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Повторить синхронизацию',
                    icon: SyncStatus(
                      running: c.sync?.isRunning ?? false,
                      failed: c.sync?.error != null,
                      succeeded: c.sync?.lastSuccess != null,
                    ),
                    onPressed: () => c.sync?.run(),
                  ),
                ),
                for (final operation in c.operations.where(
                  (o) => o['status'] == 'conflict',
                ))
                  ExpansionTile(
                    title: const Text('Конфликт изменений'),
                    subtitle: Text(
                      '${operation['kind']} · ${operation['record_id']}',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Ваше изменение:\n${operation['payload']}\n\nНа сервере:\n${operation['server']}',
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () =>
                                resolve(context, c, operation, false),
                            child: const Text('Принять сервер'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                resolve(context, c, operation, true),
                            child: const Text('Сохранить свою правку'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
              ],
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Экспорт JSON'),
                  subtitle: const Text(
                    'Дневник, цели, вес, избранное и продукты',
                  ),
                  onTap: () => export(context, c),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Импорт JSON'),
                  subtitle: const Text(
                    'Безопасное объединение с предварительным просмотром',
                  ),
                  onTap: () => import(context, c),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Выйти'),
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Выйти из аккаунта?'),
                  content: Text(
                    '${c.operations.length} несинхронизированных операций. Локальные данные сохранятся и будут доступны после входа в этот же аккаунт.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Отмена'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Выйти'),
                    ),
                  ],
                ),
              );
              if (yes == true) {
                try {
                  await c.signOut();
                } catch (e) {
                  if (context.mounted) message(context, e);
                }
              }
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Calorie Diary 1.0.0\nВаши данные хранятся локально; синхронизация выполняется с вашим проектом Supabase.',
          ),
        ],
      ),
    );
  }

  Future<void> resolve(
    BuildContext context,
    DiaryController c,
    Json op,
    bool keepLocal,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          keepLocal ? 'Применить вашу версию?' : 'Принять серверную версию?',
        ),
        content: const Text(
          'Это решение применяется ко всем вашим ожидающим правкам этой записи. Новое изменение на сервере может вызвать повторный конфликт.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await c.db!.resolve(op, keepLocal: keepLocal);
      await c.reload();
      await c.sync?.run();
    } catch (e) {
      if (context.mounted) message(context, e);
    }
  }

  Future<void> export(BuildContext context, DiaryController c) async {
    try {
      final source = await BackupService(c.db!).export();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/calorie-diary-${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(source);
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'Резервная копия Calorie Diary',
          ),
        );
      } finally {
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      if (context.mounted) message(context, 'Не удалось экспортировать: $e');
    }
  }

  Future<void> import(BuildContext context, DiaryController c) async {
    try {
      final files = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (files == null) return;
      final file = files.files.single;
      if (file.size > 20 * 1024 * 1024) {
        throw const FormatException('Файл больше 20 МБ');
      }
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final preview = await BackupService(c.db!).preview(utf8.decode(bytes));
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Объединить резервную копию?'),
          content: Text(
            'Новых: ${preview.newCount}\nСовпадающих: ${preview.sameCount}\nКонфликтов: ${preview.conflicts.length}\n\nСуществующие записи и конфликты останутся без изменений. Импортированные продукты останутся локальными.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Объединить'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await BackupService(c.db!).merge(preview);
        await c.reload();
        await c.sync?.run();
        if (context.mounted) message(context, 'Импорт завершен');
      }
    } catch (e) {
      if (context.mounted) message(context, 'Импорт отменен: $e');
    }
  }
}
