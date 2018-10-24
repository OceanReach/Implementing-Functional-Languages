{-# LANGUAGE ExistentialQuantification #-}

--处理多层括号仍然有问题

module GM02 where

import CoreParser
import Language

import qualified Data.Map.Lazy as Mz
import qualified Data.Map.Internal.Debug as Mid


type Addr = Int
type TiStack = [Addr]

data TiDump = DummyTiDump

--Heap的组成 (size, [free address], Mz.Map address Node)
--Node的的组成 NAp Addr Addr | NSupercomb Name [Name] CoreExpr | NNum a

data Node = NAp Addr Addr
          | NSupercomb Name [Name] CoreExpr
          | forall a . (Num a, Show a) => NNum a

type Heap a = (Int, [Addr], Mz.Map Addr a)
type TiHeap = Heap Node

--包含了全部的函数名以及对应的地址
type TiGlobals = Mz.Map Name Addr

--统计结果
type TiStatics = Int

type TiState = (TiStack, TiDump, TiHeap, TiGlobals, TiStatics)

runProg :: String -> IO ()
runProg file = case parse pProgram file of
                 Result remind result -> putStrLn $ showResults $ eval $ compile result
                 _ -> error "There is someting error"


initialTiDump :: TiDump
initialTiDump = DummyTiDump

tiStatInitial :: TiStatics
tiStatInitial = 0

tiStatIncSteps :: TiStatics -> TiStatics
tiStatIncSteps s = s + 1

tiStatGetSteps :: TiStatics -> Int
tiStatGetSteps s = s


applyTostatics :: (TiStatics -> TiStatics) -> TiState -> TiState
applyTostatics stats_fun (stack, dump, heap, sc_defs, stats)
  = (stack,dump,heap,sc_defs, stats_fun stats)


compile :: CoreProgram -> TiState
compile program = (initial_stack, initialTiDump, initial_heap, globals, tiStatInitial)
  where
    initial_stack = aLookup (error "\"main\" function doesn't exist") "main" (\x -> [x]) globals

    extraPreludeDefs = []
    sc_defs = preludeDefs ++ extraPreludeDefs ++ program
    (initial_heap, globals) = buildInitialHeap sc_defs

buildInitialHeap :: [CoreScDefn] -> (TiHeap, TiGlobals)
buildInitialHeap = foldl make (hInitial, Mz.empty::TiGlobals)
  where
    make (h, gb) scf = let (h', (name,addr)) = allocateSc h scf
                       in (h', Mz.insert name addr gb)
                          
allocateSc :: TiHeap -> CoreScDefn -> (TiHeap, (Name, Addr))
allocateSc heap (name, args, body) = (heap', (name, addr))
  where
    (heap', addr) = hAlloc heap (NSupercomb name args body)

--可不可以在这里修改，改为入栈一样的操作，使得最后的结果处于栈顶
eval :: TiState -> [TiState]
eval state = state:rest_states
  where
    rest_states
      | isFinal state = []
      | otherwise = eval next_state

    next_state = doAdmin $ step state

    doAdmin :: TiState -> TiState
    doAdmin state = applyTostatics tiStatIncSteps state

{-
相比于上面，这并不是一个好的定义方式
但，尚不清楚理由
eval :: TiState -> [TiState]
eval state
  | isFinal state = [state]
  | otherwise = state : eval next_state
  where
    next_state = doAdmin $ step state

    doAdmin :: TiState -> TiState
    doAdmin state = applyTostatics tiStatIncSteps state
-}

isFinal :: TiState -> Bool
isFinal ([sole_addr],_,hp,_,_)
  = isDataNode (hLookup hp sole_addr)
isFinal ([],_,_,_,_) = error "Empty Stack"
isFinal _ = False

step :: TiState -> TiState
step state@(sk,dp,hp,gb,sic)
  = dispatch (hLookup hp (head sk))
  where
    dispatch (NNum n) = numStep state n
    dispatch (NAp a1 a2) = apStep state a1 a2
    dispatch (NSupercomb sc args body) = scStep state sc args body

numStep :: (Num a, Show a) => TiState -> a -> TiState
numStep _ _ = error "Number applied as a function"

apStep :: TiState -> Addr -> Addr -> TiState
apStep (sk,dp,hp,gb,sic) a1 a2
  = ((a1:sk),dp,hp,gb,sic)

scStep :: TiState -> Name -> [Name] -> CoreExpr -> TiState
scStep (sk,dp,hp,gb,sic) sc_name arg_names body
  = (new_sk,dp,new_hp,gb,sic)
    where
      new_sk = result_addr : (drop (length arg_names + 1) sk)
      (new_hp, result_addr) = instantiate body hp env
      env = foldl (\g (k,a) -> Mz.insert k a g) gb arg_bindings
      arg_bindings = maybe
                     (error ("The number of arguments have some errors\n"
                             ++ Mid.showTree gb))
                     id
                     (checkAndzip arg_names (getargs hp sk))

getargs :: TiHeap -> TiStack -> [Addr]
getargs heap (sc:sk)
  = map get_arg sk
    where
      get_arg addr = arg
        where
          (NAp fun arg) = hLookup heap addr


instantiate :: CoreExpr -> TiHeap -> TiGlobals -> (TiHeap, Addr)
instantiate (A (ENum n)) heap env = hAlloc heap (NNum n)
instantiate (EAp e1 e2) heap env = hAlloc heap2 (NAp a1 a2)
  where
    (heap1, a1) = instantiate e1 heap env
    (heap2, a2) = instantiate e2 heap1 env

instantiate (A (EVar v)) heap env = (heap, aLookup
                                           (error $ "Undefined name: " ++ v ++ "\n" ++ Mid.showTree env )
                                           v
                                           id
                                           env)

instantiate (A (Prn e)) heap env = instantiate e heap env

instantiate (A (EConstr tag arity)) heap env
  = instantiateConstr tag arity heap env

instantiate (ELet isrec defs body) heap env
  | isrec = instantiateLetrec defs body heap env
  | otherwise = instantiateLet defs body heap env

instantiate (ECase e alts) heap env = error "Can't instantiate case expr"

instantiateConstr tag arity heap env
  = error "Can't instantiate constructors yet"

instantiateLet defs body heap env = instantiate body heap1 env1
  where
    (m, e) = head defs
    (heap1, a1) = instantiate e heap env
    env1 = Mz.insert m a1 env


--已修改，事先确定每个def参数个数保证，最后的地址正确
instantiateLetrec defs body heap env = instantiate body heap1 env1
  where
    argsWithNum = map (\(n, e) -> (n, countEAp e)) defs
    maxAddr = hNextAddr heap
    arg_bindings = scanl (\(_,addr) (n,inc) -> (n,addr+inc-1)) ("",maxAddr) argsWithNum
    env1 = foldl (\en (m,addr) -> Mz.insert m addr en) env arg_bindings
    heap1 = foldl (\hp (_,e) -> fst $ instantiate e hp env1) heap defs
    
                               
showResults :: [TiState] -> String
showResults states
 = iDisplay (iConcat [iLayn (map showState states), showStatics (last states)])

showState :: TiState -> Iseq
showState (sk,dp,hp,gb,sic)
  = iConcat [showStack hp sk, iNewline]
    

showState' :: TiState -> Iseq
showState' (_,_,(_,_,m),_,_)
  = foldr (\(k, a) rs -> iConcat [iStr "(", showAddr k,
                                  iStr ",",
                                  showNode a, iStr ")",iNewline ,rs])
    iNil
    (Mz.assocs m)

--hAddresses (size, free, cts) = [addr | (addr, node) <- cts]
showEnv :: Mz.Map Name Addr -> Iseq
showEnv env = Mz.foldrWithKey (\n a rs -> iConcat [iStr "(",iStr n, iStr" , ",showAddr a, iStr ")",rs]) iNil env

showStack :: TiHeap -> TiStack -> Iseq
showStack heap stack
  = iConcat [ iStr "Stk [",
              iIndent (iInterleave iNewline (map show_stack_item stack)),
              iStr " ]"]
    where
      show_stack_item addr
        = iConcat [showFWAddr addr, iStr ": ",
                   showStkNode heap (hLookup heap addr)]

showStkNode :: TiHeap -> Node -> Iseq
showStkNode heap (NAp fun_addr arg_addr)
  = iConcat [ iStr "NAp ", showFWAddr fun_addr,
              iStr " ", showFWAddr arg_addr, iStr " (",
              showNode (hLookup heap arg_addr), iStr ") "]

showStkNode heap node = showNode node

showNode :: Node -> Iseq
showNode (NAp a1 a2) = iConcat [ iStr "NAp ", showAddr a1,
                                 iStr " ", showAddr a2]
showNode (NSupercomb name args body) = iStr ("NSupercomb " ++ name)
showNode (NNum n) = iConcat [(iStr "NNum "), (iNum n)]
                            
showAddr :: Addr -> Iseq
showAddr addr = iStr (show addr)

showFWAddr :: Addr -> Iseq         --Show address in field of width 4
showFWAddr addr = iStr (rSpaces (4 - length str) ++ str)
  where
    str = show addr

showStatics :: TiState -> Iseq
showStatics (sk,dp,hp,gb,sic)
  = iConcat [iNewline,iNewline,iStr "Total number of steps = ",
             iNum (tiStatGetSteps sic)]

--auxiliary function
aLookup :: (Ord k) => b -> k -> (a -> b) -> Mz.Map k a -> b
aLookup err key f mka = maybe err f (Mz.lookup key mka)

hInitial :: TiHeap
hInitial = (0, [1..], Mz.empty :: Mz.Map Addr Node)

hAlloc :: Heap a -> a -> (Heap a, Addr)
hAlloc (size, (next:free), cts) x = ((size+1, free, Mz.alter (\_ -> Just x) next cts), next)

hNextAddr :: Heap a -> Addr
hNextAddr (_,(next:_),_) = next

hLookup :: Ord k => (a,b, Mz.Map k c) -> k -> c
hLookup (_,_, cts) x = aLookup (error "can't find it") x id cts

isDataNode :: Node -> Bool
isDataNode (NNum _) = True
isDataNode _ = False

checkAndzip :: [a] -> [b] -> Maybe [(a,b)]
checkAndzip [] _ = Just []
checkAndzip (a:as) (b:bs) = makeIt as bs (Just (\x -> ((a,b):x)))
  where
    makeIt [] _ mrs = liftA (\f -> f []) mrs
    makeIt (a':as') (b':bs') mrs = let new_mrs = liftA (\f -> (\x -> f ((a',b'):x))) mrs in
                                     makeIt as' bs' new_mrs
    makeIt _ _ _ = Nothing                                 
checkAndzip _ _ = Nothing

