import 'package:freezed_annotation/freezed_annotation.dart';

part 'tuple.freezed.dart';

/// Represents a 2-tuple, or pair.
@freezed
abstract class Tuple2<T1, T2> with _$Tuple2<T1, T2> {
  /// Returns the first item of the tuple
  //final T1 item1;

  /// Returns the second item of the tuple
  //final T2 item2;

  const Tuple2._();

  /// Creates a new tuple value with the specified items.
  const factory Tuple2(T1 item1, T2 item2) = _Tuple2;

  /// Returns a tuple with the first item set to the specified value.
  //Tuple2<T1, T2> withItem1(T1 v) => Tuple2<T1, T2>(item1: v, item2: item2);

  /// Returns a tuple with the second item set to the specified value.
  //Tuple2<T1, T2> withItem2(T2 v) => Tuple2<T1, T2>(item1: item1, item2: v);

  /// Creates a [List] containing the items of this [Tuple2].
  ///
  /// The elements are in item order. The list is variable-length
  /// if [growable] is true.
  List toList({bool growable = false}) => List.from([item1, item2], growable: growable);

  @override
  String toString() => '[$item1, $item2]';
}

/// Represents a 3-tuple, or triple.
@freezed
abstract class Tuple3<T1, T2, T3> with _$Tuple3<T1, T2, T3> {
  const Tuple3._();

  const factory Tuple3(T1 item1, T2 item2, T3 item3) = _Tuple3;

  /// Creates a [List] containing the items of this [Tuple3].
  ///
  /// The elements are in item order. The list is variable-length
  /// if [growable] is true.
  List toList({bool growable = false}) => List.from([item1, item2, item3], growable: growable);

  @override
  String toString() => '[$item1, $item2, $item3]';
}

/// Represents a 4-tuple, or triple.
@freezed
abstract class Tuple4<T1, T2, T3, T4> with _$Tuple4<T1, T2, T3, T4> {
  const Tuple4._();

  const factory Tuple4(T1 item1, T2 item2, T3 item3, T4 item4) = _Tuple4;

  /// Creates a [List] containing the items of this [Tuple4].
  ///
  /// The elements are in item order. The list is variable-length
  /// if [growable] is true.
  List toList({bool growable = false}) => List.from([item1, item2, item3, item4], growable: growable);

  @override
  String toString() => '[$item1, $item2, $item3, $item4]';
}

/// Represents a 5-tuple, or triple.
@freezed
abstract class Tuple5<T1, T2, T3, T4, T5> with _$Tuple5<T1, T2, T3, T4, T5> {
  const Tuple5._();

  const factory Tuple5(T1 item1, T2 item2, T3 item3, T4 item4, T5 item5) = _Tuple5;

  /// Creates a [List] containing the items of this [Tuple4].
  ///
  /// The elements are in item order. The list is variable-length
  /// if [growable] is true.
  List toList({bool growable = false}) => List.from([item1, item2, item3, item4, item5], growable: growable);

  @override
  String toString() => '[$item1, $item2, $item3, $item4, $item5]';
}
