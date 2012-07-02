{- Translate generated data structures to internal structures
  while checking for undefined automaton locations and
  constant expressions. -}
module Lang.LAMA.Transform (absToConc, trConstExpr) where

import qualified Data.Map as Map
import Data.Map (Map)
import qualified Data.Set as Set
import Data.Natural
import Data.Ratio
import qualified Data.ByteString.Char8 as BS
import Prelude hiding (foldl, concat, any)
import Data.Foldable
import Control.Applicative hiding (Const)
import Control.Arrow (second)
import Control.Monad.Error (MonadError(..), ErrorT(..))
import Control.Monad.Reader (MonadReader(..), Reader, runReader)
import Control.Monad (when, liftM)

import qualified Lang.LAMA.Parser.Abs as Abs
import qualified Lang.LAMA.Parser.Print as Abs (printTree)
import Lang.LAMA.Identifier
import Lang.LAMA.Types
import Lang.LAMA.Structure.PosIdentUntyped

-- | Monad for the transformation process
--    Carries possible errors, declared types and constants.
data Env = Env { envEnums :: Set.Set EnumConstr, envConsts :: Map PosIdent Constant }

emptyEnv :: Env
emptyEnv = Env Set.empty Map.empty

type Result = ErrorT String (Reader Env)

askEnums :: Result (Set.Set EnumConstr)
askEnums = reader envEnums

localEnums :: Set.Set EnumConstr -> Result a -> Result a
localEnums es = local (\env -> env { envEnums = es })

askConsts :: Result (Map PosIdent Constant)
askConsts = reader envConsts

localConsts :: Map PosIdent Constant -> Result a -> Result a
localConsts cs = local (\env -> env { envConsts = cs })

mkEnumSet :: Map (TypeAlias PosIdent) EnumDef -> Set.Set EnumConstr
mkEnumSet = foldl getEnumCons Set.empty
  where
    getEnumCons cs (EnumDef ctors) = cs `Set.union` (Set.fromList ctors)

absToConc :: Abs.Program -> Either String Program
absToConc p = runReader (runErrorT $ transProgram p) emptyEnv

trConstExpr :: Abs.ConstExpr -> Either String ConstExpr
trConstExpr e = runReader (runErrorT $ transConstExpr e) emptyEnv

-- | Create identifier from position information and name
makeId :: ((Int, Int), BS.ByteString) -> PosIdent
makeId (pos, str) = PosIdent str pos

-- | Create identifier from position information and name without the last
--    character, this should be a "'" which is part of a state identifier
--    on the lhs in a state assignment.
makeStateId :: ((Int, Int), BS.ByteString) -> PosIdent
makeStateId (pos, str) = PosIdent (BS.init str) pos

--- Translation functions

transIdentifier :: Abs.Identifier -> Result PosIdent
transIdentifier x = case x of
  Abs.Identifier str  -> return $ makeId str


transStateId :: Abs.StateId -> Result PosIdent
transStateId x = case x of
  Abs.StateId str  -> return $ makeStateId str


transProgram :: Abs.Program -> Result Program
transProgram x = case x of
  Abs.Program typedefs constantdefs declarations flow initial assertion invariant -> do
    td <- transTypeDefs typedefs
    cs <- transConstantDefs constantdefs
    localEnums (mkEnumSet td) $ localConsts cs $
      Program td cs <$>
        (transDeclarations declarations) <*>
        (transFlow flow) <*>
        (transInitial initial) <*>
        (transAssertion assertion) <*>
        (transInvariant invariant)

transTypeDefs :: Abs.TypeDefs -> Result (Map (TypeAlias PosIdent) EnumDef)
transTypeDefs x = case x of
  Abs.NoTypeDefs  -> return Map.empty
  Abs.JustTypeDefs typedefs  -> fmap Map.fromList $ mapM transTypeDef typedefs

transTypeDef :: Abs.TypeDef -> Result (TypeAlias PosIdent, EnumDef)
transTypeDef x = case x of
  Abs.EnumDef identifier enumconstrs  ->
    (second EnumDef) <$> ((,) <$> transIdentifier identifier <*> mapM transEnumConstr enumconstrs)


transEnumConstr :: Abs.EnumConstr -> Result EnumConstr
transEnumConstr x = case x of
  Abs.EnumConstr identifier  -> EnumCons <$> transIdentifier identifier


