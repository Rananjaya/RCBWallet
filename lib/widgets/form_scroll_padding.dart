import 'package:flutter/widgets.dart';

/// Padding for the scroll view of an add/edit form or a detail screen: the
/// screen's usual [all] on every side, plus the bottom system inset
/// (Android's navigation bar, gesture or three-button).
///
/// A ListView only adds that inset itself when its `padding` is null; these
/// screens set their own padding, so without this the last field, the Save
/// button or the last detail section ends behind the navigation bar when the
/// app draws edge-to-edge (enforced on Android 15+). With the keyboard open
/// the inset is 0: the Scaffold already moves the body above the keyboard, so
/// there's no extra gap.
EdgeInsets formScrollPadding(BuildContext context, {double all = 16}) =>
    EdgeInsets.fromLTRB(all, all, all, all + MediaQuery.paddingOf(context).bottom);
