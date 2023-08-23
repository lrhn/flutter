// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/rendering.dart';

/// An [Invocation] and the [stack] trace that led to it.
///
/// Used by [TestRecordingCanvas] to trace canvas calls.
class RecordedInvocation {
  /// Create a record for an invocation list.
  const RecordedInvocation(this.invocation, { required this.stack });

  /// The method that was called and its arguments.
  ///
  /// The arguments preserve identity, but not value. Thus, if two invocations
  /// were made with the same [Paint] object, but with that object configured
  /// differently each time, then they will both have the same object as their
  /// argument, and inspecting that object will return the object's current
  /// values (mostly likely those passed to the second call).
  final Invocation invocation;

  /// The stack trace at the time of the method call.
  final StackTrace stack;

  @override
  String toString() => _describeInvocation(invocation);

  /// Converts [stack] to a string using the [FlutterError.defaultStackFilter]
  /// logic.
  String stackToString({ String indent = '' }) {
    return indent + FlutterError.defaultStackFilter(
      stack.toString().trimRight().split('\n'),
    ).join('\n$indent');
  }
}

// Examples can assume:
// late WidgetTester tester;

/// A [Canvas] for tests that records its method calls.
///
/// This class can be used in conjunction with [TestRecordingPaintingContext]
/// to record the [Canvas] method calls made by a renderer. For example:
///
/// ```dart
/// RenderBox box = tester.renderObject(find.text('ABC'));
/// TestRecordingCanvas canvas = TestRecordingCanvas();
/// TestRecordingPaintingContext context = TestRecordingPaintingContext(canvas);
/// box.paint(context, Offset.zero);
/// // Now test the expected canvas.invocations.
/// ```
///
/// In some cases it may be useful to define a subclass that overrides the
/// [Canvas] methods the test is checking and squirrels away the parameters
/// that the test requires.
///
/// For simple tests, consider using the [paints] matcher, which overlays a
/// pattern matching API over [TestRecordingCanvas].
class TestRecordingCanvas implements Canvas {
  /// All of the method calls on this canvas.
  final List<RecordedInvocation> invocations = <RecordedInvocation>[];

  int _saveCount = 0;

  @override
  int getSaveCount() => _saveCount;

