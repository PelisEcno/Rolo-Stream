import 'package:flutter/material.dart';

/// Avatares disponibles para un perfil. Se guarda el índice, así que solo se añaden al final.
const kProfileAvatars = <({IconData icon, Color from, Color to})>[
  (icon: Icons.local_fire_department_rounded, from: Color(0xFFFF8A00), to: Color(0xFFE50914)),
  (icon: Icons.rocket_launch_rounded, from: Color(0xFF7C3AED), to: Color(0xFF312E81)),
  (icon: Icons.pets_rounded, from: Color(0xFF14B8A6), to: Color(0xFF0F766E)),
  (icon: Icons.auto_awesome_rounded, from: Color(0xFFF472B6), to: Color(0xFF9D174D)),
  (icon: Icons.sports_esports_rounded, from: Color(0xFF38BDF8), to: Color(0xFF1D4ED8)),
  (icon: Icons.bolt_rounded, from: Color(0xFFFACC15), to: Color(0xFFCA8A04)),
  (icon: Icons.nightlight_round, from: Color(0xFF64748B), to: Color(0xFF1E293B)),
  (icon: Icons.favorite_rounded, from: Color(0xFFFB7185), to: Color(0xFFBE123C)),
];

class ProfileAvatar extends StatelessWidget {
  final int avatar;
  final double size;
  const ProfileAvatar({super.key, required this.avatar, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final a = kProfileAvatars[avatar.clamp(0, kProfileAvatars.length - 1)];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a.from, a.to],
        ),
      ),
      child: Icon(a.icon, size: size * 0.5, color: Colors.white),
    );
  }
}
