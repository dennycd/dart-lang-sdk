// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart2js.util.setlet;

import 'dart:collection' show SetBase;

class Setlet<E> extends SetBase<E> {
  static const _SetletMarker _MARKER = _SetletMarker();
  static const int CAPACITY = 8;

  // The setlet can be in one of four states:
  //
  //   * Empty          (extra: null,   contents: marker)
  //   * Single element (extra: null,   contents: element)
  //   * List-backed    (extra: length, contents: list)
  //   * Set-backed     (extra: marker, contents: set)
  //
  // When the setlet is list-backed, the list in the contents field
  // may have empty slots filled with the marker value.
  dynamic _contents = _MARKER;
  var _extra;

  Setlet();

  Setlet.of(Iterable<E> elements) {
    addAll(elements);
  }

  static Set<R> _newSet<R>() => Setlet<R>();

  @override
  Set<R> cast<R>() => Set.castFrom<E, R>(this, newSet: _newSet);

  @override
  Iterator<E> get iterator {
    if (_extra == null) {
      return _SetletSingleIterator<E>(_contents);
    } else if (_MARKER == _extra) {
      return _contents.iterator;
    } else {
      return _SetletListIterator<E>(_contents, _extra);
    }
  }

  @override
  int get length {
    if (_extra == null) {
      return (_MARKER == _contents) ? 0 : 1;
    } else if (_MARKER == _extra) {
      return _contents.length;
    } else {
      return _extra;
    }
  }

  @override
  bool get isEmpty {
    if (_extra == null) {
      return _MARKER == _contents;
    } else if (_MARKER == _extra) {
      return _contents.isEmpty;
    } else {
      return _extra == 0;
    }
  }

  @override
  bool contains(Object? element) {
    if (_extra == null) {
      return _contents == element;
    } else if (_MARKER == _extra) {
      return _contents.contains(element);
    } else {
      for (int remaining = _extra, i = 0; remaining > 0 && i < CAPACITY; i++) {
        var candidate = _contents[i];
        if (_MARKER == candidate) continue;
        if (candidate == element) return true;
        remaining--;
      }
      return false;
    }
  }

  @override
  bool add(E element) {
    if (_extra == null) {
      if (_MARKER == _contents) {
        _contents = element;
        return true;
      } else if (_contents == element) {
        // Do nothing.
        return false;
      } else {
        List<Object?> list = List.filled(CAPACITY, null);
        list[0] = _contents;
        list[1] = element;
        _contents = list;
        _extra = 2; // Two elements.
        return true;
      }
    } else if (_MARKER == _extra) {
      return _contents.add(element);
    } else {
      int remaining = _extra;
      int index = 0;
      int copyTo = 0;
      int copyFrom = 0;
      while (remaining > 0 && index < CAPACITY) {
        var candidate = _contents[index++];
        if (_MARKER == candidate) {
          // Keep track of the last range of empty slots in the
          // list. When we're done we'll move all the elements
          // after those empty slots down, so that adding an element
          // after that will preserve the insertion order.
          if (copyFrom == index - 1) {
            copyFrom++;
          } else {
            copyTo = index - 1;
            copyFrom = index;
          }
          continue;
        } else if (candidate == element) {
          return false;
        }
        remaining--;
      }
      if (index < CAPACITY) {
        _contents[index] = element;
        _extra++;
      } else if (_extra < CAPACITY) {
        // Move the last elements down into the last empty slots
        // so that we have empty slots after the last element.
        while (copyFrom < CAPACITY) {
          _contents[copyTo++] = _contents[copyFrom++];
        }
        // Insert the new element as the last element.
        _contents[copyTo++] = element;
        _extra++;
        // Clear all elements after the new last elements to
        // make sure we don't keep extra stuff alive.
        while (copyTo < CAPACITY) _contents[copyTo++] = null;
      } else {
        _contents = Set<E>()
          ..addAll((_contents as List).cast<E>())
          ..add(element);
        _extra = _MARKER;
      }
      return true;
    }
  }

  @override
  void addAll(Iterable<E> elements) {
    elements.forEach((each) => add(each));
  }

