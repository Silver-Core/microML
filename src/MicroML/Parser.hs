{-# LANGUAGE OverloadedStrings #-}

module MicroML.Parser (parseProgram) where

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
       else fail "a constructor must start with a capital letter"

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
    void spaces
    _ <- string "2#"
    b <- many1 $ oneOf "10" 
    void spaces
    return $ Lit (LInt $ readBin b)
        where readBin = foldl' (\x y -> x*2 + y) 0 . map (fromIntegral . digitToInt)

octal :: Parser Expr
octal = do
    void spaces
    _ <- string "8#"
    o <- many1 octDigit 
    void spaces
    return $ Lit (LInt $ baseToDec readOct o)

hex :: Parser Expr
hex = do
    void spaces
    _ <- string "16#"
    h <- many1 hexDigit
    void spaces
    return $ Lit (LInt $ baseToDec readHex h)

-- readHex and readOct return lists of tuples, so this function simply lifts out the
-- desired number
baseToDec :: (t -> [(c, b)]) -> t -> c
baseToDec f n = (fst . head) $ f n

charLit :: Parser Expr
charLit = do
    spaces
    void $ char '\''
    c <- letter
    void $ char '\'' 
    spaces
    return $ Lit (LChar c)

stringLit :: Parser Expr
stringLit = do
    void spaces
    void $ char '"'
    s <- many $ escaped <|> noneOf "\"\\"
    void $ char '"'
    void spaces
    return $ Lit (LString s)

escaped :: ParsecT L.Text u Identity Char
escaped = do
    void $ char '\\'
    x <- oneOf "\\\"nrt"
    return $ case x of
               ' '  -> x
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
    void $ spaces *> char '['
    elems <- commaSep expr
    void $ char ']' <* spaces
    return $ List $ foldr (BinOp OpCons) Nil elems

tuple :: Parser Expr
tuple = do
    void $ string "{"
    elems <- commaSep expr
    void $ string "}"
    void spaces
    return $ Lit $ LTup elems

lambda :: Parser Expr
lambda = do
    reservedOp "\\"
    args <- many varName
    reservedOp "->"
    body <- expr
    return $ foldr Lam body args

letrecin :: Parser Expr
letrecin = do
    reserved "let"
    x <- varName
    reservedOp "="
    void spaces
    e1 <- expr
    void spaces
    reserved "in"
    void spaces
    e2 <- expr
    void spaces
    return (Let x e1 e2)

ifthen :: Parser Expr
ifthen = do
    reserved "if"
    void spaces
    cond <- expr
    void spaces
    reservedOp "then"
    void spaces
    tr <- expr
    void spaces
    reserved "else"
    void spaces
    fl <- expr
    void spaces
    return (If cond tr fl)

aexp :: Parser Expr
aexp =
      parens expr
  <|> try tuple
  <|> bool
  <|> try binary 
  <|> try octal 
  <|> try hex 
  <|> try double
  <|> number
  <|> ifthen
  <|> try parseRange
  <|> list
  <|> try letrecin 
  <|> lambda
  <|> variable
  <|> stringLit
  <|> charLit
  <?> "an expression"

term :: Parser Expr
term = Ex.buildExpressionParser primitives aexp <?> "an expression or primitive type (such as a number)"

infixOp :: String -> (a -> a -> a) -> Ex.Assoc -> Op a
infixOp x f = Ex.Infix (reservedOp x >> return f)

prefixOp :: String -> (a -> a) -> Ex.Operator L.Text () Identity a
prefixOp name func = Ex.Prefix ( do {reservedOp name; return func } )
    
primitives :: [[Op Expr]]
primitives = [[ prefixOp "head"  (UnaryOp Car)
            ,   prefixOp "tail"  (UnaryOp Cdr)
            ,   prefixOp  "_read"  (UnaryOp Read)
            ,   prefixOp  "_show"  (UnaryOp Show)
            ,   prefixOp "_ord"  (UnaryOp Ord)
            ,   prefixOp "_chr"  (UnaryOp Chr)
            ,   prefixOp "-"     (UnaryOp Minus)
            ,   infixOp   ":"    (BinOp OpCons) Ex.AssocRight
            ,   infixOp   "++"   (BinOp OpAppend) Ex.AssocRight ]
            , [ prefixOp  "_log" (UnaryOp OpLog)
            ,   infixOp   "^"    (BinOp OpExp) Ex.AssocLeft ]     -- maths operators
            , [ infixOp   "*"    (BinOp OpMul) Ex.AssocLeft
            ,   infixOp   "//"   (BinOp OpIntDiv) Ex.AssocLeft
            ,   infixOp   "/"    (BinOp OpDiv) Ex.AssocLeft
            ,   infixOp   "%"    (BinOp OpMod) Ex.AssocLeft ]
            , [ infixOp   "+"    (BinOp OpAdd) Ex.AssocLeft
            ,   infixOp   "-"    (BinOp OpSub) Ex.AssocLeft ]
            , [ infixOp   "<="   (BinOp OpLe)  Ex.AssocLeft       -- boolean operators
            ,   infixOp   ">="   (BinOp OpGe)  Ex.AssocLeft
            ,   infixOp   "<"    (BinOp OpLt)  Ex.AssocLeft
            ,   infixOp   ">"    (BinOp OpGt)  Ex.AssocLeft ]
            , [ infixOp   "=="   (BinOp OpEq)  Ex.AssocLeft
            ,   infixOp   "/="   (BinOp OpNotEq) Ex.AssocLeft ]
            , [ infixOp   "and"  (BinOp OpAnd) Ex.AssocLeft
            ,   infixOp   "or"   (BinOp OpOr)  Ex.AssocLeft
            ,   infixOp   "xor"  (BinOp OpXor) Ex.AssocLeft
            ,   prefixOp  "not"  (UnaryOp Not) ]
            , [ infixOp   ">>"   (BinOp OpPipe) Ex.AssocLeft ]]

expr :: Parser Expr
expr = do
    es <- many1 term 
    return (foldl1 App es)

parseRange :: Parser Expr
parseRange = do
    void $ string "["
    start <- expr
    void $ reserved "to"
    end <- expr
    void $ string "]"
    return $ BinOp OpEnum start end

------------------
-- DECLARATIONS --
------------------

type Binding = (String, Expr)

-- placeholders for datatype parser
dataDecl :: Parser Binding
dataDecl = do
    name <- constructorName
    params <- many varName
    reservedOp "::="
    types <- datatype `sepBy` string "|"
    return (name, Constructor name)

datatype :: Parser Expr
datatype = do
    void spaces
    name <- constructorName
    params <- many varName
    void spaces
    return $ Constructor name

letDecl :: Parser Binding
letDecl = do
    reserved "let"
    name <- varName
    args <- many varName
    void $ reservedOp "="
    body <- expr
    if name `elem` (words . removeControlChar . show) body
       then return (name, FixPoint $ foldr Lam body (name:args))
       else return (name, foldr Lam body args)
           where removeControlChar = filter (\x -> x `notElem` ['(', ')', '\"'])

val :: Parser Binding
val = do
  ex <- expr
  return ("it", ex)

decl :: Parser Binding
decl = try val 
    <|> letDecl 
    <|> dataDecl
    <?> "a declaration"

top :: Parser Binding
top = do
  x <- decl
  optional semi
  return x

modl ::  Parser [Binding]
modl = many top

parseProgram ::  FilePath -> L.Text -> Either ParseError [(String, Expr)]
parseProgram = parse (contents modl)
