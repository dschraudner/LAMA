-- This Happy file was machine-generated by the BNF converter
{
{-# OPTIONS_GHC -fno-warn-incomplete-patterns -fno-warn-overlapping-patterns #-}
module Lang.LAMA.Parser.Par where
import Lang.LAMA.Parser.Abs
import Lang.LAMA.Parser.Lex
import Lang.LAMA.Parser.ErrM
import qualified Data.ByteString.Lazy.Char8 as BS
}

%name pProgram Program
%name pConstExpr ConstExpr

-- no lexer declaration
%monad { Err } { thenM } { returnM }
%tokentype { Token }

%token 
 '(' { PT _ (TS _ 1) }
 ')' { PT _ (TS _ 2) }
 '*' { PT _ (TS _ 3) }
 '+' { PT _ (TS _ 4) }
 ',' { PT _ (TS _ 5) }
 '-' { PT _ (TS _ 6) }
 '.' { PT _ (TS _ 7) }
 '/' { PT _ (TS _ 8) }
 ':' { PT _ (TS _ 9) }
 ';' { PT _ (TS _ 10) }
 '<' { PT _ (TS _ 11) }
 '<=' { PT _ (TS _ 12) }
 '=' { PT _ (TS _ 13) }
 '=>' { PT _ (TS _ 14) }
 '>' { PT _ (TS _ 15) }
 '>=' { PT _ (TS _ 16) }
 '[' { PT _ (TS _ 17) }
 ']' { PT _ (TS _ 18) }
 '^' { PT _ (TS _ 19) }
 'and' { PT _ (TS _ 20) }
 'assertion' { PT _ (TS _ 21) }
 'automaton' { PT _ (TS _ 22) }
 'bool' { PT _ (TS _ 23) }
 'constants' { PT _ (TS _ 24) }
 'definition' { PT _ (TS _ 25) }
 'div' { PT _ (TS _ 26) }
 'edge' { PT _ (TS _ 27) }
 'enum' { PT _ (TS _ 28) }
 'false' { PT _ (TS _ 29) }
 'initial' { PT _ (TS _ 30) }
 'int' { PT _ (TS _ 31) }
 'invariant' { PT _ (TS _ 32) }
 'ite' { PT _ (TS _ 33) }
 'let' { PT _ (TS _ 34) }
 'local' { PT _ (TS _ 35) }
 'location' { PT _ (TS _ 36) }
 'match' { PT _ (TS _ 37) }
 'mod' { PT _ (TS _ 38) }
 'node' { PT _ (TS _ 39) }
 'nodes' { PT _ (TS _ 40) }
 'not' { PT _ (TS _ 41) }
 'or' { PT _ (TS _ 42) }
 'output' { PT _ (TS _ 43) }
 'prod' { PT _ (TS _ 44) }
 'project' { PT _ (TS _ 45) }
 'real' { PT _ (TS _ 46) }
 'returns' { PT _ (TS _ 47) }
 'sint' { PT _ (TS _ 48) }
 'state' { PT _ (TS _ 49) }
 'tel' { PT _ (TS _ 50) }
 'transition' { PT _ (TS _ 51) }
 'true' { PT _ (TS _ 52) }
 'typedef' { PT _ (TS _ 53) }
 'uint' { PT _ (TS _ 54) }
 'use' { PT _ (TS _ 55) }
 'xor' { PT _ (TS _ 56) }
 '{' { PT _ (TS _ 57) }
 '}' { PT _ (TS _ 58) }

L_integ  { PT _ (TI $$) }
L_Identifier { PT _ (T_Identifier _) }
L_StateId { PT _ (T_StateId _) }
L_err    { _ }


%%

Integer :: { Integer } : L_integ  { (read (BS.unpack $1)) :: Integer }
Identifier    :: { Identifier} : L_Identifier { Identifier (mkPosToken $1)}
StateId    :: { StateId} : L_StateId { StateId (mkPosToken $1)}

Program :: { Program }
Program : TypeDefs ConstantDefs Declarations Flow Initial Assertion Invariant { Program $1 $2 $3 $4 $5 $6 $7 } 


TypeDefs :: { TypeDefs }
TypeDefs : {- empty -} { NoTypeDefs } 
  | 'typedef' ListTypeDef { JustTypeDefs $2 }


ListTypeDef :: { [TypeDef] }
ListTypeDef : TypeDef ';' { (:[]) $1 } 
  | TypeDef ';' ListTypeDef { (:) $1 $3 }


TypeDef :: { TypeDef }
TypeDef : 'enum' Identifier '=' '{' ListEnumConstr '}' { EnumDef $2 $5 } 


EnumConstr :: { EnumConstr }
EnumConstr : Identifier { EnumConstr $1 } 


ListEnumConstr :: { [EnumConstr] }
ListEnumConstr : EnumConstr { (:[]) $1 } 
  | EnumConstr ',' ListEnumConstr { (:) $1 $3 }


Type :: { Type }
Type : BaseType { GroundType $1 } 
  | Identifier { TypeId $1 }
  | BaseType '^' Natural { ArrayType $1 $3 }
  | Type '*' Type { ProdType $1 $3 }


BaseType :: { BaseType }
BaseType : 'bool' { BoolT } 
  | 'int' { IntT }
  | 'real' { RealT }
  | 'sint' '[' Natural ']' { SInt $3 }
  | 'uint' '[' Natural ']' { UInt $3 }


ConstantDefs :: { ConstantDefs }
ConstantDefs : {- empty -} { NoConstantDefs } 
  | 'constants' ListConstantDef { JustConstantDefs $2 }


ListConstantDef :: { [ConstantDef] }
ListConstantDef : ConstantDef ';' { (:[]) $1 } 
  | ConstantDef ';' ListConstantDef { (:) $1 $3 }


ConstantDef :: { ConstantDef }
ConstantDef : Identifier '=' Constant { ConstantDef $1 $3 } 


Natural :: { Natural }
Natural : Integer { Nat $1 } 


IntegerConst :: { IntegerConst }
IntegerConst : Integer { NonNegativeInt $1 } 
  | '(' '-' Integer ')' { NegativeInt $3 }


Constant :: { Constant }
Constant : BoolV { BoolConst $1 } 
  | IntegerConst { IntConst $1 }
  | IntegerConst '/' IntegerConst { RealConst $1 $3 }
  | 'sint' '[' Natural ']' '(' IntegerConst ')' { SIntConst $3 $6 }
  | 'uint' '[' Natural ']' '(' Natural ')' { UIntConst $3 $6 }


BoolV :: { BoolV }
BoolV : 'true' { TrueV } 
  | 'false' { FalseV }


Assertion :: { Assertion }
Assertion : {- empty -} { NoAssertion } 
  | 'assertion' Expr ';' { JustAssertion $2 }


Initial :: { Initial }
Initial : {- empty -} { NoInitial } 
  | 'initial' ListStateInit ';' { JustInitial $2 }


Invariant :: { Invariant }
Invariant : {- empty -} { NoInvariant } 
  | 'invariant' Expr ';' { JustInvariant $2 }


ListStateInit :: { [StateInit] }
ListStateInit : StateInit { (:[]) $1 } 
  | StateInit ',' ListStateInit { (:) $1 $3 }


StateInit :: { StateInit }
StateInit : Identifier '=' ConstExpr { StateInit $1 $3 } 


ConstExpr :: { ConstExpr }
ConstExpr : Expr { ConstExpr $1 } 


ListIdentifier :: { [Identifier] }
ListIdentifier : Identifier { (:[]) $1 } 
  | Identifier ',' ListIdentifier { (:) $1 $3 }


TypedVars :: { TypedVars }
TypedVars : ListIdentifier ':' Type { TypedVars $1 $3 } 


ListTypedVars :: { [TypedVars] }
ListTypedVars : TypedVars { (:[]) $1 } 
  | TypedVars ';' ListTypedVars { (:) $1 $3 }


MaybeTypedVars :: { MaybeTypedVars }
MaybeTypedVars : {- empty -} { NoTypedVars } 
  | ListTypedVars { JustTypedVars $1 }


Node :: { Node }
Node : 'node' Identifier '(' MaybeTypedVars ')' 'returns' '(' ListTypedVars ')' ';' 'let' Declarations Flow Outputs ControlStructure Initial Assertion 'tel' { Node $2 $4 $8 $12 $13 $14 $15 $16 $17 } 


ListNode :: { [Node] }
ListNode : Node { (:[]) $1 } 
  | Node ListNode { (:) $1 $2 }


Declarations :: { Declarations }
Declarations : NodeDecls LocalDecls StateDecls { Declarations $1 $2 $3 } 


VarDecls :: { VarDecls }
VarDecls : TypedVars ';' { SingleDecl $1 } 
  | TypedVars ';' VarDecls { ConsDecl $1 $3 }


NodeDecls :: { NodeDecls }
NodeDecls : {- empty -} { NoNodes } 
  | 'nodes' ListNode { JustNodeDecls $2 }


LocalDecls :: { LocalDecls }
LocalDecls : {- empty -} { NoLocals } 
  | 'local' VarDecls { JustLocalDecls $2 }


StateDecls :: { StateDecls }
StateDecls : {- empty -} { NoStateDecls } 
  | 'state' VarDecls { JustStateDecls $2 }


Flow :: { Flow }
Flow : LocalDefinitions Transitions { Flow $1 $2 } 


LocalDefinitions :: { LocalDefinitions }
LocalDefinitions : {- empty -} { NoLocalDefinitons } 
  | 'definition' ListInstantDefinition { JustLocalDefinitons $2 }


Transitions :: { Transitions }
Transitions : {- empty -} { NoTransitions } 
  | 'transition' ListTransition { JustTransitions $2 }


Outputs :: { Outputs }
Outputs : {- empty -} { NoOutputs } 
  | 'output' ListInstantDefinition { JustOutputs $2 }


ListInstantDefinition :: { [InstantDefinition] }
ListInstantDefinition : InstantDefinition ';' { (:[]) $1 } 
  | InstantDefinition ';' ListInstantDefinition { (:) $1 $3 }


ListTransition :: { [Transition] }
ListTransition : Transition ';' { (:[]) $1 } 
  | Transition ';' ListTransition { (:) $1 $3 }


InstantDefinition :: { InstantDefinition }
InstantDefinition : Identifier '=' Expr { InstantExpr $1 $3 } 
  | Identifier '=' '(' 'use' Identifier ListExpr ')' { NodeUsage $1 $5 (reverse $6) }


Transition :: { Transition }
Transition : StateId '=' Expr { Transition $1 $3 } 


ControlStructure :: { ControlStructure }
ControlStructure : ListAutomaton { ControlStructure (reverse $1) } 


Automaton :: { Automaton }
Automaton : 'automaton' 'let' ListLocation InitialLocation ListEdge 'tel' { Automaton $3 $4 $5 } 


Location :: { Location }
Location : 'location' Identifier 'let' Flow 'tel' { Location $2 $4 } 


InitialLocation :: { InitialLocation }
InitialLocation : 'initial' Identifier ';' { InitialLocation $2 } 


Edge :: { Edge }
Edge : 'edge' '(' Identifier ',' Identifier ')' ':' Expr ';' { Edge $3 $5 $8 } 


ListLocation :: { [Location] }
ListLocation : Location { (:[]) $1 } 
  | Location ListLocation { (:) $1 $2 }


ListEdge :: { [Edge] }
ListEdge : Edge { (:[]) $1 } 
  | Edge ListEdge { (:) $1 $2 }


ListAutomaton :: { [Automaton] }
ListAutomaton : {- empty -} { [] } 
  | ListAutomaton Automaton { flip (:) $1 $2 }


Atom :: { Atom }
Atom : Constant { AtomConst $1 } 
  | Identifier { AtomVar $1 }


Expr :: { Expr }
Expr : Atom { AtExpr $1 } 
  | '(' UnOp Expr ')' { Expr1 $2 $3 }
  | '(' BinOp Expr Expr ')' { Expr2 $2 $3 $4 }
  | '(' TernOp Expr Expr Expr ')' { Expr3 $2 $3 $4 $5 }
  | '(' 'prod' ListExpr ')' { Prod (reverse $3) }
  | '(' 'project' Identifier Natural ')' { Project $3 $4 }
  | '(' 'match' Expr '{' ListPattern '}' ')' { Match $3 $5 }


ListExpr :: { [Expr] }
ListExpr : {- empty -} { [] } 
  | ListExpr Expr { flip (:) $1 $2 }


ListPattern :: { [Pattern] }
ListPattern : Pattern { (:[]) $1 } 
  | Pattern ',' ListPattern { (:) $1 $3 }


Pattern :: { Pattern }
Pattern : PatHead '.' Expr { Pattern $1 $3 } 


PatHead :: { PatHead }
PatHead : EnumConstr { EnumPat $1 } 


List2Id :: { List2Id }
List2Id : Identifier Identifier { Id2 $1 $2 } 
  | Identifier List2Id { ConsId $1 $2 }


UnOp :: { UnOp }
UnOp : 'not' { Not } 


BinOp :: { BinOp }
BinOp : 'or' { Or } 
  | 'and' { And }
  | 'xor' { Xor }
  | '=>' { Implies }
  | '=' { Equals }
  | '<' { Less }
  | '>' { Greater }
  | '<=' { LEq }
  | '>=' { GEq }
  | '+' { Plus }
  | '-' { Minus }
  | '*' { Mul }
  | '/' { RealDiv }
  | 'div' { IntDiv }
  | 'mod' { Mod }


TernOp :: { TernOp }
TernOp : 'ite' { Ite } 



{

returnM :: a -> Err a
returnM = return

thenM :: Err a -> (a -> Err b) -> Err b
thenM = (>>=)

happyError :: [Token] -> Err a
happyError ts =
  Bad $ "syntax error at " ++ tokenPos ts ++ 
  case ts of
    [] -> []
    [Err _] -> " due to lexer error"
    _ -> " before " ++ unwords (map (BS.unpack . prToken) (take 4 ts))

myLexer = tokens
}

