package thx.schema;

import utest.Assert.*;
import thx.schema.Generic.*;
// import thx.schema.SimpleSchema;
// import thx.schema.SimpleSchema.*;
// import thx.schema.SchemaDSL.*;
// import thx.schema.macro.Macros;
// using thx.schema.SchemaDynamicExtensions;
// import thx.Either;
// import thx.Functions.identity;
// import haxe.ds.Option;

class TestGeneric {
  public function new() {}

  public function testArguments() {
    var f = schema(thx.Either);
    trace(f());
    var f = schema(String);
    var f = schema(G);
    var f = schema(thx.Tuple.Tuple2);
    var f = schema({ name : String, age : Int });
    var f = schema({ age : Int, name : String });
    var f = schema({ wineName : String, age : Int });
    var f = schema({ name : String, age : Int });
  }
}

class G<A, B> {

}
