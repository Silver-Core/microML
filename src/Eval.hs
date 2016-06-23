module Eval where

import Syntax

import Control.Monad.Identity
import qualified Data.Map as Map

data Value 
    = VNum Integer
  | VBool Bool
  | VDouble Double
  | VClosure String Expr TermEnv
  | VString String
  | VChar Char
  | VList [Identity Value]
  deriving (Eq, Ord)

type TermEnv = Map.Map String Value
type Interpreter t = Identity t

emptyTmenv :: TermEnv
emptyTmenv = Map.empty

instance Show Value where
    show (VNum n)      = show n
    show (VBool b)     = show b
    show (VDouble d)   = show d
    show (VString str) = show str
    show (VChar c)     = show c
    show (VList ls)    = show ls  -- this is not correct
    show VClosure{}    = "\ESC[1m<<closure>>\ESC[0m"

eval :: TermEnv -> Expr -> Interpreter Value
eval env expr = case expr of
    Lit (Number k)   -> return $ VNum k
    Lit (Double k)   -> return $ VDouble k
    Lit (String str) -> return $ VString str
    Lit (Char c)     -> return $ VChar c
    Lit (Boolean b)  -> return $ VBool b
    List xs          -> return $ VList $ map (eval env) xs
    Lam x body       -> return (VClosure x body env)
    Var x            -> 
        case Map.lookup x env of
          Just v -> return v
          Nothing -> return $ VString "value not found"
        {-let Just v = Map.lookup x env-}
        {-return v-}
    App func arg     -> do
        VClosure s exp env' <- eval env func
        args <- eval env arg
        let newEnv = Map.insert s args env'
        eval newEnv exp
    If cond tr fl    -> do
        VBool br <- eval env cond
        if br
           then eval env tr
           else eval env fl
    Op op a b  -> do
        a' <- eval env a
        b' <- eval env b
        case op of
          OpAdd -> return $ a' `add` b'
          OpSub -> return $ a' `sub`  b'
          OpMul -> return $ a' `mul`  b'
          OpDiv -> return $ a' `div'` b'
          OpMod -> return $ a' `mod'` b'
          OpExp -> return $ a' `exp'` b'
          OpOr  -> return $ a' `or'`  b'
          OpAnd -> return $ a' `and'` b'
          -- OpCom -> return $ 
          OpEq  -> return $ VBool $ a' == b'
          OpLe  -> return $ VBool $ a' <= b'
          OpLt  -> return $ VBool $ a' <  b'
          OpGe  -> return $ VBool $ a' >= b'
          OpGt  -> return $ VBool $ a' >  b'
    UnaryMinus ex -> do
        ex' <- eval env ex
        case ex' of
          VNum n    -> return $ VNum (negate n)
          VDouble d -> return $ VDouble (negate d)

    _     -> return $ VString "not yet supported"

-- helper functions --

or' (VBool a) (VBool b) = VBool $ a || b

and' (VBool a) (VBool b)  = VBool $ a && b

add :: Value -> Value -> Value
add (VNum a) (VNum b) = VNum $ a + b
add (VDouble a) (VDouble b) = VDouble $ a + b
add (VNum a) (VDouble b) = VDouble $ realToFrac a + b
add (VDouble a) (VNum b) = VDouble $ a + realToFrac b

sub :: Value -> Value -> Value
sub (VNum a) (VNum b) = VNum $ a - b
sub (VDouble a) (VDouble b) = VDouble $ a - b
sub (VNum a) (VDouble b) = VDouble $ realToFrac a - b
sub (VDouble a) (VNum b) = VDouble $ a - realToFrac b

mul :: Value -> Value -> Value
mul (VNum a) (VNum b) = VNum $ a * b
mul (VDouble a) (VDouble b) = VDouble $ a * b
mul (VNum a) (VDouble b) = VDouble $ realToFrac a * b
mul (VDouble a) (VNum b) = VDouble $ a * realToFrac b

div' :: Value -> Value -> Value
div' (VNum a) (VNum b) = VDouble $ realToFrac a / realToFrac b
div' (VDouble a) (VDouble b) = VDouble $ a / b
div' (VNum a) (VDouble b) = VDouble $ realToFrac a / b
div' (VDouble a) (VNum b) = VDouble $ a / realToFrac b

mod' :: Value -> Value -> Value
mod' (VNum a) (VNum b) = VNum $ a `mod` b

exp' :: Value -> Value -> Value
exp' (VNum a) (VNum b) = VNum $ a^b
exp' (VNum a) (VDouble b) = VDouble $ realToFrac a**b
exp' (VDouble a) (VNum b) = VDouble $ a ^ b
exp' (VDouble a) (VDouble b) = VDouble $ a**b

runEval :: TermEnv -> String -> Expr -> (Value, TermEnv)
runEval env x exp =
    let res = runIdentity (eval env exp)
     in (res, Map.insert x res env)
