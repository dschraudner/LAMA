{-# LANGUAGE TupleSections, TemplateHaskell #-}

module Lang.LAMA.Pretty (prettyLama) where

import Development.Placeholders

import Prelude hiding (null)
import qualified Data.List as List
import qualified Data.Map as Map
import Data.Map (Map)
import Data.Natural
import Data.Ratio

import Lang.LAMA.Identifier
import Lang.LAMA.Types
import Lang.LAMA.UnTypedStructure
import qualified Lang.LAMA.Parser.Abs as Abs
import Lang.LAMA.Parser.Print (printTree)

ite :: (a -> Bool) -> (a -> b) -> (a -> b) -> a -> b
ite c f g x = if c x then f x else g x

class Container c where
  null :: c -> Bool

mapDefault :: Container c => a -> (c -> a) -> c -> a
mapDefault d f = ite null (const d) f

instance Container (Map k v) where
  null = Map.null

instance Container [a] where
  null = List.null

prettyLama :: Ident i => Program i -> String
prettyLama = printTree . trProgram

trIdent :: Ident i => i -> Abs.Identifier
trIdent = Abs.Identifier . ((0,0),) . identBS

trStateId :: Ident i => i -> Abs.StateId
trStateId = Abs.StateId . ((0,0),) . identBS

trNatural :: Natural -> Abs.Natural
trNatural = Abs.Nat . toInteger

trBoolV :: Bool -> Abs.BoolV
trBoolV True = Abs.TrueV
trBoolV False = Abs.FalseV

trIntegerConst :: Integer -> Abs.IntegerConst
trIntegerConst v = if v < 0 then Abs.NegativeInt $ abs v else Abs.NonNegativeInt v

trType :: Ident i => Type i -> Abs.Type
trType (GroundType bt) = Abs.GroundType $ trBaseType bt
trType (NamedType x) = Abs.TypeId $ trIdent x
trType (ArrayType bt n) = Abs.ArrayType (trBaseType bt) (trNatural n)
trType (Prod _) = undefined

trBaseType :: BaseType -> Abs.BaseType
trBaseType BoolT = Abs.BoolT
trBaseType IntT = Abs.IntT
trBaseType RealT = Abs.RealT
trBaseType (SInt n) = Abs.SInt $ trNatural n
trBaseType (UInt n) = Abs.UInt $ trNatural n

trProgram :: Ident i => Program i -> Abs.Program
trProgram (Program t c d f i a p) =
  Abs.Program (trTypeDefs t) (trConstantDefs c) (trDecls d)
              (trFlow f) (trInitial i) (trAssertion a) (trInvariant p)

trTypeDefs :: Ident i => Map (TypeAlias i) (TypeDef i) -> Abs.TypeDefs
trTypeDefs tds
  | Map.null tds = Abs.NoTypeDefs
  | otherwise = Abs.JustTypeDefs $ map trTypeDef $ Map.toList tds

trTypeDef :: Ident i => (TypeAlias i, TypeDef i) -> Abs.TypeDef
trTypeDef (x, EnumDef (EnumT ctrs)) = Abs.EnumDef $ Abs.EnumT (trIdent x) (map trEnumConstr ctrs)
trTypeDef (x, RecordDef (RecordT fs)) = Abs.RecordDef $ Abs.RecordT (trIdent x) (map trRecordField fs)

trEnumConstr :: Ident i => EnumConstr i -> Abs.EnumConstr
trEnumConstr = Abs.EnumConstr . trIdent

trRecordField :: Ident i => (RecordField i, Type i) -> Abs.RecordField
trRecordField (f, t) = Abs.RecordField (trIdent f) (trType t)

trConstantDefs :: Ident i => Map i Constant -> Abs.ConstantDefs
trConstantDefs = mapDefault Abs.NoConstantDefs (Abs.JustConstantDefs . map trConstantDef . Map.toList)

trConstantDef :: Ident i => (i, Constant) -> Abs.ConstantDef
trConstantDef (x, c) = Abs.ConstantDef (trIdent x) (trConstant c)

trDecls :: Ident i => Declarations i -> Abs.Declarations
trDecls d = Abs.Declarations (trNodeDecls $ declsNode d)
              (trStateDecls $ declsState d) (trLocalDecls $ declsLocal d)

trNodeDecls :: Ident i => Map i (Node i) -> Abs.NodeDecls
trNodeDecls = mapDefault Abs.NoNodes (Abs.JustNodeDecls . map trNode . Map.toList)

trStateDecls :: Ident i => [Variable i] -> Abs.StateDecls
trStateDecls = mapDefault Abs.NoStateDecls (Abs.JustStateDecls . trVarDecls)

trLocalDecls :: Ident i => [Variable i] -> Abs.LocalDecls
trLocalDecls = mapDefault Abs.NoLocals (Abs.JustLocalDecls . trVarDecls)

trVarDecls :: Ident i => [Variable i] -> Abs.VarDecls
trVarDecls [] = undefined
trVarDecls [x] = Abs.SingleDecl $ trTypedVars x
trVarDecls (x:xs) = Abs.ConsDecl (trTypedVars x) (trVarDecls xs)

trTypedVars :: Ident i => Variable i -> Abs.TypedVars
trTypedVars x = Abs.TypedVars [trIdent $ varIdent x] (trType $ varType x)

trMaybeTypedVars :: Ident i => [Variable i] -> Abs.MaybeTypedVars
trMaybeTypedVars = mapDefault Abs.NoTypedVars (Abs.JustTypedVars . map trTypedVars)

trNode :: Ident i => (i, Node i) -> Abs.Node
trNode (x, n) =
  let inp = trMaybeTypedVars $ nodeInputs n
      outp = map trTypedVars $ nodeOutputs n
      decls = trDecls $ nodeDecls n
      flow = trFlow $ nodeFlow n
      outpDefs = trOutputs $ nodeOutputDefs n
      autom = trControlStructure $ nodeAutomata n
      init = trInitial $ nodeInitial n
  in Abs.Node (trIdent x) inp outp decls flow outpDefs autom init

trFlow :: Ident i => Flow i -> Abs.Flow
trFlow f = Abs.Flow (trLocalDefinitions $ flowDefinitions f) (trTransitions $ flowTransitions f)

trLocalDefinitions :: Ident i => [InstantDefinition i] -> Abs.LocalDefinitions
trLocalDefinitions = mapDefault Abs.NoLocalDefinitons (Abs.JustLocalDefinitons . map trInstantDefinition)

trTransitions :: Ident i => [StateTransition i] -> Abs.Transitions
trTransitions = mapDefault Abs.NoTransitions (Abs.JustTransitions . map trTransition)

trTransition :: Ident i => StateTransition i -> Abs.Transition
trTransition (StateTransition x e) = Abs.Transition (trStateId x) (trExpr e)

trOutputs :: Ident i => [InstantDefinition i] -> Abs.Outputs
trOutputs = mapDefault Abs.NoOutputs (Abs.JustOutputs . map trInstantDefinition)

trInstantDefinition :: Ident i => InstantDefinition i -> Abs.InstantDefinition
trInstantDefinition (InstantDef pat inst) = Abs.InstantDef (trPattern pat) (trInstant inst)

trPattern :: Ident i => Pattern i -> Abs.Pattern
trPattern [x] = Abs.SinglePattern $ trIdent x
trPattern xs = Abs.ProductPattern $ trList2Id xs

trList2Id :: Ident i => [i] -> Abs.List2Id
trList2Id [x,y] = Abs.Id2 (trIdent x) (trIdent y)
trList2Id (x:(y:xs)) = Abs.ConsId (trIdent x) (trList2Id $ y:xs)
trList2Id _ = undefined

trInstant :: Ident i => Instant i -> Abs.Instant
trInstant (Fix (InstantExpr e)) = Abs.InstantExpr $ trExpr e
trInstant (Fix (NodeUsage n params)) = Abs.NodeUsage (trIdent n) (map trExpr params)

trControlStructure :: Map Int (Automaton i) -> Abs.ControlStructure
trControlStructure = Abs.ControlStructure . map trAutomaton . Map.elems

trAutomaton :: Automaton i -> Abs.Automaton
trAutomaton = $notImplemented

trInitial :: Ident i => StateInit i -> Abs.Initial
trInitial = mapDefault Abs.NoInitial (Abs.JustInitial . map trStateInit . Map.toList)

trStateInit :: Ident i => (i, ConstExpr i) -> Abs.StateInit
trStateInit (x, c) = Abs.StateInit (trIdent x) (trConstExpr c)

trAssertion :: Ident i => Expr i -> Abs.Assertion
trAssertion = ite (== (constAtExpr $ boolConst True)) (const Abs.NoAssertion) (Abs.JustAssertion . trExpr)

trInvariant :: Ident i => Expr i -> Abs.Invariant
trInvariant = ite (== (constAtExpr $ boolConst True)) (const Abs.NoInvariant) (Abs.JustInvariant . trExpr)

trConstant :: Constant -> Abs.Constant
trConstant = trConstant' . unfix
  where
    trConstant' (BoolConst v) = Abs.BoolConst $ trBoolV v
    trConstant' (IntConst v) = Abs.IntConst $ trIntegerConst v
    trConstant' (RealConst v) = Abs.RealConst (trIntegerConst $ numerator v) (trIntegerConst $ denominator v)
    trConstant' (SIntConst s v) = Abs.SIntConst (trNatural $ s) (trIntegerConst v)
    trConstant' (UIntConst s v) = Abs.UIntConst (trNatural $ s) (trNatural v)

trExpr :: Ident i => Expr i -> Abs.Expr
trExpr = trExpr' . unfix
  where
    trExpr' :: Ident i => (GExpr i Constant (Atom i) (Expr i)) -> Abs.Expr
    trExpr' (AtExpr a) = Abs.AtExpr $ trAtom a
    trExpr' (LogNot e) = Abs.Expr1 Abs.Not (trExpr e)
    trExpr' (Expr2 o e1 e2) = Abs.Expr2 (trBinOp o) (trExpr e1) (trExpr e2)
    trExpr' (Ite c e1 e2) = Abs.Expr3 Abs.Ite (trExpr c) (trExpr e1) (trExpr e2)
    trExpr' (Constr ctr) = $notImplemented
    trExpr' (Select x f) = $notImplemented
    trExpr' (Project x i) = $notImplemented

trAtom :: Ident i => GAtom i Constant (Atom i) -> Abs.Atom
trAtom (AtomConst c) = Abs.AtomConst $ trConstant c
trAtom (AtomVar x) = Abs.AtomVar $ trIdent x

trBinOp :: BinOp -> Abs.BinOp
trBinOp x = case x of
  Or  -> Abs.Or
  And  -> Abs.And
  Xor  -> Abs.Xor
  Implies  -> Abs.Implies
  Equals  -> Abs.Equals
  Less  -> Abs.Less
  Greater  -> Abs.Greater
  LEq  -> Abs.LEq
  GEq  -> Abs.GEq
  Plus  -> Abs.Plus
  Minus  -> Abs.Minus
  Mul  -> Abs.Mul
  RealDiv  -> Abs.RealDiv
  IntDiv  -> Abs.IntDiv
  Mod  -> Abs.Mod

trConstExpr :: Ident i => ConstExpr i -> Abs.ConstExpr
trConstExpr (Fix (Const c)) = Abs.ConstExpr $ Abs.AtExpr $ Abs.AtomConst $ trConstant c
trConstExpr (Fix (ConstRecord ctor)) = $notImplemented
trConstExpr (Fix (ConstTuple tuple)) = $notImplemented