package tools.haxelib;

import haxe.ds.Option;

#if macro
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Context;

using haxe.macro.Tools;
#end

typedef Validatable = {
	function validate():Option<{ error: String }>;
}

class Validator {
	#if macro
	static var ARG = 'v';
	var pos:Position;
	var IARG:Expr;
	function new(pos) {
		this.pos = pos;
		IARG = macro @:pos(pos) $i{ARG};
	}
	
	function doCheck(t:Type, e:Expr) {
		var ct = t.toComplexType();
		return
			macro @:pos (function ($ARG : $ct) ${makeCheck(t)})($e);
	}
	
	function isAtom(s:String)
		return switch s {
			case 'String', 'Int', 'Bool', 'Float': true;
			default: false;
		}
	
	function enforce(type:String)
		return 
			macro @:pos(pos) Std.is($i{ARG}, $i{type});
		
	function makeCheck(t:Type):Expr 
		return
			switch Context.follow(t) {
				case TAnonymous(_.get().fields => fields): 
					
					var block:Array<Expr> = [for (f in fields) 
						switch f.kind {
							case FVar(AccNormal, _):
								var name = f.name;
								var rec = doCheck(f.type, macro @:pos(pos) $IARG.$name);
								rec;
							default: //skip
						}
					];
					
					block.unshift(
						macro @:pos(pos) if (!Reflect.isObject($IARG)) throw 'object expected'
					);
					
					macro @:pos(pos) $b{block};
					
				case _.toString() => atom if (isAtom(atom)): 
					
					enforce(atom);
					
				case TInst(_.get().module => 'Array', [p]):
					
					macro @:pos(pos) {
						${enforce('Array')};
						for ($IARG in $IARG)
							${doCheck(p, IARG)};
					}
				
				case TAbstract(_.get() => a, _) if (a.meta.has(':enum')):
					var name = a.module + '.' + a.name;
					var options:Array<Expr> = [for (f in a.impl.get().statics.get()) 
						switch f.kind {
							case FVar(_, _):
								macro @:pos(pos) $p{(name+'.'+f.name).split('.')};
							default: //skip
						}
					];
					
					macro if (!Lambda.has($a { options }, $IARG)) throw 'Invalid value ' + $IARG + ' for ' + $v { a.name };
					
				case TAbstract(_.get() => a, _):
					
					macro @:pos(pos) switch ($IARG : tools.haxelib.Validator.Validatable).validate() {
						case Some( { error: e } ): throw e;
						case None:
					}
					
				default: 
					
					throw t.toString();
			}
	#end		
	macro static public function validate(e:Expr) 
		return 
			new Validator(e.pos).doCheck(Context.typeof(e), e);
}