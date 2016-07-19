{-# LANGUAGE OverloadedStrings #-}

module Compiler.MicroBitHeader where

import Language.C.DSL
import qualified Data.Map as Map


microBitIncludes :: String
microBitIncludes = "#include \"MicroBit.h\"\n\nMicroBit uBit;\n"

microBitAPI :: Map.Map String CExpr
microBitAPI = Map.fromList [
    ("scroll", _scroll)                       
    ]

_scroll :: CExpr
_scroll = "uBit.display.scroll" 

blank :: CExpr
blank = ""

microBitInit :: CExpr
microBitInit = "uBit.init()"

releaseFiber :: CExpr
releaseFiber = "release_fiber()"
