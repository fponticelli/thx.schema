package thx.schema.macro;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import thx.schema.macro.Error.*;
import thx.schema.macro.BoundSchemaType;
import thx.schema.macro.Utils.*;
using thx.Arrays;

class SchemaBuilder {
  // here are passed things like Option<Array<A>> or Either<Option<String>> where A is a type paramter of the container schema
  public static function lookupSchema(schemaType: BoundSchemaType, typeSchemas: Map<String, Expr>): Expr {
    return switch schemaType.type {
      case LocalParam(param):
        var name = TypeBuilder.variableNameFromTypeParameter(param);
        return macro (() -> $i{name});
      case QualifiedType(_):
        var type = schemaType.toString();
        if(typeSchemas.exists(type)) {
          typeSchemas.get(type);
        } else {
          var path = TypeBuilder.ensure(schemaType.toUnboundSchemaType(), typeSchemas);
          macro $p{path};
        }
      case AnonObject(_):
        var type = schemaType.toString();
        if(typeSchemas.exists(type)) {
          typeSchemas.get(type);
        } else {
          var path = TypeBuilder.ensure(schemaType.toUnboundSchemaType(), typeSchemas);
          macro $p{path};
        }
    };
  }

  public static function generateSchema(schemaType: BoundSchemaType, typeSchemas: Map<String, Expr>): Expr {
    return switch [schemaType.toType(), schemaType.type] {
      case [TInst(_.get() => cls, _),     BoundSchemaTypeImpl.QualifiedType(qtype)]: generateClassSchema(cls,    qtype, typeSchemas);
      case [TEnum(_.get() => enm, _),     BoundSchemaTypeImpl.QualifiedType(qtype)]: generateEnumSchema(enm,     qtype, typeSchemas);
      case [TAbstract(_.get() => abs, _), BoundSchemaTypeImpl.QualifiedType(qtype)]: generateAbstractSchema(abs, qtype, typeSchemas);
      // TODO
      case [TAnonymous(_.get() => anon),  BoundSchemaTypeImpl.AnonObject(obj)]:      generateAnonSchema(anon,    obj,   typeSchemas);
      case _: fatal('Cannot generate schema for unsupported type ${schemaType.toString()}');
    }
  }

  static function generateClassSchema(cls: ClassType, qtype: QualifiedType<BoundSchemaType>, typeSchemas: Map<String, Expr>) {
    var fields = cls.fields.get().filter(keepVariables);
    var n = fields.length;
    return if(n == 0) {
      var path = qtype.parts();
      macro thx.schema.SimpleSchema.object(PropsBuilder.Pure(Type.createEmptyInstance($p{path})));
    } else {
      // generate constructor function
      var constructor = generateClassConstructorF(fields.map(classFieldToFunctionArgument), qtype);
      // generate fields
      var properties = fields.map(createPropertyFromClassField.bind(BoundSchemaType.createQualified(qtype), typeSchemas, _));
      // capture apN and ap arguments
      var apN = 'ap$n';
      var apNArgs = [constructor].concat(properties);
      // return schema
      var body = macro thx.schema.SimpleSchema.object(thx.schema.SchemaDSL.$apN($a{apNArgs}));
      body;
    }
  }

  static function classFieldToFunctionArgument(cf: ClassField): FunctionArgument {
    return {
      ctype: TypeTools.toComplexType(cf.type),
      opt: false,
      name: cf.name
    };
  }

  static function generateClassConstructorF(args: Array<FunctionArgument>, qtype: QualifiedType<BoundSchemaType>) {
    var path = qtype.parts(),
        bodyParts = [
            macro var inst = Type.createEmptyInstance($p{path})
          ]
          .concat(args.map(arg -> macro Reflect.setField(inst, $v{arg.name}, $i{arg.name})))
          .append(macro return inst);
    return createFunction("createInstance" + qtype.toIdentifier(), args, macro $b{bodyParts}, qtype.toComplexType(b -> b.toComplexType()), []);
  }

  static function generateEnumConstructor(name: String, constructor: EnumField, schemaType: QualifiedType<BoundSchemaType>, typeSchemas: Map<String, Expr>) {
    var cons = schemaType.parts().concat([constructor.name]);
    // trace(constructor);
    return switch constructor.type {
      case TEnum(_):
        macro thx.schema.SimpleSchema.constEnum($v{name}, $p{cons});
      case TFun(args, returnType):
        var n = args.length;
        var apN = 'ap$n';
        var container = thx.schema.macro.AnonObject.fromEnumArgs(args);
        var containerType = container.toComplexType();
        var complexType = schemaType.toComplexType(f -> f.toComplexType());
        var object = container.toSetterObject();
        var cargs = args.map(arg -> {
              ctype: TypeTools.toComplexType(arg.t),
              name: arg.name,
              opt: arg.opt
            });
        var constructorF = createFunction(null, cargs, macro return $object, containerType, []);
        // static function createProperty(qtype: QualifiedType<BoundSchemaType>, argType: BoundSchemaType, argName: String, typeSchemas: Map<String, Expr>): Expr {
        var objectProperties = container.fields.map(f -> createProperty(BoundSchemaType.createAnon(container), f.type, f.name, typeSchemas));
        var apNArgs = [constructorF].concat(objectProperties);
        var enumArgs = args.map(a -> a.name).map(n -> macro v.$n);
        var destructured = args.map(a -> a.name).map(n -> macro $i{n});
        var body = macro thx.schema.SimpleSchema.alt(
          $v{name},
          thx.schema.SimpleSchema.object(thx.schema.SchemaDSL.$apN($a{apNArgs})),
          function(v: $containerType): $complexType return $p{cons}($a{enumArgs}),
          function(v: $complexType): haxe.ds.Option<$containerType> return switch v {
            case $p{cons}($a{destructured}): Some($object);
            case _: None;
          }
        );
        // trace(ExprTools.toString(body));
        body;
      case _:
        fatal('unable to match correct type for enum constructor: ${constructor}');
    };
/*
    var ctype = TypeTools.toComplexType(Context.getType(type));
    return switch item.field.type {
      case TFun(args, returd):
        var n = args.length,
            apN = 'ap$n',
            containerType = createAnonymTypeFromArgs(args),
            object = createSetObject(args),
            cargs = args.map(arg -> {
              ctype: TypeTools.toComplexType(arg.t),
              name: arg.name,
              opt: arg.opt
            }),
            constructorF = createFunction(null, cargs, createReturn(object), containerType, []),
            objectProperties = args.map(createProperty.bind(containerType, _, providedSchemas)),
            apNArgs = [constructorF].concat(objectProperties),
            enumArgs = args.map(a -> a.name).map(n -> macro v.$n),
            destructured = args.map(a -> a.name).map(n -> macro $i{n});
        var r = macro thx.schema.SimpleSchema.alt(
          $v{item.name},
          thx.schema.SimpleSchema.object(thx.schema.SchemaDSL.$apN($a{apNArgs})),
          function(v: $containerType): $ctype return $p{cons}($a{enumArgs}),
          function(v: $ctype): haxe.ds.Option<$containerType> return switch v {
            case $p{cons}($a{destructured}): Some($object);
            case _: None;
          }
        );
        r;
      case _:
        Context.error("unable to match correct type for enum constructor: " + item.field, Context.currentPos());
    }
*/
  }

