module TestAbsTrans (tests) where

import Test.HUnit
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.ByteString.Char8 as B
import Data.Map as Map

import Lang.LAMA.Identifier
import Lang.LAMA.Types
import Lang.LAMA.TypedStructure
import Lang.LAMA.Parse

tests :: Test
tests = TestList [
    TestLabel "Types" testTypes,
    TestLabel "Constants" testConstants,
    TestLabel "Switch" testSwitchTrans,
    TestLabel "UpDownCounter" testUpDownCounterTrans
  ]

-- Helper
dontcare :: (Int, Int)
dontcare = (0, 0)
ident :: String -> Identifier
ident s = Id (B.pack s) dontcare

false :: Constant
false = Typed (BoolConst False) boolT

varExpr :: Identifier -> Type -> Expr
varExpr v t = Typed (AtExpr (AtomVar v)) t

constAtExpr :: Constant -> Expr
constAtExpr c@(Typed _ t) = Typed (AtExpr (AtomConst c)) t

intConst :: Integer -> Constant
intConst c = Typed (IntConst c) intT

intE :: Integer -> Expr
intE = constAtExpr . intConst

intConstE :: Integer -> ConstExpr
intConstE c = Typed (Const $ intConst c) intT

ite :: Expr -> Expr -> Expr -> Expr
ite c e1 e2 = Typed (Ite c e1 e2) boolT

eqE :: Expr -> Expr -> Expr
eqE e1 e2 = Typed (Expr2 Equals e1 e2) boolT

leqE :: Expr -> Expr -> Expr
leqE e1 e2 = Typed (Expr2 LEq e1 e2) boolT

notE :: Expr -> Expr
notE e = Typed (LogNot e) boolT

checkEqual :: Program -> BL.ByteString -> Test
checkEqual t inp = case parseLAMA inp of
  Left (ParseError pe) -> TestCase $ assertFailure $ "Parsing failed: " ++ show pe
  Left (StaticError se) -> TestCase $ assertFailure $ "Conversion failed: " ++ show se
  Right t' -> t ~=? t'

---------------

typesSrc :: BL.ByteString
typesSrc = BL.pack $ unlines [
  "typedef",
  "  enum e = { e1, e2 };",
  "  record r1 = { f1 : e };",
  "  record r2 = { f2 : r1 };",
  "nodes node main() returns (x : r2); let tel",
  "local x : r2;",
  "definition x = (use main);" ]

expectedTypes :: Program
expectedTypes =
  Program {
    progTypeDefinitions = fromList [
      (e, EnumDef (EnumT [e1, e2])),
      (r1, RecordDef (RecordT [(f1, NamedType e)])),
      (r2, RecordDef (RecordT [(f2, NamedType r1)]))
    ],
    progConstantDefinitions = fromList [],
    progDecls = Declarations {
      declsNode = [Node {
        nodeName = ident "main",
        nodeInputs = [],
        nodeOutputs = [Variable x (NamedType r2)],
        nodeDecls = Declarations [] [] [],
        nodeFlow = Flow {flowDefinitions = [], flowTransitions = []},
        nodeOutputDefs = [], nodeAutomata = [], nodeInitial = fromList []
      }],
      declsState = [],
      declsLocal = [Variable x (NamedType r2)]
    },
    progFlow = Flow [InstantDef [x] (Typed (NodeUsage main []) (NamedType r2))] [],
    progAssertions = [], progInitial = fromList [], progInvariant = []
  }
  where
    main = ident "main"
    e = ident "e"
    e1 = ident "e1"
    e2 = ident "e2"
    r1 = ident "r1"
    r2 = ident "r2"
    f1 = ident "f1"
    f2 = ident "f2"
    x = ident "x"

testTypes :: Test
testTypes = checkEqual expectedTypes typesSrc

---------------

constantsSrc :: BL.ByteString
constantsSrc = BL.pack $ unlines [
  "nodes",
  "  node main() returns (x : sint[32]; y : uint[16]); let",
  "    output",
  "      x = sint[32]((- 5));",
  "      y = uint[16](1322);",
  "tel" ]

expectedConstants :: Program
expectedConstants =
  Program {
    progTypeDefinitions = fromList [],
    progConstantDefinitions = fromList [],
    progDecls = Declarations {
      declsNode = [Node {
        nodeName = ident "main",
        nodeInputs = [],
        nodeOutputs = [
          Variable x (GroundType (SInt 32)),
          Variable y (GroundType (UInt 16))
        ],
        nodeDecls = Declarations [] [] [],
        nodeFlow = Flow [] [],
        nodeOutputDefs = [
          InstantDef [x] (constAtExpr $ Typed (SIntConst (-5)) (GroundType (SInt 32))),
          InstantDef [y] (constAtExpr $ Typed (UIntConst 1322) (GroundType (UInt 16)))
        ],
        nodeAutomata = [], nodeInitial = fromList []
      }],
      declsState = [],
      declsLocal = []
    },
    progFlow = Flow [] [],
    progAssertions = [], progInitial = fromList [], progInvariant = []
  }
  where
    x = ident "x"
    y = ident "y"

testConstants :: Test
testConstants = checkEqual expectedConstants constantsSrc

---------------

