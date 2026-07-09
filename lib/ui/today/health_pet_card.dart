import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

import '../../models/payloads.dart';
import '../design/design.dart';

class HealthPetCard extends StatefulWidget {
  final TodayData today;
  const HealthPetCard({super.key, required this.today});

  @override
  State<HealthPetCard> createState() => _HealthPetCardState();
}

class _HealthPetCardState extends State<HealthPetCard> {
  StateMachineController? _controller;
  SMITrigger? _successTrigger;
  SMITrigger? _failTrigger;
  SMIBool? _isHandsUp;

  void _onRiveInit(Artboard artboard) {
    _controller = StateMachineController.fromArtboard(artboard, 'Login Machine');
    if (_controller != null) {
      artboard.addController(_controller!);
      _successTrigger = _controller!.findInput<bool>('trigSuccess') as SMITrigger?;
      _failTrigger = _controller!.findInput<bool>('trigFail') as SMITrigger?;
      _isHandsUp = _controller!.findInput<bool>('isHandsUp') as SMIBool?;
      
      _reactToRecovery();
    }
  }

  void _reactToRecovery() {
    if (!mounted) return;
    
    final recovery = widget.today.recovery.value;
    
    if (recovery == null) {
      _isHandsUp?.value = false;
    } else if (recovery > 66) {
      _isHandsUp?.value = false;
      _successTrigger?.fire();
    } else if (recovery < 33) {
      _isHandsUp?.value = false;
      _failTrigger?.fire();
    } else {
      _isHandsUp?.value = false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(Sp.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(OsIcon.heartRate, color: AppColors.accent),
              const SizedBox(width: Sp.x2),
              Text('Your Health Pet', style: AppText.body),
            ],
          ),
          const SizedBox(height: Sp.x2),
          Text(
            'Hit your recovery goals to keep your pet happy!',
            style: AppText.captionMuted,
          ),
          const SizedBox(height: Sp.x4),
          SizedBox(
            height: 200,
            width: double.infinity,
            child: RiveAnimation.asset(
              'assets/login-teddy.riv',
              fit: BoxFit.contain,
              onInit: _onRiveInit,
            ),
          ),
          const SizedBox(height: Sp.x4),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () => _reactToRecovery(),
              child: const Text('Pet the bear'),
            ),
          ),
        ],
      ),
    );
  }
}
