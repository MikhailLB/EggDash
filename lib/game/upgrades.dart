import 'package:flutter/material.dart';

enum UpgradeId {
  basketSize,
  moveSpeed,
  maxLives,
  coinBonus,
  magnet,
  shield,
  goldenLuck,
  slowStart,
}

class UpgradeDef {
  final UpgradeId id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final int maxLevel;
  final int baseCost;
  final double costGrowth;

  const UpgradeDef({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.maxLevel,
    required this.baseCost,
    required this.costGrowth,
  });

  int costForLevel(int currentLevel) {
    var r = 1.0;
    for (var i = 0; i < currentLevel; i++) {
      r *= costGrowth;
    }
    return (baseCost * r).round();
  }
}

const List<UpgradeDef> allUpgrades = [
  UpgradeDef(
    id: UpgradeId.basketSize,
    name: 'Big Basket',
    description: 'Wider basket — catch eggs more easily.',
    icon: Icons.shopping_basket,
    color: Color(0xFFFFB300),
    maxLevel: 5,
    baseCost: 60,
    costGrowth: 1.8,
  ),
  UpgradeDef(
    id: UpgradeId.moveSpeed,
    name: 'Quick Hands',
    description: 'The basket follows your finger faster.',
    icon: Icons.speed,
    color: Color(0xFF42A5F5),
    maxLevel: 5,
    baseCost: 50,
    costGrowth: 1.7,
  ),
  UpgradeDef(
    id: UpgradeId.maxLives,
    name: 'Extra Heart',
    description: 'Start each run with one more life.',
    icon: Icons.favorite,
    color: Color(0xFFEF5350),
    maxLevel: 4,
    baseCost: 120,
    costGrowth: 2.2,
  ),
  UpgradeDef(
    id: UpgradeId.coinBonus,
    name: 'Golden Touch',
    description: 'Earn more coins from every egg.',
    icon: Icons.monetization_on,
    color: Color(0xFFFFD54F),
    maxLevel: 5,
    baseCost: 80,
    costGrowth: 1.9,
  ),
  UpgradeDef(
    id: UpgradeId.magnet,
    name: 'Egg Magnet',
    description: 'Good eggs drift toward the basket.',
    icon: Icons.adjust,
    color: Color(0xFFAB47BC),
    maxLevel: 4,
    baseCost: 140,
    costGrowth: 2.0,
  ),
  UpgradeDef(
    id: UpgradeId.shield,
    name: 'Egg Shield',
    description: 'Start with shields that absorb one mistake each.',
    icon: Icons.shield,
    color: Color(0xFF26C6DA),
    maxLevel: 3,
    baseCost: 160,
    costGrowth: 2.4,
  ),
  UpgradeDef(
    id: UpgradeId.goldenLuck,
    name: 'Lucky Hen',
    description: 'Chickens lay more golden eggs.',
    icon: Icons.auto_awesome,
    color: Color(0xFFFFA726),
    maxLevel: 4,
    baseCost: 110,
    costGrowth: 2.0,
  ),
  UpgradeDef(
    id: UpgradeId.slowStart,
    name: 'Calm Start',
    description: 'Eggs fall slower for the first seconds of a run.',
    icon: Icons.hourglass_bottom,
    color: Color(0xFF66BB6A),
    maxLevel: 3,
    baseCost: 70,
    costGrowth: 1.8,
  ),
];

UpgradeDef upgradeDef(UpgradeId id) =>
    allUpgrades.firstWhere((u) => u.id == id);

class UpgradeState {
  final Map<UpgradeId, int> levels;
  UpgradeState(this.levels);

  factory UpgradeState.empty() =>
      UpgradeState({for (final u in allUpgrades) u.id: 0});

  int levelOf(UpgradeId id) => levels[id] ?? 0;

  double get basketWidthMul => 1.0 + levelOf(UpgradeId.basketSize) * 0.12;
  double get moveResponse => 10.0 + levelOf(UpgradeId.moveSpeed) * 3.5;
  int get extraLives => levelOf(UpgradeId.maxLives);
  double get coinMul => 1.0 + levelOf(UpgradeId.coinBonus) * 0.15;
  double get magnetStrength => levelOf(UpgradeId.magnet) * 70.0;
  double get magnetRadius => levelOf(UpgradeId.magnet) == 0 ? 0 : 90.0;
  int get startShields => levelOf(UpgradeId.shield);
  double get goldenBonus => levelOf(UpgradeId.goldenLuck) * 0.05;
  double get slowStartDuration => levelOf(UpgradeId.slowStart) * 2.5;
}