switch :: BL.ByteString
switch = BL.pack $ unlines [
    "nodes",
    "node Switch(on, off: bool) returns (so: bool);",
    "let",
    "  state",
    "    s : bool;",
    "  local",
    "    s_ : bool;",
    "  definition",
    "    s_ = (ite s (not off) on);",
    "  transition",
    "    s' = s_;",
    "  output",
    "    so = s_;",
    "  initial s = false;",
    "tel",
    "local on, off, so : bool;",
    "definition so = (use Switch on off);"]

expectedSwitch :: Program
expectedSwitch =
  Program {
    progTypeDefinitions = fromList [],
    progConstantDefinitions = fromList [],
    progDecls = Declarations {
      declsNode = [Node {
        nodeName = ident "Switch",
        nodeInputs = [Variable on boolT, Variable off boolT],
        nodeOutputs = [Variable so boolT],
        nodeDecls = Declarations {
          declsNode = [],
          declsState = [Variable s boolT],
          declsLocal = [Variable s_ boolT]
        },
        nodeFlow = Flow {
          flowDefinitions = [
            InstantDef [s_] (
              ite (varExpr s boolT)
                  (notE (varExpr off boolT))
                  (varExpr on boolT)
            )
          ],
          flowTransitions = [StateTransition s (varExpr s_ boolT)]
        },
        nodeOutputDefs = [InstantDef [so] (varExpr s_ boolT)], 
        nodeAutomata = [],
        nodeInitial = fromList [(s,(Typed (Const false) boolT))]
      }],
      declsState = [],
      declsLocal = [Variable on boolT, Variable off boolT, Variable so boolT]
    },
    progFlow = Flow {
      flowDefinitions = [InstantDef [so] (Typed (NodeUsage switchN [varExpr on boolT, varExpr off boolT]) boolT)],
      flowTransitions = []
    },
    progAssertions = [], progInitial = fromList [], progInvariant = []
  }
  where
    on = ident "on"
    off = ident "off"
    s = ident "s"
    so = ident "so"
    s_ = ident "s_"
    switchN = ident "Switch"

testSwitchTrans :: Test
testSwitchTrans = checkEqual expectedSwitch switch

-------------

upDownCounter :: BL.ByteString
upDownCounter = BL.pack $ unlines [
  "nodes",
  "  node main () returns (xo : int);",
  "  let",
  "    state",
  "      x : int;",
  "    local",
  "      x_ : int;",
  "    transition",
  "      x' = x_;",
  "    output",
  "      xo = x_;",
  "    ",
  "    automaton let",
 "       location A let",
 "         definition x_ = (+ x 1);",
 "       tel",
 "       location B let",
 "         definition x_ = (- x 1);",
 "       tel",
 "       initial A;",
 "       edge (A, B) : (= x 10);",
 "       edge (B, A) : (= x 0);",
 "       edge (A, A) : (not (= x 10));",
 "       edge (B, B) : (not (= x 0));",
 "     tel",
 "     ",
 "     initial x = (- 1);",
 "  tel",
 "local xo : int;",
 "definition xo = (use main);",
 "invariant (<= xo 10);" ]

expectedUpDownCounter :: Program
expectedUpDownCounter =
  Program {
    progTypeDefinitions = fromList [], progConstantDefinitions = fromList [],
    progDecls = Declarations {
      declsNode = [Node {
        nodeName = ident "main",
        nodeInputs = [],
        nodeOutputs = [Variable xo intT],
        nodeDecls = Declarations {
          declsNode = [],
          declsState = [Variable x intT],
          declsLocal = [Variable x_ intT]
        },
        nodeFlow = Flow {
          flowDefinitions = [],
          flowTransitions = [StateTransition x (varExpr x_ intT)]
        },
        nodeOutputDefs = [InstantDef [xo] (varExpr x_ intT)],
        nodeAutomata = [ Automaton {
          automLocations = [
            Location sA (Flow {
              flowDefinitions = [InstantDef [x_] (Typed (Expr2 Plus (varExpr x intT) (intE 1)) (GroundType IntT))],
              flowTransitions = []
            }),
            Location sB (Flow {
              flowDefinitions = [InstantDef [x_] (Typed (Expr2 Minus (varExpr x intT) (intE 1)) (GroundType IntT))],
              flowTransitions = []
            })
          ],
          automInitial = sA,
          automEdges = [
            Edge sA sB (eqE (varExpr x intT) (intE 10)),
            Edge sB sA (eqE (varExpr x intT) (intE 0)),
            Edge sA sA (notE (eqE (varExpr x intT) (intE 10))),
            Edge sB sB (notE (eqE (varExpr x intT) (intE 0)))
          ]
        }],
        nodeInitial = fromList [(x, intConstE (-1))]
      }],
      declsState = [],
      declsLocal = [Variable xo intT]      
    },
    progFlow = Flow {
      flowDefinitions = [InstantDef [xo] (Typed (NodeUsage main []) intT)],
      flowTransitions = []
    },
    progInitial = fromList [],
    progAssertions = [],
    progInvariant = [leqE (varExpr xo intT) (intE 10)]
  }
  where
    main = ident "main"
    x = ident "x"
    x_ = ident "x_"
    xo = ident "xo"
    sA = ident "A"
    sB = ident "B"

testUpDownCounterTrans :: Test
testUpDownCounterTrans = checkEqual expectedUpDownCounter upDownCounter

