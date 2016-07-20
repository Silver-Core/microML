{-# LANGUAGE OverloadedStrings #-}

module Compiler.CodeGen where

import Compiler.MicroBitHeader
import MicroML.Syntax
import MicroML.Parser 

import Language.C.DSL 
import Control.Monad.Identity
import Control.Monad.Reader
import Control.Monad.Except

import qualified Data.Text.Lazy as L
import Data.Either (rights)
import qualified Data.Map as Map
import Data.Maybe (mapMaybe)
import Data.String (fromString)

--------------------
-- COMPILER TYPES --
--------------------

type FuncName = String
type ErrorMsg = String
type FileName = L.Text
type Env = Map.Map String Expr
type Compiler a = ReaderT Env (ExceptT ErrorMsg Identity) a

--------------
-- COMPILER --
--------------

runCompiler :: Env -> Compiler a -> Either ErrorMsg a
runCompiler env ev = runIdentity (runExceptT (runReaderT ev env))

hoistError :: Show a => Either a t -> t
hoistError (Right vl) = vl
hoistError (Left err) = error $ show err

compileMicroML :: (String, Expr) -> Compiler CExtDecl
compileMicroML (nm, expr) = do
    let newNm = fromString nm
    case expr of
      -- if there's only a name and a literal, these must be variable declarations
      Lit (LInt n)     -> return $ export $ int newNm .= fromInteger n
      Lit (LDouble d)  -> return $ export $ double newNm .= realToFrac d
      Lit (LChar c)    -> return $ export $ char newNm .= chr c
      Lit (LString st) -> return $ export $ charPtr newNm .= str st
      Lam n e -> return $ generateLam n e
      Op op a b -> 
          case op of
            OpAdd -> return $ export $ makeAddFunc nm a b
      _ -> throwError "something strange has happened"

generateLam :: String -> Expr -> CExtDecl
generateLam n exp = undefined

makeAddFunc :: String -> Expr -> Expr -> CFunDef
makeAddFunc name e1 e2 = 
    case (e1, e2) of
      (Lit (LInt _), Lit (LInt _)) -> 
          fun [intTy] name [int "a", int "b"] $ hBlock [
            creturn ("a" + "b")
          ]

chr :: Char -> CExpr
chr = CConst . flip CCharConst undefNode . cChar

makeMain :: [CExtDecl] -> [(CDecl, Maybe String, CExpr)] -> [CExtDecl]
makeMain decls inits =
    mapMaybe makeFunProtos decls
    ++ map makeProts inits
    ++ [export $ fun [intTy] "main" [] (makeBlock inits)]
        where makeBlock = hBlock . concatMap buildExp
              buildExp (_, v, ex) = maybe [ex] ((:[]) . (<-- ex) . fromString) v
              makeProts = export . (\(a, _, _) -> a)

makeFunProtos :: CExtDecl -> Maybe CExtDecl
makeFunProtos (CFDefExt (CFunDef specs declr _ _ a)) =
    Just . export $ CDecl specs [(Just declr, Nothing, Nothing)] a
makeFunProtos _ = Nothing

renderC :: [CExtDecl] -> String
renderC = newlines . concatMap (show . pretty)

newlines :: String -> String
newlines xs = [c | v <- xs, c <- if v == ';' || v == '}' then v:"\n" else [v]]

writeCFile :: L.Text -> [CExtDecl] -> IO ()
writeCFile nf code = do
    let cFile = L.unpack nf ++ ".cpp"
    writeFile cFile $ microBitIncludes ++ renderC code

compile :: L.Text -> FileName -> IO ()
compile source fn = do
    let res = parseProgram "from source" source
    case res of
      Right prog -> do
          let code = map (runCompiler Map.empty . compileMicroML) prog
          writeCFile fn $ rights code
      Left err  -> putStr $ show err
