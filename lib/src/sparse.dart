import 'package:chunked_stream/chunked_stream.dart';

/// Represents a [length]-sized fragment at [offset] in a file.
///
/// [SparseEntry]s can represent either data or holes, and we can easily
/// convert between the two if we know the size of the file, all the sparse
/// data and all the sparse entries combined must give the full size.
class SparseEntry {
  final int offset;
  final int length;

  SparseEntry(this.offset, this.length);

  int get end => offset + length;

  @override
  String toString() => 'offset: $offset, length $length';

  @override
  bool operator ==(Object? other) {
    if (other is! SparseEntry) return false;

    return offset == other.offset && length == other.length;
  }

  @override
  int get hashCode => offset ^ length;
}

/// Generates a stream of the sparse file contents of size [size], given
/// [sparseHoles] and the raw content in [source].
Stream<List<int>> sparseStream(
    Stream<List<int>> source, List<SparseEntry> sparseHoles, int size) {
  if (sparseHoles.isEmpty) {
    return ChunkedStreamIterator(source).substream(size);
  }

  return _sparseStream(source, sparseHoles, size);
}

/// Generates a stream of the sparse file contents of size [size], given
/// [sparseHoles] and the raw content in [source].
///
/// [sparseHoles] has to be non-empty.
Stream<List<int>> _sparseStream(
    Stream<List<int>> source, List<SparseEntry> sparseHoles, int size) async* {
  if (sparseHoles.isEmpty) {
    ArgumentError.value(
        sparseHoles, 'sparseHoles', 'sparseHoles should not be empty!');
  }

  // Current logical position in sparse file.
  var position = 0;

  // Index of the next sparse hole in [sparseHoles] to be processed.
  var sparseHoleIndex = 0;

  // Iterator through [source] to obtain the data bytes.
  final iterator = ChunkedStreamIterator(source);

  while (position < size) {
    // Yield all the necessary sparse holes.
    while (sparseHoleIndex < sparseHoles.length &&
        sparseHoles[sparseHoleIndex].offset == position) {
      final sparseHole = sparseHoles[sparseHoleIndex];
      yield List<int>.filled(sparseHole.length, 0);
      position += sparseHole.length;
      sparseHoleIndex++;
    }

    if (position == size) break;

    /// Yield up to the next sparse hole's offset, or all the way to the end
    /// if there are no sparse holes left.
    var yieldTo = size;
    if (sparseHoleIndex < sparseHoles.length) {
      yieldTo = sparseHoles[sparseHoleIndex].offset;
    }

    yield await iterator.read(yieldTo - position);
    position = yieldTo;
  }
}

/// Reports whether [sparseEntries] is a valid sparse map.
/// It does not matter whether [sparseEntries] represents data fragments or
/// hole fragments.
bool validateSparseEntries(List<SparseEntry> sparseEntries, int size) {
  // Validate all sparse entries. These are the same checks as performed by
  // the BSD tar utility.
  if (size < 0) return false;

  SparseEntry? previous;

  for (final current in sparseEntries) {
    // Negative values are never okay.
    if (current.offset < 0 || current.length < 0) return false;

    // Integer overflow with large length.
    if (current.offset + current.length < current.offset) return false;

    // Region extends beyond the actual size.
    if (current.end > size) return false;

    // Regions cannot overlap and must be in order.
    if (previous != null && previous.end > current.offset) return false;

    previous = current;
  }

  return true;
}

/// Converts a sparse map ([source]) from one form to the other.
/// If the input is sparse holes, then it will output sparse datas and
/// vice-versa. The input must have been already validated.
///
/// This function mutates [source] and returns a normalized map where:
///	* adjacent fragments are coalesced together
///	* only the last fragment may be empty
///	* the endOffset of the last fragment is the total size
List<SparseEntry> invertSparseEntries(List<SparseEntry> source, int size) {
  final result = <SparseEntry>[];
  var previous = SparseEntry(0, 0);
  for (final current in source) {
    /// Skip empty fragments
    if (current.length == 0) continue;

    final newLength = current.offset - previous.offset;
    if (newLength > 0) {
      result.add(SparseEntry(previous.offset, newLength));
    }

    previous = SparseEntry(current.end, 0);
  }
  final lastLength = size - previous.offset;
  result.add(SparseEntry(previous.offset, lastLength));
  return result;
}
