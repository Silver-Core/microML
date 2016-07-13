module MicroML.Syntax where

import qualified Data.Map as Map

type TermEnv = Map.Map String Expr

type Name = String
type VarName = String
type ConName = String

data Expr
  = Var Name
  | Constructor Name
  | App Expr Expr
  | Lam Name Expr
  | Let Name Expr Expr
  | Lit Lit
  | List [Expr]
  | If Expr Expr Expr
  | FixPoint Expr
  | Op Binop Expr Expr
  | UnaryOp UnaryOp Expr
  | ListComp Expr Expr Expr
  | Closure Name Expr TermEnv
  | PrimitiveErr MLError
  deriving (Show, Eq, Ord)

data Lit
  = LInt Integer
  | LDouble Double
  | LBoolean Bool
  | LString String
  | LChar Char
  | LTup [Expr]

  deriving (Show, Eq, Ord)

data UnaryOp =
        Car 
      | Cdr
      | Minus
      | Not
    deriving (Show, Eq, Ord)

data Binop = 
        OpAdd | OpSub | OpMul | OpDiv | OpIntDiv | OpExp 
      | OpMod | OpLog   -- maths primitives
      | OpOr | OpXor | OpAnd | OpEq | OpLe | OpLt | OpGe 
      | OpGt | OpNotEq | OpCons | OpComp | OpAppend
      deriving (Eq, Ord, Show)      

data MLError
    = MathsPrim String 
    | ListPrim String
    deriving (Eq, Ord)

instance Show MLError where
    show (MathsPrim str) = show str
    show (ListPrim str)  = show str

data Program = Program [Decl] Expr deriving Eq

type Decl = (String, Expr)
