import 'dart:async';

import 'package:meta/meta.dart';

import 'constants.dart';
import 'header.dart';

/// An entry in a tar file.
///
/// Usually, tar entries are read from a stream, and they're bound to the stream
/// from which they've been read. This means that they can only be read once,
/// and that only one [TarEntry] is active at a time.
@sealed
class TarEntry {
  /// The parsed [TarHeader] of this tar entry.
  final TarHeader header;

  /// The content stream of the active tar entry.
  ///
  /// This is a single-subscription stream backed by the original stream used to
  /// create a tar reader.
  /// When listening on [contents], the stream needs to be fully drained before
  /// the next call to [StreamIterator.next]. It's acceptable to not listen to
  /// [contents] at all before calling [StreamIterator.next] again. In that
  /// case, this library will take care of draining the stream to get to the
  /// next entry.
  final Stream<List<int>> contents;

  /// The name of this entry, as indicated in the header or a previous pax
  /// entry.
  String get name => header.name;

  /// The type of tar entry (file, directory, etc.).
  TypeFlag get type => header.typeFlag;

  /// The content size of this entry, in bytes.
  int get size => header.size;

  /// Time of the last modification of this file, as indicated in the [header].
  DateTime get modified => header.modified;

  TarEntry(this.header, this.contents);

  /// Creates an in-memory tar entry from the [header] and the [data] to store.
  factory TarEntry.data(TarHeader header, List<int> data) {
    return TarEntry(header, Stream.value(data));
  }
}