  @override
  void save() {
    _saveCount += 1;
    invocations.add(RecordedInvocation(Invocation.method(#save), stack: StackTrace.current));
  }

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    _saveCount += 1;
    invocations.add(RecordedInvocation(Invocation.method(#saveLayer, <dynamic>[bounds, paint]), stack: StackTrace.current));
  }

  @override
  void restore() {
    _saveCount -= 1;
    assert(_saveCount >= 0);
    invocations.add(RecordedInvocation(Invocation.method(#restore), stack: StackTrace.current));
  }

  @override
  void noSuchMethod(Invocation invocation) {
    assert(_symbolNames.containsKey(invocation.memberName));
    invocations.add(RecordedInvocation(invocation, stack: StackTrace.current));
  }
}

/// A [PaintingContext] for tests that use [TestRecordingCanvas].
class TestRecordingPaintingContext extends ClipContext implements PaintingContext {
  /// Creates a [PaintingContext] for tests that use [TestRecordingCanvas].
  TestRecordingPaintingContext(this.canvas);

  @override
  final Canvas canvas;

  @override
  void paintChild(RenderObject child, Offset offset) {
    child.paint(this, offset);
  }

  @override
  ClipRectLayer? pushClipRect(
    bool needsCompositing,
    Offset offset,
    Rect clipRect,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.hardEdge,
    ClipRectLayer? oldLayer,
  }) {
    clipRectAndPaint(clipRect.shift(offset), clipBehavior, clipRect.shift(offset), () => painter(this, offset));
    return null;
  }

  @override
  ClipRRectLayer? pushClipRRect(
    bool needsCompositing,
    Offset offset,
    Rect bounds,
    RRect clipRRect,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.antiAlias,
    ClipRRectLayer? oldLayer,
  }) {
    clipRRectAndPaint(clipRRect.shift(offset), clipBehavior, bounds.shift(offset), () => painter(this, offset));
    return null;
  }

  @override
  ClipPathLayer? pushClipPath(
    bool needsCompositing,
    Offset offset,
    Rect bounds,
    Path clipPath,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.antiAlias,
    ClipPathLayer? oldLayer,
  }) {
    clipPathAndPaint(clipPath.shift(offset), clipBehavior, bounds.shift(offset), () => painter(this, offset));
    return null;
  }

  @override
  TransformLayer? pushTransform(
    bool needsCompositing,
    Offset offset,
    Matrix4 transform,
    PaintingContextCallback painter, {
    TransformLayer? oldLayer,
  }) {
    canvas.save();
    canvas.transform(transform.storage);
    painter(this, offset);
    canvas.restore();
    return null;
  }

  @override
  OpacityLayer pushOpacity(
    Offset offset,
    int alpha,
    PaintingContextCallback painter, {
    OpacityLayer? oldLayer,
  }) {
    canvas.saveLayer(null, Paint()); // TODO(ianh): Expose the alpha somewhere.
    painter(this, offset);
    canvas.restore();
    return OpacityLayer();
  }

  @override
  void pushLayer(
    Layer childLayer,
    PaintingContextCallback painter,
    Offset offset, {
    Rect? childPaintBounds,
  }) {
    painter(this, offset);
  }

  @override
  VoidCallback addCompositionCallback(CompositionCallback callback) => () {};

  @override
  void noSuchMethod(Invocation invocation) { }
}

String _valueName(Object? value) {
  if (value is double) {
    return value.toStringAsFixed(1);
  }
  return value.toString();
}

String _symbolName(Symbol symbol) => _symbolNames[symbol] ??
    throw UnsupportedError('Only members of Canvas supported');

String _describeInvocation(Invocation call) {
  final StringBuffer buffer = StringBuffer();
  buffer.write(_symbolName(call.memberName));
  if (call.isSetter) {
    buffer.write(call.positionalArguments[0].toString());
  } else if (call.isMethod) {
    buffer.write('(');
    buffer.writeAll(call.positionalArguments.map<String>(_valueName), ', ');
    String separator = call.positionalArguments.isEmpty ? '' : ', ';
    call.namedArguments.forEach((Symbol name, Object? value) {
      buffer.write(separator);
      buffer.write(_symbolName(name));
      buffer.write(': ');
      buffer.write(_valueName(value));
      separator = ', ';
    });
    buffer.write(')');
  }
  return buffer.toString();
}

const _symbolNames = {
  #clipOp: 'clipOp',
  #clipPath: 'clipPath',
  #clipRRect: 'clipRRect',
  #clipRect: 'clipRect',
  #doAntiAlias: 'doAntiAlias',
  #drawArc: 'drawArc',
  #drawAtlas: 'drawAtlas',
  #drawCircle: 'drawCircle',
  #drawColor: 'drawColor',
  #drawDRRect: 'drawDRRect',
  #drawImage: 'drawImage',
  #drawImageNine: 'drawImageNine',
  #drawImageRect: 'drawImageRect',
  #drawLine: 'drawLine',
  #drawOval: 'drawOval',
  #drawPaint: 'drawPaint',
  #drawParagraph: 'drawParagraph',
  #drawPath: 'drawPath',
  #drawPicture: 'drawPicture',
  #drawPoints: 'drawPoints',
  #drawRRect: 'drawRRect',
  #drawRawAtlas: 'drawRawAtlas',
  #drawRawPoints: 'drawRawPoints',
  #drawRect: 'drawRect',
  #drawShadow: 'drawShadow',
  #drawVertices: 'drawVertices',
  #getDestinationClipBounds: 'getDestinationClipBounds',
  #getLocalClipBounds: 'getLocalClipBounds',
  #getSaveCount: 'getSaveCount',
  #getTransform: 'getTransform',
  #intersect: 'intersect',
  #restore: 'restore',
  #restoreToCount: 'restoreToCount',
  #rotate: 'rotate',
  #rue: 'rue',
  #save: 'save',
  #saveLayer: 'saveLayer',
  #scale: 'scale',
  #skew: 'skew',
  #transform: 'transform',
  #translate: 'translate',
};
