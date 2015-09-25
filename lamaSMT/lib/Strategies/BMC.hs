{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE FlexibleContexts #-}
module Strategies.BMC (BMC, assumeTrace, checkInvariant, bmcStep, assertPrecond, freshVars) where

import Data.Natural
import NatInstance
import Data.List (stripPrefix)
import qualified Data.Map as Map
import Data.Map (Map)
import qualified Data.Array as Array
import Data.Array (Array)

import Control.Monad.IO.Class
import Control.Monad (when, liftM)
import Control.Monad.State

import Language.SMTLib2
import Language.SMTLib2.Internals (SMTExpr(Var))

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

  check s env defs =
    let base = 0
        vars = varList env
    in do fresh <- freshVars vars
          check' s (getModel $ varEnv env) defs base (vars, fresh)

assumeTrace :: MonadSMT m => ProgDefs -> ([TypedExpr], [TypedExpr]) -> m ()
assumeTrace defs args =
  assertDefs args (flowDef defs) >>
  assertPrecond args (precondition defs)

bmcStep :: MonadSMT m =>
        (Map Natural StreamPos -> SMT (Model i))
        -> ProgDefs
        -> ([TypedExpr], [TypedExpr])
        -> m (Bool)
bmcStep getModel defs vars =
  do assumeTrace defs vars
     let invs = invariantDef defs
     liftSMT . stack
       $ checkInvariant vars invs-- >>=
       --checkGetModel getModel pastIndices

check' :: BMC
       -> (Map Natural StreamPos -> SMT (Model i))
       -> ProgDefs
       -> Natural
       -> ([TypedExpr], [TypedExpr])
       -> SMTErr (StrategyResult i)
check' s getModel defs i vars =
  do liftIO $ when (bmcPrintProgress s) (putStrLn $ "Depth " ++ show i)
     r <- bmcStep getModel defs vars
     case r of
       True -> next (check' s getModel defs) s i vars
       False -> return $ Failure i 

assertDefs :: MonadSMT m => ([TypedExpr], [TypedExpr]) -> [Definition] -> m ()
assertDefs i = mapM_ (assertDef i)

assertDef :: MonadSMT m => ([TypedExpr], [TypedExpr]) -> Definition -> m ()
assertDef = assertDefinition id

assertPrecond :: MonadSMT m => ([TypedExpr], [TypedExpr]) -> Definition -> m ()
assertPrecond = assertDefinition id

-- | Returns true, if the invariant holds
checkInvariant :: MonadSMT m => ([TypedExpr], [TypedExpr]) -> Definition -> m Bool
checkInvariant i p = liftSMT $ assertDefinition not' i p >> liftM not checkSat

checkGetModel :: MonadSMT m =>
              (Map Natural StreamPos -> SMT (Model i))
              -> Map Natural StreamPos
              -> Bool
              -> m (Maybe (Model i))
checkGetModel getModel indices r = liftSMT $
  if r then return Nothing else fmap Just $ getModel indices

next :: (Natural
             -> ([TypedExpr], [TypedExpr])
             -> SMTErr (StrategyResult i)
        )
        -> BMC
        -> Natural
        -> ([TypedExpr], [TypedExpr])
        -> SMTErr (StrategyResult i)
next checkCont s i vars =
  let i' = succ i
  in case bmcDepth s of
       Nothing -> do vars' <- freshVars $ snd vars
                     checkCont i' (snd vars, vars')
       Just l ->
         if i' < l
         then do vars' <- freshVars $ snd vars
                 checkCont i' (snd vars, vars')
         else return Success

freshVars :: MonadSMT m => [TypedExpr] -> m [TypedExpr]
freshVars vars = liftSMT $ mapM newVar vars
  where
    newVar (BoolExpr _)   = do new <- var
                               return $ BoolExpr new
    newVar (IntExpr _)    = do new <- var
                               return $ IntExpr new
    newVar (RealExpr _)   = do new <- var
                               return $ RealExpr new
    newVar (EnumExpr (Var _ k))  = do new <- varAnn k
                                      return $ EnumExpr new
                              --etAnn <- lookupEnumAnn et
    --                          new <- varAnn etAnn
    --                          return $ EnumExpr new
    newVar (ProdExpr arr) = do newList <- mapM newVar (Array.elems arr)
                               let newProd = mkProdExpr newList
                               return newProd