transProdTypeList :: Abs.Type -> Abs.Type -> Result [Type PosIdent]
transProdTypeList (Abs.ProdType t1 t2) (Abs.ProdType t3 t4) = (++) <$> transProdTypeList t1 t2 <*> transProdTypeList t3 t4
transProdTypeList (Abs.ProdType t1 t2) t = (++) <$> transProdTypeList t1 t2 <*> ((:[]) <$> transType t)
transProdTypeList t (Abs.ProdType t1 t2) = (++) <$> ((:[]) <$> transType t) <*> transProdTypeList t1 t2
transProdTypeList t1 t2 = (\a b -> [a, b]) <$> transType t1 <*> transType t2


transType :: Abs.Type -> Result (Type PosIdent)
transType x = case x of
  Abs.GroundType basetype  -> fmap GroundType $ transBaseType basetype
  Abs.TypeId identifier  -> fmap EnumType $ transIdentifier identifier
  Abs.ArrayType basetype natural  ->
    ArrayType <$> (transBaseType basetype) <*> (transNatural natural)
  Abs.ProdType t1 t2  -> ProdType <$> transProdTypeList t1 t2


transBaseType :: Abs.BaseType -> Result BaseType
transBaseType x = case x of
  Abs.BoolT  -> return BoolT
  Abs.IntT  -> return IntT
  Abs.RealT  -> return RealT
  Abs.SInt natural  -> fmap SInt $ transNatural natural
  Abs.UInt natural  -> fmap UInt $ transNatural natural

transConstantDefs :: Abs.ConstantDefs -> Result (Map PosIdent Constant)
transConstantDefs x = case x of
  Abs.NoConstantDefs -> return Map.empty
  Abs.JustConstantDefs constantdefs -> fmap Map.fromList $ mapM transConstantDef constantdefs


transConstantDef :: Abs.ConstantDef -> Result (PosIdent, Constant)
transConstantDef x = case x of
  Abs.ConstantDef identifier constant ->
    (,) <$> transIdentifier identifier <*> transConstant constant


transNatural :: Abs.Natural -> Result Natural
transNatural x = case x of
  Abs.Nat n  -> return $ fromInteger n


transIntegerConst :: Abs.IntegerConst -> Result Integer
transIntegerConst x = case x of
  Abs.NonNegativeInt n  -> return n
  Abs.NegativeInt n  -> return $ -n


transConstant :: Abs.Constant -> Result Constant
transConstant = fmap Fix . transConstant'
  where
    transConstant' x = case x of
      Abs.BoolConst boolv  -> BoolConst <$> transBoolV boolv

      Abs.IntConst integerconst  -> IntConst <$> (transIntegerConst integerconst)

      Abs.RealConst integerconst0 integerconst  ->
        RealConst <$>
          ((%) <$> (transIntegerConst integerconst0) <*> (transIntegerConst integerconst))

      Abs.SIntConst natural integerconst  ->
        SIntConst <$> (transNatural natural) <*> (transIntegerConst integerconst)

      Abs.UIntConst natural0 natural  ->
        UIntConst <$> (transNatural natural0) <*> (transNatural natural)


transBoolV :: Abs.BoolV -> Result Bool
transBoolV x = case x of
  Abs.TrueV  -> return True
  Abs.FalseV  -> return False


transAssertion :: Abs.Assertion -> Result Expr
transAssertion x = case x of
  Abs.NoAssertion  -> return $ constAtExpr $ boolConst True
  Abs.JustAssertion expr  -> transExpr expr


transInitial :: Abs.Initial -> Result (Map PosIdent ConstExpr)
transInitial x = case x of
  Abs.NoInitial  -> return Map.empty
  Abs.JustInitial stateinits  -> fmap Map.fromList $ mapM transStateInit stateinits


transInvariant :: Abs.Invariant -> Result Expr
transInvariant x = case x of
  Abs.NoInvariant  -> return $ constAtExpr $ boolConst True
  Abs.JustInvariant expr  -> transExpr expr


transStateInit :: Abs.StateInit -> Result (PosIdent, ConstExpr)
transStateInit x = case x of
  Abs.StateInit identifier constexpr  -> do
    (,) <$> transIdentifier identifier <*> (transConstExpr constexpr)


transConstExpr :: Abs.ConstExpr -> Result ConstExpr
transConstExpr x = case x of
  Abs.ConstExpr expr  -> transExpr expr >>= evalConstM
  where
    evalConstM = liftM Fix . evalConst . unfix

    evalConst :: GExpr PosIdent Constant Atom Expr -> Result (GConstExpr PosIdent Constant ConstExpr)
    evalConst (AtExpr (AtomConst c)) = return $ Const c
    evalConst (AtExpr (AtomVar y)) = do
      enums <- askEnums
      if (EnumCons y) `Set.member` enums
      then return $ ConstEnum (EnumCons y)
        else throwError $ "Not a constant expression: " ++ show y
    evalConst (ProdCons (Prod cs)) = ConstProd . Prod <$> mapM evalConstM cs
    evalConst (ArrayCons (Array cs)) = ConstArray . Array <$> mapM evalConstM cs
    evalConst _ = throwError $ "Not a constant expression: " ++ Abs.printTree x


