{-# LANGUAGE ViewPatterns #-}
module Strategies.BMC (BMC, assumeTrace, checkInvariant, bmcStep, assertPrecond) where

import Data.Natural
import NatInstance
import Data.List (stripPrefix)
import qualified Data.Map as Map
import Data.Map (Map)

import Control.Monad.IO.Class
import Control.Monad (when, liftM)

import Language.SMTLib2

import Strategy
import LamaSMTTypes
import Definition
import TransformEnv
import Model (Model, getModel)
import Internal.Monads

data BMC = BMC
           { bmcDepth :: Maybe Natural
           , bmcPrintProgress :: Bool }

instance StrategyClass BMC where
  defaultStrategyOpts = BMC Nothing False

  readOption (stripPrefix "depth=" -> Just d) s =
    case d of
      "inf" -> s { bmcDepth = Nothing }
      _ -> s { bmcDepth = Just $ read d }
  readOption "progress" s =
    s { bmcPrintProgress = True }
  readOption o _ = error $ "Invalid BMC option: " ++ o

  check natAnn s env defs =
    let base = 0
    in do baseDef <- liftSMT . defConst $ constantAnn base natAnn
          check' natAnn s env defs (Map.singleton base baseDef) base baseDef

assumeTrace :: MonadSMT m => ProgDefs -> [SMTExpr Bool] -> m ()
assumeTrace defs args =
  assertDefs args (flowDef defs) >>
  assertPrecond args (precondition defs)

bmcStep :: MonadSMT m =>
        Env i
        -> ProgDefs
        -> Map Natural StreamPos
        -> StreamPos
        -> m (Maybe (Model i))
bmcStep env defs pastIndices iDef =
  do assumeTrace defs $ varList env
     let invs = invariantDef defs
     liftSMT . stack
       $ checkInvariant (varList env) invs >>=
       checkGetModel (getModel $ varEnv env) pastIndices

check' :: SMTAnnotation Natural
       -> BMC
       -> Env i
       -> ProgDefs
       -> Map Natural StreamPos
       -> Natural
       -> StreamPos
       -> SMTErr (StrategyResult i)
check' natAnn s env defs pastIndices i iDef =
  do liftIO $ when (bmcPrintProgress s) (putStrLn $ "Depth " ++ show i)
     r <- bmcStep env defs pastIndices iDef
     case r of
       Nothing -> next (check' natAnn s env defs) natAnn s pastIndices i iDef
       Just m -> return $ Failure i m

assertDefs :: MonadSMT m => [SMTExpr Bool] -> [Definition] -> m ()
assertDefs i = mapM_ (assertDef i)

assertDef :: MonadSMT m => [SMTExpr Bool] -> Definition -> m ()
assertDef = assertDefinition id

assertPrecond :: MonadSMT m => [SMTExpr Bool] -> Definition -> m ()
assertPrecond = assertDefinition id

-- | Returns true, if the invariant holds
checkInvariant :: MonadSMT m => [SMTExpr Bool] -> Definition -> m Bool
checkInvariant i p = liftSMT $ assertDefinition not' i p >> liftM not checkSat

checkGetModel :: MonadSMT m =>
              (Map Natural StreamPos -> SMT (Model i))
              -> Map Natural StreamPos
              -> Bool
              -> m (Maybe (Model i))
checkGetModel getModel indices r = liftSMT $
  if r then return Nothing else fmap Just $ getModel indices

next :: (Map Natural StreamPos
             -> Natural
             -> SMTExpr Natural
             -> SMTErr (StrategyResult i)
        )
        -> SMTAnnotation Natural
        -> BMC
        -> Map Natural StreamPos
        -> Natural
        -> SMTExpr Natural
        -> SMTErr (StrategyResult i)
next checkCont natAnn s pastIndices i iDef =
  do let i' = succ i
     iDef' <- liftSMT . defConst$ succ' natAnn iDef
     let pastIndices' = Map.insert i' iDef' pastIndices
     case bmcDepth s of
       Nothing -> checkCont pastIndices' i' iDef'
       Just l ->
         if i' < l
         then checkCont pastIndices' i' iDef'
         else return Success
