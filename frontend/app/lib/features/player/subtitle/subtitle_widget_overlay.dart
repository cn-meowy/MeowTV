import 'package:flutter/material.dart';
import 'subtitle_model.dart';
import 'subtitle_manager.dart';

class SubtitleWidgetOverlay extends StatelessWidget {
  final SubtitleManager manager;
  final Duration position;

  const SubtitleWidgetOverlay({super.key, required this.manager, required this.position});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final cues = manager.getActiveCues(position);
        if (cues.isEmpty) return const SizedBox.shrink();
        return Positioned(
          left: 0, right: 0, bottom: 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: cues.map((cue) => _buildCueText(cue)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildCueText(SubtitleCue cue) {
    final style = cue.style ?? const SubtitleStyle.defaults();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
        child: Text(cue.text, textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(style.color ?? 0xFFFFFFFF),
            fontSize: (style.fontSize ?? 25).toDouble(),
            fontWeight: style.bold == true ? FontWeight.bold : FontWeight.normal,
            fontStyle: style.italic == true ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }
}
