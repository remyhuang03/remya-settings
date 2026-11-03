import 'dart:math' as math;

import 'package:croppy/croppy.dart';
import 'package:material_ui/material_ui.dart';

/// The package owns crop geometry and bounds for every input method.
class AvatarCropController extends CroppableImageControllerWithMixins {
  AvatarCropController({required super.imageProvider, required Size imageSize})
    : super(
        data:
            CroppableImageData.initialWithCropPathFn(
              imageSize: imageSize,
              cropPathFn: aabbCropShapeFn,
            ).copyWith(
              cropRect: Rect.fromCenter(
                center: Offset(imageSize.width / 2, imageSize.height / 2),
                width: math.min(imageSize.width, imageSize.height),
                height: math.min(imageSize.width, imageSize.height),
              ),
            ),
        enabledTransformations: const [Transformation.panAndScale],
        minimumCropDimension: math.min(imageSize.width, imageSize.height) / 8,
      ) {
    // Use the package's Dart solver consistently on desktop and in widget tests.
    croppyForceUseCassowaryDartImpl = true;
    aspectRatioNotifier.value = allowedAspectRatios.single;
  }

  @override
  List<CropAspectRatio?> get allowedAspectRatios => const [
    CropAspectRatio(width: 1, height: 1),
  ];

  double get zoom =>
      math.min(data.imageSize.width, data.imageSize.height) /
      data.cropRect.width;

  @override
  void onPanAndScale({
    required double scaleDelta,
    required Offset offsetDelta,
  }) {
    super.onPanAndScale(
      scaleDelta: (zoom * scaleDelta).clamp(1, 8) / zoom,
      offsetDelta: offsetDelta,
    );
    normalize();
    setViewportScale();
  }

  void setZoom(double value) {
    final ownGesture = !isPanAndScaling;
    if (ownGesture && !onPanAndScaleStart()) return;
    onPanAndScale(scaleDelta: value / zoom, offsetDelta: .zero);
    if (ownGesture) onPanAndScaleEnd();
  }

  Map<String, double> get normalizedCrop => {
    'left': (data.cropRect.left / data.imageSize.width).clamp(0, 1),
    'top': (data.cropRect.top / data.imageSize.height).clamp(0, 1),
    'right': (data.cropRect.right / data.imageSize.width).clamp(0, 1),
    'bottom': (data.cropRect.bottom / data.imageSize.height).clamp(0, 1),
  };
}
