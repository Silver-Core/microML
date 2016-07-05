{-# LANGUAGE OverloadedStrings #-}

module MicroML.Parser where

import Text.Parsec
import Text.Parsec.Text.Lazy (Parser)

import qualified Text.Parsec.Expr as Ex
import qualified Text.Parsec.Token as Tok

import Data.Char (isLower, isUpper, digitToInt)
import Data.List (foldl')
import Numeric (readOct, readHex)
import qualified Data.Text.Lazy as L

import Control.Monad.Identity (Identity)
import Control.Monad (void)

import MicroML.Lexer
import qualified MicroML.Lexer as Lx
import MicroML.Syntax
import MicroML.ListPrimitives

varName :: Parser String
varName = do
    name@(n:_) <- identifier
    if isLower n
       then return name
       else fail "a variable name must start with a lowercase letter"

constructorName :: Parser String
constructorName = do
    name@(n:_) <- identifier
    if isUpper n
       then return name
       else fail "a \ESC[1mconstructor\ESC[0m must start with a capital letter"

integer :: Parser Integer
integer = Tok.integer lexer

float :: Parser Double
float = Tok.float lexer

variable :: Parser Expr
variable = varName >>= \n -> return $ Var n

constructor :: Parser Expr
constructor = constructorName >>= \c -> return $ Constructor c

number :: Parser Expr
number = Lx.integer >>= \n -> return (Lit (LInt n))

double :: Parser Expr
double = float >>= \d -> return (Lit (LDouble d))

{- base formats use erlang style syntax, ie. 2#, 8# ad 16# -}
binary :: Parser Expr
binary = do
    _ <- string "2#"
    b <- many1 $ oneOf "10"
    return $ Lit (LInt $ readBin b)
        where readBin = foldl' (\x y -> x*2 + y) 0 . map (fromIntegral . digitToInt)

octal :: Parser Expr
octal = do
    _ <- string "8#"
    o <- many1 octDigit 
    return $ Lit (LInt $ baseToDec readOct o)

hex :: Parser Expr
hex = do
    _ <- string "16#"
    h <- many1 hexDigit
    return $ Lit (LInt $ baseToDec readHex h)

-- readHex and readOct return lists of tuples, so this function simply lifts out the
-- desired number
baseToDec :: (t -> [(c, b)]) -> t -> c
baseToDec f n = (fst . head) $ f n

charLit :: Parser Expr
charLit = do
    void $ char '\''
    c <- letter
    void $ char '\''
    return $ Lit (LChar c)

stringLit :: ParsecT L.Text u Identity Expr
stringLit = do
    void $ char '"'
    s <- many $ escaped <|> noneOf "\"\\"
    void $ char '"'
    return $ Lit (LString s)

escaped :: ParsecT L.Text u Identity Char
escaped = do
    void $ char '\\'
    x <- oneOf "\\\"nrt"
    return $ case x of
               '\\' -> x
               '"'  -> x
               'n'  -> '\n'
               'r'  -> '\r'
               't'  -> '\t'

bool :: Parser Expr
bool = (reserved "true" >> return (Lit (LBoolean True)))
    <|> (reserved "false" >> return (Lit (LBoolean False)))

list :: Parser Expr
list = do
    void $ string "["
    elems <- List <$> expr `sepBy` choice [string ",", string ", "]
    void $ string "]"
    return elems

lambda :: Parser Expr
lambda = do
  reservedOp "\\"
  args <- many varName
  reservedOp "->"
  body <- expr
  return $ foldr Lam body args

letin :: Parser Expr
letin = do
    reserved "let"
    x <- varName
    void $ reservedOp "="
    e1 <- expr
    reserved "in"
    e2 <- expr
    return $ Let x e1 e2

letrecin :: Parser Expr
letrecin = do
    reserved "let"
    reserved "rec"
    x <- identifier
    reservedOp "="
    e1 <- expr
    reserved "in"
    e2 <- expr
    return (Let x e1 e2)

ifthen :: Parser Expr
ifthen = do
    reserved "if"
    cond <- aexp
    reservedOp "then"
    tr <- aexp
    reserved "else"
    fl <- aexp
    return (If cond tr fl)

aexp :: Parser Expr
aexp =
      parens expr
  <|> bool
  <|> try binary <|> try octal <|> try hex <|> try double
  <|> number
  <|> ifthen
  <|> try listComp <|> list
  <|> try letrecin
  <|> letin
  <|> lambda
  <|> variable
  <|> stringLit
  <|> charLit

term :: Parser Expr
term = Ex.buildExpressionParser table aexp

infixOp :: String -> (a -> a -> a) -> Ex.Assoc -> Op a
infixOp x f = Ex.Infix (reservedOp x >> return f)

prefixOp :: String -> (a -> a) -> Ex.Operator L.Text () Identity a
prefixOp name func = Ex.Prefix ( do {reservedOp name; return func } )
    
table :: [[Op Expr]]
table = [ [ infixOp "^"   (Op OpExp) Ex.AssocLeft ]
        , [ infixOp "*"   (Op OpMul) Ex.AssocLeft
        ,   infixOp "/"   (Op OpDiv) Ex.AssocLeft
        ,   infixOp "%"   (Op OpMod) Ex.AssocLeft ]
        , [ infixOp "+"   (Op OpAdd) Ex.AssocLeft
        ,   infixOp "-"   (Op OpSub) Ex.AssocLeft ]
        , [ infixOp "<="  (Op OpLe)  Ex.AssocLeft
        ,   infixOp ">="  (Op OpGe)  Ex.AssocLeft
        ,   infixOp "<"   (Op OpLt)  Ex.AssocLeft
        ,   infixOp ">"   (Op OpGt)  Ex.AssocLeft ]
        , [ infixOp "=="  (Op OpEq)  Ex.AssocLeft 
        ,   infixOp "/="  (Op OpNotEq) Ex.AssocLeft ] 
        , [ infixOp "and" (Op OpAnd) Ex.AssocLeft   -- boolean operators
        ,   infixOp "or"  (Op OpOr)  Ex.AssocLeft 
        ,   infixOp "xor" (Op OpXor) Ex.AssocLeft]  
        , [ infixOp ":" (Op OpCons) Ex.AssocRight] -- cons operator
        , [ infixOp "." compose Ex.AssocRight] 
  , [ prefixOp "head" (ListOp Car)                -- list operators
        ,   prefixOp "tail" (ListOp Cdr) 
        ,   prefixOp "init" init'] ]

expr :: Parser Expr
expr = do
    es <- many1 term
    return (foldl1 App es)

listComp :: ParsecT L.Text () Identity Expr
listComp = do
    void $ string "["
    func <- expr
    void $ choice [string "| ", string " | "]
    item <- expr
    void $ string "<- " <|> string " <- "
    set <- expr
    void $ string "]"
    return $ ListComp func item set

compose = undefined

------------------
-- DECLARATIONS --
------------------

type Binding = (String, Expr)

letDecl :: Parser Binding
letDecl = do
    reserved "let"
    name <- varName
    args <- many varName
    void $ reservedOp "="
    body <- expr
    -- return (name, foldr Lam body args)
    if name `elem` (words . removeControlChar . show) body
       then return (name, FixPoint $ foldr Lam body (name:args))
       else return (name, foldr Lam body args)
           where removeControlChar = filter (\x -> x `notElem` ['(', ')', '\"'])

val :: Parser Binding
val = do
  ex <- expr
  return ("it", ex)

decl :: Parser Binding
decl = try letDecl <|> val

top :: Parser Binding
top = do
  x <- decl
  optional semi
  return x

modl ::  Parser [Binding]
modl = many top

parseProgram ::  FilePath -> L.Text -> Either ParseError [(String, Expr)]
parseProgram = parse (contents modl)
