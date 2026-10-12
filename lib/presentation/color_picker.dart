import 'package:flutter/material.dart';
import 'motion.dart';

Future<int?> pickAccent(BuildContext context, int initial) =>
    showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      sheetAnimationStyle: sheetMotion(context),
      builder: (_) => AccentPicker(initial: Color(initial)),
    );

class AccentPicker extends StatefulWidget {
  const AccentPicker({super.key, required this.initial});
  final Color initial;
  @override
  State<AccentPicker> createState() => _AccentPickerState();
}

class _AccentPickerState extends State<AccentPicker> {
  late HSVColor hsv = HSVColor.fromColor(widget.initial);
  late final hex = TextEditingController(text: code(widget.initial));
  String? error;
  String code(Color color) =>
      color.toARGB32().toRadixString(16).substring(2).toUpperCase();
  void update(HSVColor value) => setState(() {
    hsv = value;
    hex.text = code(hsv.toColor());
    error = null;
  });
  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Акцентный цвет', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, bounds) {
              void point(Offset local) => update(
                hsv
                    .withSaturation(
                      (local.dx / bounds.maxWidth).clamp(0.0, 1.0),
                    )
                    .withValue((1 - local.dy / 180).clamp(0.0, 1.0)),
              );
              return GestureDetector(
                key: const ValueKey('accent-sv'),
                onPanDown: (details) => point(details.localPosition),
                onPanUpdate: (details) => point(details.localPosition),
                child: SizedBox(
                  height: 180,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white,
                                HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: hsv.saturation * (bounds.maxWidth - 18),
                        top: (1 - hsv.value) * 162,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black54, blurRadius: 2),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          const Text('Оттенок'),
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.red,
                  Colors.yellow,
                  Colors.green,
                  Colors.cyan,
                  Colors.blue,
                  Colors.purple,
                  Colors.red,
                ],
              ),
            ),
            child: Slider(
              key: const ValueKey('accent-hue'),
              min: 0,
              max: 360,
              value: hsv.hue,
              onChanged: (value) => update(hsv.withHue(value)),
            ),
          ),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hsv.toColor(),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: hex,
                  maxLength: 7,
                  decoration: InputDecoration(
                    labelText: 'HEX (#RRGGBB)',
                    errorText: error,
                    counterText: '',
                  ),
                  onChanged: (text) {
                    final raw = text.trim().replaceFirst('#', '');
                    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(raw)) {
                      setState(() {
                        hsv = HSVColor.fromColor(
                          Color(0xFF000000 | int.parse(raw, radix: 16)),
                        );
                        error = null;
                      });
                    } else {
                      setState(() => error = 'Введите 6 символов HEX');
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: error != null
                ? null
                : () => Navigator.pop(context, hsv.toColor().toARGB32()),
            child: const Text('Применить'),
          ),
          TextButton(
            onPressed: () =>
                update(HSVColor.fromColor(const Color(0xFF56DCC6))),
            child: const Text('Вернуть бирюзовый'),
          ),
        ],
      ),
    ),
  );
}
