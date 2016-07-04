module Repl.Eval where

import MicroML.Syntax
import MicroML.ListPrimitives

import qualified Data.Map as Map
import Data.Maybe (fromMaybe)

emptyTmenv :: TermEnv
emptyTmenv = Map.empty

eval :: TermEnv -> Expr -> Expr
eval env expr = case expr of
    num@(Lit (LInt _))      -> num
    doub@(Lit (LDouble _))  -> doub
    char@(Lit (LChar _))    -> char
    str@(Lit (LString _))   -> str
    bool@(Lit (LBoolean _)) -> bool
    Var x                   -> fromMaybe (error "not yet been set") (Map.lookup x env)
    ls@(List _)             -> ls
    FixPoint e              -> eval env (App e (FixPoint e))
    Lam x body              -> Closure x body env
    App a b                 -> do
        let Closure n expr' clo = eval env a
        let arg = eval env b
        let new' = Map.insert n arg clo
        eval new' expr'
    If cond tr fls          -> do
        let cond' = eval env cond
        if cond' == Lit (LBoolean True)
           then eval env tr
           else eval env fls
    Let x e body            -> do
        let e' = eval env e
        let new' = Map.insert x e' env
        eval new' body
    ListOp op a -> do
        let a' = eval env a
        case op of
          Car -> car a'
          Cdr -> cdr a'
    Op op a b -> do
        let a' = eval env a
        let b' = eval env b
        case op of
          OpAdd -> a' `add` b'
          OpSub -> a' `sub`  b'
          OpMul -> a' `mul`  b'
          OpDiv -> a' `div'` b'
          OpMod -> a' `mod'` b'
          OpExp -> a' `exp'` b'
          {-OpOr  -> a' `or'`  b'-}
          {-OpAnd -> a' `and'` b'-}
          OpEq  -> Lit $ LBoolean $ a' == b'
          OpLe  -> Lit $ LBoolean $ a' <= b'
          OpLt  -> Lit $ LBoolean $ a' <  b'
          OpGe  -> Lit $ LBoolean $ a' >= b'
          OpGt  -> Lit $ LBoolean $ a' >  b'
          OpNotEq -> Lit $ LBoolean $ a' /= b'
    {-UnaryMinus ex -> do-}
        {-ex' <- eval env ex-}
        {-case ex' of-}
          {-Lit (LInt n)  -> Lit (LInt (negate n))-}
          {-VDouble d ->  (negate d)-}
    -- _     -> Default $ L.pack "not yet supported"

add :: Expr -> Expr -> Expr
add (Lit (LInt a)) (Lit (LInt b)) = Lit $ LInt $ a + b
add (Lit (LDouble a)) (Lit (LDouble b)) = Lit $ LDouble $ a + b
add (Lit (LInt a)) (Lit (LDouble b)) = Lit $ LDouble $ realToFrac a + b
add (Lit (LDouble a)) (Lit (LInt b)) = Lit $ LDouble $ a + realToFrac b
-- add _ _ = Default $ L.pack "weird"

{-or' (VBool a) (VBool b) = VBool $ a || b-}

{-and' (VBool a) (VBool b)  = VBool $ a && b-}

sub :: Expr -> Expr -> Expr
sub (Lit (LInt a)) (Lit (LInt b)) = Lit $ LInt $ a - b
sub (Lit (LDouble a)) (Lit (LDouble b)) = Lit $ LDouble $ a - b
sub (Lit (LInt a)) (Lit (LDouble b)) = Lit $ LDouble $ realToFrac a - b
sub (Lit (LDouble a)) (Lit (LInt b)) = Lit $ LDouble $ a - realToFrac b
-- sub _ _                  = Default $ L.pack "please check your calculation..."

mul :: Expr -> Expr -> Expr
mul (Lit (LInt a)) (Lit (LInt b)) = Lit $ LInt $ a * b
mul (Lit (LDouble a)) (Lit (LDouble b)) = Lit $ LDouble $ a * b
mul (Lit (LInt a)) (Lit (LDouble b)) = Lit $ LDouble $ realToFrac a * b
mul (Lit (LDouble a)) (Lit (LInt b)) = Lit $ LDouble $ a * realToFrac b
-- mul _ _                  = Default $ L.pack "please check your calculation..."

div' :: Expr -> Expr -> Expr
div' (Lit (LInt a)) (Lit (LInt b)) = Lit $ LDouble $ realToFrac a / realToFrac b
div' (Lit (LDouble a)) (Lit (LDouble b)) = Lit $ LDouble $ a / b
div' (Lit (LInt a)) (Lit (LDouble b)) = Lit $ LDouble $ realToFrac a / b
div' (Lit (LDouble a)) (Lit (LInt b)) = Lit $ LDouble $ a / realToFrac b
-- div' _ _                  = Default $ L.pack "please check your calculation..."

mod' :: Expr -> Expr -> Expr
mod' (Lit (LInt a)) (Lit (LInt b)) = Lit $ LInt $ a `mod` b
-- mod' _ _                  = Default $ L.pack "please check your calculation..."

exp' :: Expr -> Expr -> Expr
exp' (Lit (LInt a)) (Lit (LInt b)) = Lit $ LInt $ a^b
exp' (Lit (LInt a)) (Lit (LDouble b)) = Lit $ LDouble $ realToFrac a**b
exp' (Lit (LDouble a)) (Lit (LInt b)) = Lit $ LDouble $ a ^ b
exp' (Lit (LDouble a)) (Lit (LDouble b)) = Lit $ LDouble $ a**b
-- exp' _ _                  = Default $ L.pack "please check your calculation..."

runEval :: TermEnv -> String -> Expr -> (Expr, TermEnv)
runEval env x exp = 
    let res = eval env exp
     in (res, Map.insert x res env)