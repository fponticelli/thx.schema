package thx.schema;

import haxe.ds.Option;
import thx.schema.SPath;

import thx.Objects;
import thx.Nel;
import thx.Validation;
import thx.Validation.*;
import thx.Types;
import thx.Unit;
import thx.fp.Dynamics;
import thx.fp.Dynamics.*;
import thx.fp.Functions.*;

using thx.Arrays;
using thx.Eithers;
using thx.Functions;
using thx.Maps;
using thx.Options;
using thx.Validation.ValidationExtensions;

import thx.schema.Schema;
import thx.schema.SchemaDSL.*;
using thx.schema.SchemaExtensions;

class SchemaDynamicExtensions {
  public static function parse<A>(schema: Schema<A>, v: Dynamic): VNel<ParseError, A> {
    return parse0(schema, v, SPath.root);
  }

  private static function parse0<A>(schema: Schema<A>, v: Dynamic, path: SPath): VNel<ParseError, A> {
    return switch schema {
      case IntSchema:   parseInt(v).leftMapNel(errAt(path));
      case FloatSchema: parseFloat(v).leftMapNel(errAt(path));
      case StrSchema:   parseString(v).leftMapNel(errAt(path));
      case BoolSchema:  parseBool(v).leftMapNel(errAt(path));
      case UnitSchema:  successNel(unit);

      case ObjectSchema(propSchema): parseObject(propSchema, v, path);
      case ArraySchema(elemSchema):  parseArrayIndexed(v, function(v, i) return parse0(elemSchema, v, path * i), errAt(path));

      case OneOfSchema(alternatives):
        // The alternative is encoded as an object containing single field, where the
        // name of the field is the constructor and the body is parsed by the schema
        // for that alternative.
        if (Types.isAnonymousObject(v)) {
          var fields = Objects.fields(v);
          var alts = fields.flatMap(function(name) return alternatives.filter.fn(_.id() == name));

          switch alts {
            case [Prism(id, base, f, g)]:
              var parser = if (isConstant(base)) parseNullableProperty else parseProperty.bind(_, _, _, ParseError.new.bind(_, path));
              parser(v, id, parse0.bind(base, _, path / id)).map(f);

            case other:
              if (other.length == 0) {
                fail('Could not match type identifier from among ${alternatives.map.fn(_.id())} in object with fields $fields.', path);
              } else {
                // throw here, because this is a programmer error, not a user error.
                throw new thx.Error('More than one alternative bound to the same schema at path ${path.toString()}!');
              }
          };
        } else {
          fail('$v is not an anonymous object structure, as required for the representation of values of "oneOf" type.', path);
        };

      case IsoSchema(base, f, _): 
        parse0(base, v, path).map(f);
    };
  }

  private static function parseObject<O, A>(builder: ObjectBuilder<O, A>, v: Dynamic, path: SPath): VNel<ParseError, A> {
    // helper function used to unpack existential type I
    inline function go<I>(schema: PropSchema<O, I>, k: ObjectBuilder<O, I -> A>): VNel<ParseError, A> {
      var parsedOpt: VNel<ParseError, I> = switch schema {
        case Required(fieldName, valueSchema, _):
          parseOptionalProperty(v, fieldName, parse0.bind(valueSchema, _, path / fieldName)).flatMapV.fn(
            _.toSuccessNel(new ParseError('Value $v does not contain field $fieldName and no default was available.', path))
          );

        case Optional(fieldName, valueSchema, _):
          parseOptionalProperty(v, fieldName, parse0.bind(valueSchema, _, path / fieldName));
      };

      return parsedOpt.ap(parseObject(k, v, path), Nel.semigroup());
    }

    return if (Types.isAnonymousObject(v)) {
      switch builder {
        case Pure(a): successNel(a);
        case Ap(s, k): go(s, k);
      };
    } else {
      fail('$v is not an anonymous object structure}).', path);
    };
  }

  public static function isConstant<A>(schema: Schema<A>): Bool {
    return switch schema {
      case UnitSchema: true;
      case IsoSchema(base, _, _): isConstant(base);
      case _: false;
    }
  }

  inline static public function errAt<A>(path: SPath): String -> ParseError
    return ParseError.new.bind(_, path);

  inline static public function fail<A>(message: String, path: SPath): VNel<ParseError, A>
    return failureNel(new ParseError(message, path));
}

class ParseError {
  public var message(default, null): String;
  public var path(default, null): SPath;

  public function new(message: String, path: SPath) {
    this.message = message;
    this.path = path;
  }

  public function toString(): String {
    return '${path.toString()}: ${message}';
  }
}
