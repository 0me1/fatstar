import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/nutrition.dart';
import '../domain/records.dart';
import 'catalog.dart';
import 'controller.dart';
import 'forms.dart';
import 'goals.dart';
import 'settings.dart';
import 'auth_errors.dart';
import 'food_add_button.dart';
import 'motion.dart';
import 'meal_section.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false, visible = false;
  String? error;
  DateTime? recoveryRequestedAt;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit({bool recovery = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    final c = ref.read(diaryProvider);
    final action = c.needsPassword
        ? AuthAction.password
        : recovery
        ? AuthAction.recovery
        : AuthAction.login;
    try {
      if (c.needsPassword) {
        if (password.text.length < 8) {
          throw ArgumentError('Пароль не короче 8 символов');
        }
        await c.client.auth.updateUser(UserAttributes(password: password.text));
        c.needsPassword = false;
        await c.reload();
      } else if (recovery) {
        if (!RegExp(
          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
        ).hasMatch(email.text.trim())) {
          throw ArgumentError(
            'Введите корректный email для восстановления доступа',
          );
        }
        final requestedAt = recoveryRequestedAt;
        if (requestedAt != null &&
            DateTime.now().difference(requestedAt).inSeconds < 60) {
          throw ArgumentError(
            'Подождите минуту перед повторной отправкой. '
            'Откройте самое новое письмо на телефоне с установленным приложением.',
          );
        }
        recoveryRequestedAt = DateTime.now();
        await c.client.auth
            .resetPasswordForEmail(
              email.text.trim(),
              redirectTo: 'com.fatstar.caloriediary://auth/recovery',
            )
            .timeout(const Duration(seconds: 20));
        if (mounted) {
          message(
            context,
            'Если адрес зарегистрирован, письмо восстановления отправлено. '
            'Откройте самое новое письмо на этом телефоне; ссылка одноразовая.',
          );
        }
      } else {
        await c.client.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = authFailureMessage(e, action));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(diaryProvider).needsPassword;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.restaurant_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    recovery ? 'Новый пароль' : 'Calorie Diary',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Личный дневник. Общий каталог. Вход по приглашению.',
                  ),
                  const SizedBox(height: 28),
                  if (!recovery)
                    TextField(
                      controller: email,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: password,
                    obscureText: !visible,
                    autofillHints: [
                      recovery
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => visible = !visible),
                        tooltip: 'Показать пароль',
                        icon: Icon(
                          visible ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(
                      busy
                          ? 'Подождите…'
                          : recovery
                          ? 'Сохранить пароль'
                          : 'Войти',
                    ),
                  ),
                  if (!recovery)
                    TextButton(
                      onPressed: busy ? null : () => submit(recovery: true),
                      child: const Text('Восстановить доступ'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: index,
      children: const [
        DiaryScreen(),
        CatalogScreen(),
        GoalsScreen(),
        SettingsScreen(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (v) => setState(() => index = v),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.book_outlined),
          selectedIcon: Icon(Icons.book),
          label: 'Дневник',
        ),
        NavigationDestination(icon: Icon(Icons.search), label: 'Продукты'),
        NavigationDestination(icon: Icon(Icons.flag_outlined), label: 'Цели'),
        NavigationDestination(icon: Icon(Icons.tune), label: 'Настройки'),
      ],
    ),
  );
}

class DiaryScreen extends ConsumerWidget {
  const DiaryScreen({super.key});
  Future<void> add(BuildContext context, Meal meal) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => CatalogScreen(meal: meal)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(diaryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          dayKey(c.day) == dayKey(DateTime.now())
              ? 'Сегодня'
              : DateFormat('d MMMM', 'ru').format(c.day),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SyncStatus(
                running: c.sync?.isRunning ?? false,
                failed: c.sync?.error != null,
                succeeded: c.sync?.lastSuccess != null,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Предыдущий день',
            onPressed: () =>
                c.selectDay(DateTime(c.day.year, c.day.month, c.day.day - 1)),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Календарь',
            onPressed: () async {
              final day = await showDatePicker(
                context: context,
                initialDate: c.day,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (day != null) c.selectDay(day);
            },
            icon: const Icon(Icons.calendar_month),
          ),
          IconButton(
            tooltip: 'Следующий день',
            onPressed: dayKey(c.day) == dayKey(DateTime.now())
                ? null
                : () => c.selectDay(
                    DateTime(c.day.year, c.day.month, c.day.day + 1),
                  ),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: DiaryMotion(
        day: c.day,
        selectDay: c.selectDay,
        child: page(context, c, c.day),
        pageBuilder: (day) => page(context, c, day),
      ),
    );
  }

  Widget page(BuildContext context, DiaryController c, DateTime day) {
    final entries = c
        .of('entry')
        .where((e) => e.data['day'] == dayKey(day))
        .toList();
    final goalRecord = goalForDay(c.records, day);
    final total = NutritionTotal(entries.map(entryNutrition));
    final goal = goalRecord == null
        ? null
        : Nutrition.fromJson(
            Map<String, dynamic>.from(goalRecord.data['nutrition'] as Map),
          );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (c.sync?.error != null)
          Text(c.sync!.error!, style: Theme.of(context).textTheme.bodySmall),
        Text('Сводка', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 24,
                  runSpacing: 16,
                  children: [
                    Column(
                      children: [
                        MotionNumber(
                          value: total.kcal,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Text('Съедено'),
                      ],
                    ),
                    SizedBox(
                      width: 160,
                      height: 160,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: GoalPulse(
                              reached:
                                  goal != null &&
                                  total.kcal >= goal.kcal &&
                                  total.kcal <= goal.kcal * 1.02,
                              child: MotionProgress(
                                circular: true,
                                label: 'Прогресс калорий',
                                value: goal == null || goal.kcal == 0
                                    ? 0
                                    : (total.kcal / goal.kcal).clamp(0.0, 1.0),
                              ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (goal == null)
                                const Text('—')
                              else
                                MotionNumber(
                                  value: (goal.kcal - total.kcal).abs(),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                              Text(
                                goal == null
                                    ? 'Цель не задана'
                                    : total.kcal > goal.kcal
                                    ? 'Сверх цели'
                                    : 'Осталось',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  goal == null
                      ? 'Задайте норму в разделе «Цели»'
                      : 'Суточная цель ${number(goal.kcal, 0)} ккал',
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    macro(
                      context,
                      'Углеводы',
                      total.carbs,
                      goal?.carbs,
                      total.carbsComplete,
                    ),
                    macro(
                      context,
                      'Белки',
                      total.protein,
                      goal?.protein,
                      total.proteinComplete,
                    ),
                    macro(
                      context,
                      'Жиры',
                      total.fat,
                      goal?.fat,
                      total.fatComplete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Питание', style: Theme.of(context).textTheme.titleLarge),
        Card(
          child: Column(
            children: [
              for (final meal in Meal.values) ...[
                if (meal != Meal.breakfast) const Divider(height: 1),
                MealSection(
                  key: ValueKey('meal/${dayKey(day)}/${meal.name}'),
                  hasEntries: entries.any((e) => e.data['meal'] == meal.name),
                  header: (expanded, toggle) => ListTile(
                    minVerticalPadding: 24,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Container(
                      width: 58,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF596161)
                              : const Color(0xFFCFDBD8),
                          width: 7,
                        ),
                      ),
                      child: ExcludeSemantics(
                        child: Text(switch (meal) {
                          Meal.breakfast => '☕',
                          Meal.lunch => '🍝',
                          Meal.dinner => '🥗',
                          Meal.snack => '🍎',
                        }, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            meal.label,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: motionDuration(context, 180),
                          child: const Icon(
                            Icons.expand_more_rounded,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '${number(NutritionTotal(entries.where((e) => e.data['meal'] == meal.name).map(entryNutrition)).kcal, 0)} ккал',
                    ),
                    trailing: FoodAddButton(
                      tooltip: 'Добавить в ${meal.label.toLowerCase()}',
                      onPressed: () => add(context, meal),
                    ),
                    onTap: toggle,
                    onLongPress: () => copyMeal(context, c, meal),
                  ),
                  child: Column(
                    children: [
                      MotionRows(
                        key: ValueKey('entries/${dayKey(day)}/${meal.name}'),
                        children: [
                          for (final e in entries.where(
                            (e) => e.data['meal'] == meal.name,
                          ))
                            Dismissible(
                              key: ValueKey(e.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: Theme.of(context).colorScheme.error,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                child: Icon(
                                  Icons.delete_outline,
                                  color: Theme.of(context).colorScheme.onError,
                                ),
                              ),
                              confirmDismiss: (_) async {
                                try {
                                  await deleteDiaryEntry(context, c, e);
                                } catch (error) {
                                  if (context.mounted) {
                                    message(context, error);
                                  }
                                }
                                return false;
                              },
                              child: ListTile(
                                key: ValueKey(e.id),
                                title: Text(e.data['name'] as String),
                                subtitle: Text(
                                  '${number(e.data['amount'] as num)} ${e.data['unit'] == 'gram'
                                      ? 'г'
                                      : e.data['unit'] == 'milliliter'
                                      ? 'мл'
                                      : 'запись'} · ${number(entryNutrition(e).kcal, 0)} ккал',
                                ),
                                onTap: () async {
                                  final data = await editEntry(context, e);
                                  if (data != null) {
                                    try {
                                      await c.save('entry', data, previous: e);
                                      if (context.mounted) {
                                        undo(context, c, e);
                                      }
                                    } catch (error) {
                                      if (context.mounted) {
                                        message(context, error);
                                      }
                                    }
                                  }
                                },
                                trailing: PopupMenuButton<String>(
                                  tooltip: 'Действия с записью',
                                  onSelected: (action) async {
                                    try {
                                      if (action == 'delete') {
                                        await deleteDiaryEntry(context, c, e);
                                      }
                                      if (action == 'repeat') {
                                        await c.addEntries([e.data], meal);
                                      }
                                      if (action == 'copy' && context.mounted) {
                                        final date = await showDatePicker(
                                          context: context,
                                          initialDate: day,
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2100),
                                        );
                                        if (date != null) {
                                          await c.save('entry', {
                                            ...e.data,
                                            'day': dayKey(date),
                                          });
                                        }
                                      }
                                    } catch (error) {
                                      if (context.mounted) {
                                        message(context, error);
                                      }
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'repeat',
                                      child: Text('Повторить'),
                                    ),
                                    PopupMenuItem(
                                      value: 'copy',
                                      child: Text('Копировать на дату'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Удалить'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextButton.icon(
                          onPressed: () => copyMeal(context, c, meal),
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: const Text('Копировать с другого дня'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget macro(
    BuildContext context,
    String name,
    double value,
    double? target,
    bool complete,
  ) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Text(name, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          MotionProgress(
            circular: false,
            value: target == null || target == 0
                ? 0
                : (value / target).clamp(0.0, 1.0),
          ),
          const SizedBox(height: 8),
          MotionNumber(
            value: value,
            prefix: complete ? '' : '≥ ',
            suffix: ' / ${number(target, 0)} г',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );

  Future<void> copyMeal(
    BuildContext context,
    DiaryController c,
    Meal target,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate: c.day.subtract(const Duration(days: 1)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return;
    final source = await showModalBottomSheet<Meal>(
      context: context,
      showDragHandle: true,
      sheetAnimationStyle: sheetMotion(context),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final meal in Meal.values)
            ListTile(
              title: Text(meal.label),
              onTap: () => Navigator.pop(context, meal),
            ),
        ],
      ),
    );
    if (source == null || !context.mounted) return;
    final values = c
        .of('entry')
        .where(
          (r) => r.data['day'] == dayKey(date) && r.data['meal'] == source.name,
        )
        .toList();
    if (values.isEmpty) {
      message(context, 'В выбранном приеме нет записей');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Копировать прием пищи?'),
        content: Text(
          '${source.label}, ${dayKey(date)} → ${target.label}, ${dayKey(c.day)}\n${values.map((r) => r.data['name']).join(', ')}\n${number(NutritionTotal(values.map(entryNutrition)).kcal, 0)} ккал',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Копировать'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await c.copyMeal(date, source, target);
    }
  }
}

Future<void> deleteDiaryEntry(
  BuildContext context,
  DiaryController c,
  Record entry,
) async {
  await c.remove(entry);
  unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
  if (context.mounted) {
    undo(context, c, entry);
  }
}

void undo(BuildContext context, DiaryController c, Record original) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Изменение сохранено'),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () async {
            try {
              await c.restore(original);
            } catch (e) {
              if (context.mounted) {
                message(context, e);
              }
            }
          },
        ),
      ),
    );
