module GM where

import CoreUtils
{-
runProg :: String -> IO ()
runProg inp = case parse pProgram inp of
                Result _ r -> putStrLn $ showResults $ eval $ compile r
                _ -> error "These is someting error in your program"
n-}

eval :: GmState -> [GmState]
eval state = state : rest
  where
    rest | gmFinal state = []
         | otherwise = eval nextState
    nextState = doAdmin $ step state

doAdmin :: GmState -> GmState
doAdmin (i,sk,hp,gb,sic) = (i,sk,hp,gb,sic+1)

gmFinal :: GmState -> Bool
gmFinal (i,_,_,_,_) = null i

step :: GmState -> GmState
step (i:is,sk,hp,gb,sic) = dispatch i (is,sk,hp,gb,sic)


dispatch :: Instruction -> GmState -> GmState
dispatch (Pushglobal f) = pushglobal f
dispatch (Pushcn n) = pushcn n
dispatch Mkap = mkap
dispatch (Push n) = push n
{-
dispatch (Slide n) = slide n
dispatch UnWind = unwind
-}

pushglobal :: Name -> GmState -> GmState
pushglobal f (i,sk,hp,gb,sic)
  = (i,a:sk,hp,gb,sic)
  where
    a = aLookup (error $ "Undeclared global: " ++ f) f id gb

pushcn :: CN -> GmState -> GmState
pushcn cn (i,sk,hp,gb,sic)
  = (i,a:sk,new_hp,gb,sic)
  where
    (new_hp, a) = hAlloc (NNum cn) hp

mkap :: GmState -> GmState
mkap (i,a1:a2:as,hp,gb,sic)
  = (i,a:as,new_hp,gb,sic)
  where
    (new_hp,a) = hAlloc (NAp a1 a2) hp

push :: Int -> GmState -> GmState
push n (i,sk,hp,gb,sic)
  = (i,a:sk,hp,gb,sic)
  where
    (_, a) = getNAp $ hLookup (sk !! (n+1)) hp


