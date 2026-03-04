import 'dart:typed_data';

/// Extension methods for [List] to handle tensor-related operations.
extension ListShape on List<dynamic> {
  /// Reshape list to a another [shape]
  List<dynamic> reshape<T>(List<int> shape) {
    final dims = shape.length;

    if (dims <= 3) {
      switch (dims) {
        case 2:
          return _reshape2<T>(shape);
        case 3:
          return _reshape3<T>(shape);
      }
    }

    // For dims > 3, use generic approach
    var reshapedList = flatten<dynamic>();
    for (var i = dims - 1; i > 0; i--) {
      final temp = <dynamic>[];
      for (
        var start = 0;
        start + shape[i] <= reshapedList.length;
        start += shape[i]
      ) {
        temp.add(reshapedList.sublist(start, start + shape[i]));
      }
      reshapedList = temp;
    }
    return reshapedList;
  }

  List<List<T>> _reshape2<T>(List<int> shape) {
    final flatList = flatten<T>();
    final reshapedList = List<List<T>>.generate(
      shape[0],
      (i) => List.generate(
        shape[1],
        (j) => flatList[i * shape[1] + j],
      ),
    );

    return reshapedList;
  }

  List<List<List<T>>> _reshape3<T>(List<int> shape) {
    final flatList = flatten<T>();
    final reshapedList = List<List<List<T>>>.generate(
      shape[0],
      (i) => List.generate(
        shape[1],
        (j) => List.generate(
          shape[2],
          (k) => flatList[i * shape[1] * shape[2] + j * shape[2] + k],
        ),
      ),
    );

    return reshapedList;
  }

  /// Get shape of the list
  List<int> get shape {
    if (isEmpty) {
      return [];
    }
    var list = this as dynamic;
    final shape = <int>[];
    while (list is List<dynamic>) {
      shape.add(list.length);
      list = list.elementAt(0);
    }
    return shape;
  }

  /// Flatten this list, [T] is element type
  List<T> flatten<T>() {
    final flat = <T>[];
    forEach((e) {
      if (e is List<dynamic>) {
        flat.addAll(e.flatten());
      } else if (e is T) {
        flat.add(e);
      }
    });
    return flat;
  }

  /// Get the element type of a nested list
  dynamic element() {
    var list = this as dynamic;
    while (list is List<dynamic> && !_isTypedList(list)) {
      list = list.elementAt(0);
    }
    return list;
  }

  /// Check if list is a typed list
  bool _isTypedList(dynamic list) {
    return list is Float32List ||
        list is Int64List ||
        list is Int16List ||
        list is Uint8List;
  }
}
