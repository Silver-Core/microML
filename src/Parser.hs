module Parser (
    parseProgram
) where

import Syntax
import Lexer
import Data.Functor.Identity (Identity)
import Data.Char (isLower, isUpper)
import Text.Megaparsec
import Text.Megaparsec.Expr
import Control.Monad (void)

type MLParser = ParsecT Dec String Identity
type FileName = String
type Input = String

varName :: MLParser String
varName = do name@(n:_) <- identifier
             if isLower n
                then return name
                else fail "a variable must start with a lowercase letter"

constructorName :: MLParser String
constructorName = do name@(n:_) <- identifier
                     if isUpper n 
                        then return name
                        else fail "a constructor must begin with a capital letter" 

variable :: MLParser Expr
variable = varName >>= \var -> return $ Var var

constructor :: MLParser Expr
constructor = constructorName >>= \c -> return $ Constructor c

number :: MLParser Expr
number = integer >>= \n -> return (Lit (Number n))

double :: MLParser Expr
double = float >>= \d -> return (Lit (Double d))

------------------------
-- EXPRESSION PARSERS --
------------------------

atomicExpr =
        parens expr
    <|> bool
    <|> try double <|> number
    <|> ifThenElse
    <|> lambda
    <|> variable
    <|> charLit
    <|> stringLit

term = makeExprParser atomicExpr table
    where 
        table = [ [ Prefix (symbol "-" *> pure UnaryMinus)
                ,   Prefix (symbol "+" >> return id) ]
                , [ InfixL (symbol "^" *> pure (Op OpExp)) ] 
                , [ InfixL (symbol "*" *> pure (Op OpMul))
                ,   InfixL (symbol "/" *> pure (Op OpDiv))
                ,   InfixL (symbol "%" *> pure (Op OpMod)) ]
                , [ InfixL (symbol "+" *> pure (Op OpAdd))
                ,   InfixL (symbol "-" *> pure (Op OpSub)) ] 
                , [ InfixL (symbol "<=" *> pure (Op OpLe))
                ,   InfixL (symbol ">=" *> pure (Op OpGe))
                ,   InfixL (symbol "<"  *> pure (Op OpLt))
                ,   InfixL (symbol ">"  *> pure (Op OpGt)) ]
                , [ InfixL (symbol "==" *> pure (Op OpEq)) ] 
                , [ InfixL (reservedWord "and" *> pure (Op OpAnd))
                ,   InfixL (reservedWord "or"  *> pure (Op OpOr))] ]


bool :: MLParser Expr
bool = (reservedWord "true" *> pure (Lit (Boolean True)))
   <|> (reservedWord "false" *> pure (Lit (Boolean False)))

---------------------
-- GENERAL PARSERS --
---------------------

charLit :: MLParser Expr
charLit = do
    void $ symbol "'"
    c <- alphaNumChar <|> spaceChar
    void $ symbol "'"
    return $ Lit $ Char c

stringLit :: MLParser Expr
stringLit = do
    void $ symbol "\""
    str <- many $ alphaNumChar <|> spaceChar
    void $ symbol "\""
    return $ Lit $ String str

lambda :: MLParser Expr
lambda = do
  void $ symbol "\\"
  args <- many identifier
  void arrow
  body <- expr
  return $ foldr Lam body args

ifThenElse :: MLParser Expr
ifThenElse = do
    reservedWord "if"
    cond <- atomicExpr
    reservedWord "then"
    tr <- atomicExpr
    reservedWord "else"
    fl <- atomicExpr
    return $ If cond tr fl

expr :: MLParser Expr
expr = do
    es <- some term
    return $ foldl1 App es

type Binding = (String, Expr)

letDecl :: MLParser Binding
letDecl = do
    reservedWord "let"
    name <- varName
    args <- many varName
    void $ symbol "="
    body <- expr
    return (name, foldr Lam body args)

letRecDecl :: MLParser (String, Expr)
letRecDecl = do
  reservedWord "rec"
  name <- varName
  args <- many varName
  void $ symbol "="
  body <- expr
  return (name, FixPoint $ foldr Lam body (name:args))

mainDecl :: MLParser Binding
mainDecl = do
    reservedWord "main"
    void $ symbol "="
    body <- expr
    return ("main", body)

val :: MLParser Binding
val = do
    ex <- expr
    return ("it", ex) --  same syntax here as in ghci

decl :: MLParser Binding
decl = try letRecDecl <|> try letDecl <|> val <|> mainDecl

topLevel :: MLParser Binding
topLevel = do 
    x <- decl
    void $ optional $ symbol ";"
    return x

--------------------------
-- TOP SIGNATURE PARSER --
--------------------------

{-typeParser = do-}
    {-types <- type' `sepBy1` arrow-}
    {-return $ foldr1 TypFun tys-}
        {-where type' = makeExprParser terms table <?> "type expression"-}
              {-table = [ [ InfixR (whiteSpace >> return TApp) ] ]-}
              {-term = parens ty <|> listTy <|> try primitiveTy <|> try tyVar <|> dataTy-}
              {-listTy = TyList <$> brackets ty-}
              {-tyVar = TyVar <$> TvName <$> varName-}
              {-dataTy = TyData <$> constructorName-}
              {-primitiveTy = (reservedWord "Number" >> return (TyPrimitive TyNum))-}
                        {-<|> (reservedWord "Boolean" >> return (TyPrimitive TyBool))-}

program :: MLParser [Binding]
program = many topLevel

parseProgram :: FileName -> Input -> Either (ParseError Char Dec) [Binding]
parseProgram = parse (contents program) 