transTypedVars :: Abs.TypedVars -> Result [Variable]
transTypedVars x = case x of
  Abs.TypedVars identifiers t  -> do
    t' <- transType t
    let varCons = flip Variable $ t'
    fmap (map varCons) $ mapM transIdentifier identifiers


transMaybeTypedVars :: Abs.MaybeTypedVars -> Result [Variable]
transMaybeTypedVars x = case x of
  Abs.NoTypedVars  -> return []
  Abs.JustTypedVars typedvarss  -> fmap concat $ mapM transTypedVars typedvarss


transNode :: Abs.Node -> Result (PosIdent, Node)
transNode x = case x of
  Abs.Node identifier maybetypedvars typedvarss declarations flow outputs controlstructure initial ->
    (,) <$> (transIdentifier identifier) <*>
      (Node <$>
        (transMaybeTypedVars maybetypedvars) <*>
        (fmap concat $ mapM transTypedVars typedvarss) <*>
        (transDeclarations declarations) <*>
        (transFlow flow) <*>
        (transOutputs outputs) <*>
        (transControlStructure controlstructure) <*>
        (transInitial initial))

transDeclarations :: Abs.Declarations -> Result Declarations
transDeclarations x = case x of
  Abs.Declarations nodedecls localdecls statedecls ->
    Declarations <$>
      transNodeDecls nodedecls <*>
      transLocalDecls localdecls <*>
      transStateDecls statedecls

transVarDecls :: Abs.VarDecls -> Result [Variable]
transVarDecls x = case x of
  Abs.SingleDecl typedvars  -> transTypedVars typedvars
  Abs.ConsDecl typedvars vardecls  -> do
    vs <- transTypedVars typedvars
    vss <- transVarDecls vardecls
    return $ vs ++ vss


transNodeDecls :: Abs.NodeDecls -> Result (Map PosIdent Node)
transNodeDecls x = case x of
  Abs.NoNodes  -> return Map.empty
  Abs.JustNodeDecls nodes  -> fmap Map.fromList $ mapM transNode nodes


transStateDecls :: Abs.StateDecls -> Result [Variable]
transStateDecls x = case x of
  Abs.NoStateDecls  -> return []
  Abs.JustStateDecls vardecls  -> transVarDecls vardecls


transLocalDecls :: Abs.LocalDecls -> Result [Variable]
transLocalDecls x = case x of
  Abs.NoLocals  -> return []
  Abs.JustLocalDecls vardecls  -> transVarDecls vardecls


transFlow :: Abs.Flow -> Result Flow
transFlow x = case x of
  Abs.Flow localdefinitions transitions  ->
    Flow <$>
      (transLocalDefinitions localdefinitions) <*>
      (transTransitions transitions)

transLocalDefinitions :: Abs.LocalDefinitions -> Result [InstantDefinition]
transLocalDefinitions x = case x of
  Abs.NoLocalDefinitons  -> return []
  Abs.JustLocalDefinitons instantdefinitions  -> mapM transInstantDefinition instantdefinitions


transTransitions :: Abs.Transitions -> Result [StateTransition]
transTransitions x = case x of
  Abs.NoTransitions  -> return []
  Abs.JustTransitions transitions  -> mapM transTransition transitions


transOutputs :: Abs.Outputs -> Result [InstantDefinition]
transOutputs x = case x of
  Abs.NoOutputs  -> return []
  Abs.JustOutputs instantdefinitions  -> mapM transInstantDefinition instantdefinitions


transInstantDefinition :: Abs.InstantDefinition -> Result InstantDefinition
transInstantDefinition x = case x of
  Abs.InstantDef identifier instant  -> InstantDef <$> (transIdentifier identifier) <*> (transInstant instant)


transInstant :: Abs.Instant -> Result Instant
transInstant x = case x of
  Abs.InstantExpr expr  -> Fix . InstantExpr <$> transExpr expr
  Abs.NodeUsage identifier exprs  ->
    Fix <$> (NodeUsage <$> transIdentifier identifier <*> mapM transExpr exprs)


transTransition :: Abs.Transition -> Result StateTransition
transTransition x = case x of
  Abs.Transition stateid expr  ->
    StateTransition <$> (transStateId stateid) <*> (transExpr expr)


transControlStructure :: Abs.ControlStructure -> Result (Map Int Automaton)
transControlStructure x = case x of
  Abs.ControlStructure automatons  -> liftM (Map.fromDistinctAscList . zip (iterate (+1) 0)) $ mapM transAutomaton automatons


