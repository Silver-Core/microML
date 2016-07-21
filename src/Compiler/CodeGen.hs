{-# LANGUAGE OverloadedStrings #-}

module Compiler.CodeGen where

import Compiler.MicroBitHeader
import Compiler.CHelper
import MicroML.Syntax
import MicroML.Parser 

import Language.C.DSL 
import Control.Monad.Identity
import Control.Monad.Reader
import Control.Monad.Except

import qualified Data.Text.Lazy as L
import Data.Either (rights)
import qualified Data.Map as Map
import Data.Maybe (fromJust)
import Data.String (fromString)

import System.Exit

--------------------
-- COMPILER TYPES --
--------------------

type FuncName = String
type ErrorMsg = String
type FileName = L.Text
type CompEnv = Map.Map String Expr
type Compiler a = ReaderT CompEnv (ExceptT ErrorMsg Identity) a

--------------
-- COMPILER --
--------------

runCompiler :: CompEnv -> Compiler a -> Either ErrorMsg a
runCompiler env ev = runIdentity (runExceptT (runReaderT ev env))

hoistError :: Show a => Either a t -> t
hoistError (Right vl) = vl
hoistError (Left err) = error $ show err

compileMicroML :: (String, Expr) -> Compiler CExtDecl
compileMicroML (nm, expr) = do
    let newNm = fromString nm
    case expr of
      -- if there's only a name and a Lit expression, then it must be a variable declaration
      Lit (LInt n)     -> return $ export $ int newNm .= fromInteger n
      Lit (LDouble d)  -> return $ export $ double newNm .= realToFrac d
      Lit (LChar c)    -> return $ export $ char newNm .= chr c
      Lit (LString st) -> return $ export $ charPtr newNm .= str st
      App (Var n) body -> return $ export $ do
          let (func, retty) = fromJust $ Map.lookup n microBitAPI
          if nm == "main" 
             then makeMain func (resolve body)
             else fun [getRetType retty] nm [charPtr "str"] $ hBlock [ func # ["str"] ]
      -- function definition
      Lam n e -> return $ generateLam n e
      _ -> throwError "something strange has happened"

generateLam :: String -> Expr -> CExtDecl
generateLam _ _ = undefined

getRetType :: RetTy -> CDeclSpec
getRetType rt = fromJust $ lookup rt table
    where table = 
            [ ("void"   , voidTy)
            , ("int"    , intTy)
            , ("double" , doubleTy)
            , ("char"   , charTy) ]

makeFunProtos :: CExtDecl -> Maybe CExtDecl
makeFunProtos (CFDefExt (CFunDef specs declr _ _ a)) =
    Just . export $ CDecl specs [(Just declr, Nothing, Nothing)] a
makeFunProtos _ = Nothing

makeMain :: CExpr -> [CExpr] -> CFunDef
makeMain func bdy = 
    fun [intTy] "main" [] $ hBlock [
        microBitInit
      , func # bdy                            
      , releaseFiber
    ]

resolve :: Expr -> [CExpr]
resolve e = 
    case e of 
      Lit (LInt n)     -> [int' n]
      Lit (LDouble d)  -> [db d]
      Lit (LChar c)    -> [chr c]
      Lit (LString st) -> [str st]

---------------------
-- PRETTY PRINTING --
---------------------

renderC :: [CExtDecl] -> String
renderC = newlines . concatMap (show . pretty)

newlines :: String -> String
newlines xs = [c | v <- xs, c <- if v == ';' || v == '}' then v:"\n" else [v]]

writeCFile :: L.Text -> [CExtDecl] -> IO ()
writeCFile nf code = do
    let cFile = L.unpack nf ++ ".cpp"
    writeFile cFile $ microBitIncludes ++ renderC code

----------------------------
-- MAIN COMPILER FUNCTION --
----------------------------

compile :: L.Text -> L.Text -> IO ()
compile source fn = do
    let res = hoistError $ parseProgram "from source" source
    print res
    if null res
       then die $ red ++ "Exit Failure: " ++ unred ++ "the given file was empty, so there's nothing to compile!"
       else do 
           let code = map (runCompiler Map.empty . compileMicroML) res
           writeCFile fn $ rights code
