module ShowResult where

import qualified Data.Map.Lazy as Mz
import Language

showResults :: [GmState] -> [Char]
showResults sts@((_,_,_,gb,_):_)
  =iDisplay (iConcat [
                iStr "Supercombinator definitions", iNewline,
                Mz.foldr interIt iNil gb,
                iNewline,iNewline,iStr "State transitions",iNewline,iNewline,
                iLayn (map showState sts),iNewline,iNewline,
                showStatistic (last sts)])
   where
     interIt sc r
       | r == iNil = iConcat [showSc sc, r]
       | otherwise = iConcat [showSc sc, iNewline, r]
                
showSc :: GmState -> (Name, Addr) -> Iseq
showSc (_,_,hp,_,_) (name, addr)
  = iConcat [iStr "Code for ", iStr name, iNewline,
             showGmCode gmcode, iNewline, iNewline]
    where
      (NGlobal arity gmcode) = hLookup hp addr


showGmCode :: GmCode -> Iseq
showGmCode i
  = iConcat [iStr " Code:{",
             iIndent (foldl interIt i),
             iStr "}",iNewline]

showInstruction :: Instruction -> Iseq
showInstruction UnWind = iStr "Unwind"
showInstruction (Pushglobal f) = iConcat [iStr "Pushglobal ", iStr f]
showInstruction (Push n) = iConcat [iStr "Push ", iNum $ I n]
showInstruction (Pushcn cn) = iConcat [iStr "Pushcn ", iNum cn]
showInstruction Mkap = iStr "Mkap"
showInstruction (Slide n) = iConcat [iStr "Slide ", iNum $ I n]


showState :: GmState -> Iseq
showState st@(i,_,_,_,_)
  = iConcat [showStack st, iNewline,
             showGmCode i, iNewline]

showStack :: GmState -> Iseq
showStack st@(_,sk,_,_,_)
  = iConcat [iStr " Stack:[",
             iIndent, foldr interIt $ reverse sk,
             iStr "]"]
    where
      interIt
