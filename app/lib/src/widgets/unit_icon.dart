import 'package:flutter/material.dart';

import '../theme.dart';

/// A picture of the machine when the app has one for this model code,
/// otherwise the code on an orange tile.
class UnitIcon extends StatelessWidget {
  const UnitIcon({super.key, required this.unitId, this.width = 82, this.height = 56});

  /// The unit folder name, like PC500LC-10.
  final String unitId;
  final double width;
  final double height;

  /// Letters and the first number of the unit id, which picks the picture:
  /// PC500-10 and PC500LC-10 are both a PC500.
  static String modelCode(String unitId) =>
      RegExp(r'^[A-Z]+[-_ ]?\d+').firstMatch(unitId.toUpperCase())?[0]?.replaceAll(RegExp(r'[-_ ]'), '') ?? '';

  /// Shown on the tile when there is no picture.
  static String shortCode(String unitId) {
    final code = unitId.split(RegExp(r'[-_ ]')).first.toUpperCase();
    return code.length > 7 ? code.substring(0, 7) : code;
  }

  /// Model codes with a picture in `assets/units/<model>.png`.
  static const pictures = {'PC2000', 'PC1250', 'PC500', 'PC210', 'CAT395', 'D375', 'D155', 'D85'};

  @override
  Widget build(BuildContext context) {
    final model = modelCode(unitId);
    if (pictures.contains(model)) {
      return SizedBox(
        width: width,
        height: height,
        child: Image.asset('assets/units/${model.toLowerCase()}.png', fit: BoxFit.contain),
      );
    }
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(14)),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          shortCode(unitId),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.orangeText),
        ),
      ),
    );
  }
}

/// A machine picture standing on a light grey tile with a soft shadow under
/// its tracks, so pictures of different sizes look alike in lists.
class PictureStage extends StatelessWidget {
  const PictureStage({super.key, required this.child, this.width = 112, this.height = 76});

  final Widget child;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: width * 0.16,
            right: width * 0.16,
            bottom: height * 0.09,
            child: Container(
              height: 8,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.elliptical(60, 4)),
                boxShadow: [BoxShadow(color: Color(0x29101828), blurRadius: 5)],
              ),
            ),
          ),
          Padding(padding: EdgeInsets.only(bottom: height * 0.1), child: child),
        ],
      ),
    );
  }
}
