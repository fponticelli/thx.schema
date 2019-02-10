package thx.schema.macro;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.ComplexTypeTools;
import thx.schema.macro.Error.*;

class Utils {
  public static function extractTypeNameFromKind(s: String): String {
    if(s.substring(0, 1) == "{") {
      return s;
    } else {
      var pattern = ~/^(?:Enum|Class|Abstract)[<](.+)[>]$/;
      return if(pattern.match(s)) {
        pattern.matched(1);
      } else {
        fatal("Unable to extract type name from kind: " + s);
      }
    }
  }

  public static function createRef<T>(t: T): Ref<T> {
    return {
      get: function (): T {
        return t;
      },
      toString: function (): String {
        return Std.string(t);
      }
    };
  }

  public static function paramAsComplexType(p: String): ComplexType {
    return TPath({
      pack: [],
      name: p,
      params: []
    });
  }

  public static function paramAsType(p: String): Type {
    var ct = paramAsComplexType(p);
    return TInst(createRef({
      module: "M",
      init: null,
      kind: KTypeParameter([]),
      meta: null,
      name: p,
      pack: [],
      interfaces: [],
      params: [],
      doc: null,
      pos: Context.currentPos(),
      fields: createRef([]),
      statics: createRef([]),
      isFinal: false,
      isPrivate: false,
      constructor: null,
      isInterface: false,
      isExtern: false,
      superClass: null,
      exclude: function() {},
      overrides: null
    }), []);
  }

  public static function keepVariables(f: ClassField): Bool {
    return switch f.kind {
      case FVar(AccCall, AccCall): f.meta.has(":isVar");
      case FVar(AccCall, _): true;
      case FVar(AccNormal, _) | FVar(AccNo, _): true;
      case _: false;
    }
  }

  public static function createExpressionFromDef(e: ExprDef) {
    return {
      expr: e,
      pos: Context.currentPos()
    };
  }
}