  static function generateEnumSchema(enm: EnumType, schemaType: QualifiedType<BoundSchemaType>, typeSchemas: Map<String, Expr>) {
    var constructors: Array<Expr> = enm.names.map(name -> generateEnumConstructor(name, enm.constructs.get(name), schemaType, typeSchemas));
    var body = macro thx.schema.SimpleSchema.oneOf([$a{constructors}]);
    // trace(ExprTools.toString(body));
    return body;
/*
    var tenum = extractTypeFromExpression(e);
    var params = extractTypeParamsFromExpression(e);

    // push all types to map
    params.map(v -> TypeTools.toString(v.t)).each(name -> {
      var n = typeToArgumentName(name);
      typeSchemaMap.set(name, macro $i{n});
    });

    var nenum = extractTypeNameFromExpression(e);
    var list = extractEnumConstructorsFromType(tenum);
    var constructors: Array<Expr> = list.map(constructEnumConstructorExpression.bind(nenum, _, typeSchemaMap));

    var argNames = params.map(p -> typeToArgumentName(p.name)).map(a -> macro $i{a});
    var inner = createFunction(
      "_makeSchema",
      params.map(p -> { ctype: wrapTypeInSchema(p.t), name: typeToArgumentName(p.name), opt: false }),
      macro return thx.schema.SimpleSchema.oneOf([$a{constructors}]),
      null,
      ["E"].concat(params.map(v -> v.name))
    );
    var r = createFunction(
      "makeSchema",
      // DO NOT set the types of the arguments for ctype. The compiler doesn't like that
      params.map(p -> { ctype: null, name: typeToArgumentName(p.name), opt: false }),
      macro {
        $inner;
        return _makeSchema($a{argNames});
      },
      null,
      []
    );
*/
  }

  static function generateAbstractSchema(abs: AbstractType, schemaType: QualifiedType<BoundSchemaType>, typeSchemas: Map<String, Expr>) {
    return macro null; // TODO
  }

  static function generateAnonSchema(anon: AnonType, anonObject: AnonObject, typeSchemas: Map<String, Expr>) {
    return macro null; // TODO
  }

  static function createFunction(name: Null<String>, args: Array<FunctionArgument>, body: Expr, returnType: Null<ComplexType>, typeParams: Array<String>): Expr {
    return createExpressionFromDef(EFunction(name, {
      args: args.map(a -> ({
        name: a.name,
        type: a.ctype,
        opt: a.opt,
        meta: null,
        value: null
      } : FunctionArg)),
      ret: returnType,
      expr: body,
      params : typeParams.map(n -> {
        name: n,
        constraints: null,
        params: null,
        meta: null
      })
    }));
  }

  static function createExpressionFromDef(e: ExprDef) {
    return {
      expr: e,
      pos: Context.currentPos()
    };
  }

  static function createPropertyFromClassField(qtype: BoundSchemaType, typeSchemas: Map<String, Expr>, cf: ClassField): Expr {
    var argType = BoundSchemaType.fromType(cf.type);
    var argName = cf.name;
    return createProperty(qtype, argType, argName, typeSchemas);
  }

  public static function resolveSchema(schemaType: BoundSchemaType, typeSchemas: Map<String, Expr>) {
      var args = schemaType.parameters().map(resolveSchema.bind(_, typeSchemas));
      var schema: Expr = lookupSchema(schemaType, typeSchemas);

      if(args.length > 0) {
        return macro thx.schema.SimpleSchema.lazy(() -> $schema($a{args}).schema);
      } else {
        return macro $schema();
      };
  }

  static function createProperty(qtype: BoundSchemaType, argType: BoundSchemaType, argName: String, typeSchemas: Map<String, Expr>): Expr {
    var schema = resolveSchema(argType, typeSchemas),
        containerType = qtype.toComplexType(),
        type = argType.toComplexType();
    return macro thx.schema.SchemaDSL.required($v{argName}, $schema, (v : $containerType) -> (Reflect.field(v, $v{argName}): $type));
  }
}

typedef FunctionArgument = {
  ctype: Null<ComplexType>,
  opt: Bool,
  name: String
};
