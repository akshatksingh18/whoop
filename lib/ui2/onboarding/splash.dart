// The cold-start cover.
//
// AppState's init (SQLite open, migrations, first derive check) is the slow
// part of a launch and it happens before anything can be drawn honestly. This
// covers exactly that window and cross-fades out the instant the gate leaves
// `loading` — mid-play if need be. Shown once per launch; it latches itself
// off afterwards so a later rebuild never re-covers a running app.
//
// The video is decoration and is treated as such: if it fails to initialise
// (test harness, codec, missing asset) the cover is the mark on the page
// background and the launch is otherwise identical.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../ui2.dart';

class BootSplash extends StatefulWidget {
  /// True once the app behind the cover is ready to be looked at.
  final bool ready;
  final Widget child;

  const BootSplash({super.key, required this.ready, required this.child});

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash> {
  VideoPlayerController? _video;

  /// Latched once the cover has faded. A splash that can come back is a splash
  /// that will come back at the worst possible moment.
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    final v = VideoPlayerController.asset('assets/splash/splashscreen.mp4');
    v.initialize().then((_) {
      if (!mounted) {
        v.dispose();
        return;
      }
      v.play();
      setState(() => _video = v);
    }).catchError((Object _) {
      v.dispose();
      // No video — the mark on the page background is the cover.
    });
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    if (_gone) return widget.child;
    // Reduced motion has no fade to hide behind, so the cover simply stops
    // existing the moment the app is ready.
    if (widget.ready && !Motion.enabled(c)) return widget.child;
    return Stack(children: [
      widget.child,
      Positioned.fill(
        // `IgnorePointer` blocks touch and NOT semantics, so while the user saw
        // only the splash a screen reader was walking the whole live app
        // underneath it. `BlockSemantics` is the half that was missing.
        child: BlockSemantics(
          child: IgnorePointer(
            ignoring: widget.ready,
            child: AnimatedOpacity(
              opacity: widget.ready ? 0 : 1,
              duration: motion(c, Motion.slow),
              onEnd: () {
                if (widget.ready && mounted) setState(() => _gone = true);
              },
              child: _Cover(video: _video),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Cover extends StatelessWidget {
  final VideoPlayerController? video;
  const _Cover({this.video});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final v = video;
    return ColoredBox(
      color: p.bg,
      child: Center(
        child: v != null && v.value.isInitialized
            ? AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.activity, size: 44, color: p.on(C.green)),
                const SizedBox(height: S.x4),
                Text('OpenStrap', style: F.t2.copyWith(color: p.ink)),
              ]),
      ),
    );
  }
}
