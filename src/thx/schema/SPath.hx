package thx.schema;

using StringTools;
using thx.Arrays;
using thx.Functions;
import thx.schema.SchemaF.ParseResult;
using thx.schema.SchemaFExtensions;

enum SPathADT {
  Property(name: String, tail: SPath);
  Index(idx: Int, tail: SPath);
  Empty;
}

abstract SPath (SPathADT) from SPathADT to SPathADT {
  public function render(): String return switch this {
    case Property(name, xs):
      if (xs == Empty) name else '${xs.render()}.$name';

    case Index(idx, xs):
      if (xs == Empty) '[$idx]' else '${xs.render()}[$idx]';

    case Empty: "";
  }

  public static var root(get, null): SPath;
  inline static function get_root(): SPath return Empty;

  @:op(A / B)
  public function property(name: String): SPath
    return Property(name, this);

  // fun fact: in haXe, multiplication and division have the same precedence,
  // and always associate to the left. So we can use * for array indexing,
  // and avoid a lot of spurious parentheses when creating complex paths.
  @:op(A * B)
  public function index(idx: Int): SPath
    return Index(idx, this);

  @:op(A + B)
  public function append(other: SPath): SPath return switch this {
    case Property(name, xs): Property(name, xs.append(other));
    case Index(idx, xs): Index(idx, xs.append(other));
    case Empty: this;
  }

  public function reverse(): SPath {
    function go(path: SPath, acc: SPath): SPath {
      return switch path {
        case Property(name, xs): go(xs, Property(name, acc));
        case Index(idx, xs): go(xs, Index(idx, acc));
        case Empty: acc;
      };
    }

    return go(this, Empty);
  }

  public static function parse(s: String): ParseResult<String, String, SPath> {
    var segments = s.split(".");

    return segments.reversed().reduce(
      function(acc: ParseResult<String, String, SPath>, segment: String) {
        return acc.flatMap(parseSegment.bind(segment, _));
      },
      PSuccess(Empty)
    ).map.fn(
      _.reverse()
    );
  }

  static function parseSegment(segment: String, tail: SPath): ParseResult<String, String, SPath> {
    var sr = ~/(?:([^\[\]\s]+)|(?:\[(\d+)\]))(.*)/;
    return if (segment.trim() == "") {
      return PSuccess(tail);
    } else if (sr.match(segment)) {
      if (sr.matched(1) != null) {
        var prop = Property.bind(sr.matched(1), _);
        if (sr.matched(3) != null) {
          parseSegment(sr.matched(3), tail).map(prop);
        } else {
          PSuccess(prop(tail));
        }
      } else if (sr.matched(2) != null) {
        var index = Index.bind(Ints.parse(sr.matched(2)), _);
        if (sr.matched(3) != null) {
          parseSegment(sr.matched(3), tail).map(index);
        } else {
          PSuccess(index(tail));
        }
      } else {
        return PFailure("Path segment did not begin with either a property or index dereference.", segment);
      }
    } else {
      return PFailure("Path segment did not match expected pattern.", segment);
    }
  }
}
