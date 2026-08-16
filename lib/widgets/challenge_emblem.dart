import 'package:flutter/material.dart';

import 'badge_icon.dart';

/// Preset icons a challenge's emblem is randomly picked from at creation.
const challengeEmblemIcons = [
  Icons.emoji_events,
  Icons.military_tech,
  Icons.workspace_premium,
  Icons.local_fire_department,
  Icons.bolt,
  Icons.star,
  Icons.rocket_launch,
  Icons.shield,
  Icons.diamond,
  Icons.whatshot,
];

/// A challenge's cosmetic emblem - a random icon/color pair assigned once at
/// creation, shown wherever the challenge is listed. Purely decorative, not
/// tied to progress or completion (unlike [BadgeIcon]).
class ChallengeEmblem extends StatelessWidget {
  final int iconIndex;
  final int colorIndex;
  final double size;

  const ChallengeEmblem({
    super.key,
    required this.iconIndex,
    required this.colorIndex,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final icon = challengeEmblemIcons[iconIndex % challengeEmblemIcons.length];
    final (background, foreground) = badgeColors[colorIndex % badgeColors.length];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background.shade100, shape: BoxShape.circle),
      child: Icon(icon, color: foreground, size: size * 0.55),
    );
  }
}
