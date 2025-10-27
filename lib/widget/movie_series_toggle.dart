import 'package:flutter/material.dart';

class MovieSeriesToggle extends StatelessWidget {
  final bool isMovieMode;
  final Function(bool) onToggle;

  const MovieSeriesToggle({
    Key? key,
    required this.isMovieMode,
    required this.onToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        color: Colors.white.withOpacity(0.1),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildToggleButton(
            label: 'Movies',
            isSelected: isMovieMode,
            onTap: () => onToggle(true),
          ),
          _buildToggleButton(
            label: 'Series',
            isSelected: !isMovieMode,
            onTap: () => onToggle(false),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: 115,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.white.withOpacity(0.3) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