transAutomaton :: Abs.Automaton -> Result Automaton
transAutomaton x = case x of
  Abs.Automaton locations initiallocation edges  -> do
    locs <- mapM transLocation locations
    Automaton locs <$>
      (transInitialLocation locs initiallocation) <*>
      (mapM (transEdge locs) edges)


transLocation :: Abs.Location -> Result Location
transLocation x = case x of
  Abs.Location identifier flow  ->
    Location <$> (transIdentifier identifier) <*> (transFlow flow)

isKnownLocation :: [Location] -> LocationId -> Result ()
isKnownLocation locs loc =
  when (not $ any (\(Location l _) -> l == loc) locs)
    (throwError $ "Unknown location " ++ identPretty loc)

transInitialLocation :: [Location] -> Abs.InitialLocation -> Result LocationId
transInitialLocation locs x = case x of
  Abs.InitialLocation identifier  -> do
    loc <- transIdentifier identifier
    isKnownLocation locs loc
    return loc


transEdge :: [Location] -> Abs.Edge -> Result Edge
transEdge locs x = case x of
  Abs.Edge identifier0 identifier expr  -> do
    t <- transIdentifier identifier0
    isKnownLocation locs t
    h <- transIdentifier identifier
    isKnownLocation locs h
    e <- transExpr expr
    return $ Edge t h e


transAtom :: Abs.Atom -> Result Atom
transAtom x = case x of
  Abs.AtomConst constant  -> Fix . AtomConst <$> transConstant constant
  Abs.AtomVar identifier  -> do
    y <- transIdentifier identifier
    cs <- askConsts
    case Map.lookup y cs of
      Nothing -> return $ Fix $ AtomVar y
      Just c -> return $ Fix $ AtomConst c

transExpr :: Abs.Expr -> Result Expr
transExpr = fmap Fix . transExpr'
  where
    transExpr' x = case x of
      Abs.AtExpr atom -> (AtExpr . unfix) <$> transAtom atom

      Abs.Expr1 Abs.Not expr ->
        LogNot <$> (transExpr expr)

      Abs.Expr2 binop expr0 expr ->
        Expr2 <$> transBinOp binop <*> transExpr expr0 <*> transExpr expr

      Abs.Expr3 Abs.Ite expr0 expr1 expr  ->
        Ite <$> transExpr expr0 <*> transExpr expr1 <*> transExpr expr

      Abs.Prod exprs  -> ProdCons . Prod <$> mapM transExpr exprs

      Abs.Match expr patterns  ->
        Match <$> transExpr expr <*> mapM transPattern patterns

      Abs.Array exprs  -> ArrayCons . Array <$> mapM transExpr exprs

      Abs.Project identifier natural  ->
        Project <$> transIdentifier identifier <*> transNatural natural

      Abs.Update identifier natural expr  ->
        Update <$> transIdentifier identifier <*> transNatural natural <*> transExpr expr


transPattern :: Abs.Pattern -> Result Pattern
transPattern x = case x of
  Abs.Pattern pathead expr  -> Pattern <$> transPatHead pathead <*> transExpr expr


transPatHead :: Abs.PatHead -> Result PatHead
transPatHead x = case x of
  Abs.EnumPat enumconstr  -> EnumPat <$> transEnumConstr enumconstr
  Abs.ProdPat list2id  -> ProdPat <$> transList2Id list2id

transList2Id :: Abs.List2Id -> Result [PosIdent]
transList2Id x = case x of
  Abs.Id2 identifier1 identifier2  -> do
    ident1 <- transIdentifier identifier1
    ident2 <- transIdentifier identifier2
    return [ident1, ident2]
  Abs.ConsId identifier list2id  -> (:) <$> (transIdentifier identifier) <*> (transList2Id list2id)


transBinOp :: Abs.BinOp -> Result BinOp
transBinOp = return . transBinOp'
  where
    transBinOp' :: Abs.BinOp -> BinOp
    transBinOp' x = case x of
      Abs.Or  -> Or
      Abs.And  -> And
      Abs.Xor  -> Xor
      Abs.Implies  -> Implies
      Abs.Equals  -> Equals
      Abs.Less  -> Less
      Abs.Greater  -> Greater
      Abs.LEq  -> LEq
      Abs.GEq  -> GEq
      Abs.Plus  -> Plus
      Abs.Minus  -> Minus
      Abs.Mul  -> Mul
      Abs.RealDiv  -> RealDiv
      Abs.IntDiv  -> IntDiv
      Abs.Mod  -> Mod