  @override
  E? lookup(Object? element) {
    if (_extra == null) {
      return _contents == element ? _contents : null;
    } else if (_MARKER == _extra) {
      return _contents.lookup(element);
    } else {
      for (int remaining = _extra, i = 0; remaining > 0 && i < CAPACITY; i++) {
        var candidate = _contents[i];
        if (_MARKER == candidate) continue;
        if (candidate == element) return candidate;
        remaining--;
      }
      return null;
    }
  }

  @override
  bool remove(Object? element) {
    if (_extra == null) {
      if (_contents == element) {
        _contents = _MARKER;
        return true;
      } else {
        return false;
      }
    } else if (_MARKER == _extra) {
      return _contents.remove(element);
    } else {
      for (int remaining = _extra, i = 0; remaining > 0 && i < CAPACITY; i++) {
        var candidate = _contents[i];
        if (_MARKER == candidate) continue;
        if (candidate == element) {
          _contents[i] = _MARKER;
          _extra--;
          return true;
        }
        remaining--;
      }
      return false;
    }
  }

  @override
  void removeAll(Iterable<Object?> other) {
    other.forEach(remove);
  }

  @override
  void removeWhere(bool test(E element)) {
    if (_extra == null) {
      if (_MARKER != _contents) {
        if (test(_contents)) {
          _contents = _MARKER;
        }
      }
    } else if (_MARKER == _extra) {
      _contents.removeWhere(test);
    } else {
      for (int remaining = _extra, i = 0; remaining > 0 && i < CAPACITY; i++) {
        var candidate = _contents[i];
        if (_MARKER == candidate) continue;
        if (test(candidate)) {
          _contents[i] = _MARKER;
          _extra--;
        }
        remaining--;
      }
    }
  }

  @override
  void retainWhere(bool test(E element)) {
    removeWhere((E element) => !test(element));
  }

  @override
  void retainAll(Iterable<Object?> elements) {
    Set set = elements is Set ? elements : elements.toSet();
    removeWhere((E element) => !set.contains(element));
  }

  @override
  void forEach(void action(E element)) {
    if (_extra == null) {
      if (_MARKER != _contents) action(_contents);
    } else if (_MARKER == _extra) {
      _contents.forEach(action);
    } else {
      for (int remaining = _extra, i = 0; remaining > 0 && i < CAPACITY; i++) {
        var element = _contents[i];
        if (_MARKER == element) continue;
        action(element);
        remaining--;
      }
    }
  }

  @override
  bool containsAll(Iterable<Object?> other) {
    for (final e in other) {
      if (!this.contains(e)) return false;
    }
    return true;
  }

  @override
  clear() {
    _contents = _MARKER;
    _extra = null;
  }

  @override
  Set<E> union(Set<E> other) => Set<E>.from(this)..addAll(other);

  @override
  Setlet<E> intersection(Set<Object?> other) =>
      Setlet.of(this.where((e) => other.contains(e)));

  @override
  Setlet<E> difference(Set<Object?> other) =>
      Setlet.of(this.where((e) => !other.contains(e)));

  @override
  Setlet<E> toSet() {
    Setlet<E> result = Setlet<E>();
    if (_extra == null) {
      result._contents = _contents;
    } else if (_extra == _MARKER) {
      result._extra = _MARKER;
      result._contents = _contents.toSet();
    } else {
      result._extra = _extra;
      result._contents = _contents.toList();
    }
    return result;
  }
}

class _SetletMarker {
  const _SetletMarker();
  @override
  toString() => "-";
}

class _SetletSingleIterator<E> implements Iterator<E> {
  var _element;
  E? _current;
  _SetletSingleIterator(this._element);

  @override
  E get current => _current as E;

  @override
  bool moveNext() {
    if (Setlet._MARKER == _element) {
      _current = null;
      return false;
    }
    _current = _element;
    _element = Setlet._MARKER;
    return true;
  }
}

class _SetletListIterator<E> implements Iterator<E> {
  final List _list;
  int _remaining;
  int _index = 0;
  E? _current;
  _SetletListIterator(this._list, this._remaining);

  @override
  E get current => _current as E;

  @override
  bool moveNext() {
    while (_remaining > 0) {
      var candidate = _list[_index++];
      if (Setlet._MARKER != candidate) {
        _current = candidate;
        _remaining--;
        return true;
      }
    }
    _current = null;
    return false;
  }
}
