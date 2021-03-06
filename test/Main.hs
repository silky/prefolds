{-# LANGUAGE NoImplicitPrelude, ExistentialQuantification, TypeOperators #-}
module Main where

import Lib
import Core
import Fold
import qualified Prelude as P
import qualified Data.List as P
import Control.Monad.Trans.Writer

-- I didn't find a lib that allows to not name every single test,
-- so here is a tiny implementation.
data Test = forall a. (Show a, Eq a) => a :== a
          | Label String [Test]

type Suite = Writer [Test] ()

runSuite :: Suite -> String
runSuite = fin . gos . execWriter where
  fin [] = "OK"
  fin ss = P.intercalate "\n" ss

  gos = concatMap go . zip [1..]

  go (i, x :== y)    = [concat [show i, ": ", show x, " is not ", show y] | x /= y]
  go (i, Label s ts) = P.map (\t -> s ++ "/" ++ t) $ gos ts

label :: String -> Suite -> Suite
label s t = tell [Label s $ execWriter t]

(===) :: (Show a, Eq a) => a -> a -> Suite
x === y = tell [x :== y]



perf :: (Fold a Identity [a] -> Fold a Identity b) -> [a] -> b
perf f = exec (f list)

-- It's really easy to make an off-by-one error with functions like `scan` and `groupBy`,
-- hence the tests mostly cover such cases.
suite :: Suite
suite = do
  label "map"  $ do
    perf (map (^2)) []     === ([] :: [Int])
    perf (map (^2)) [1..3] === [1,4,9]
  label "take" $ do
    perf (take 0) []                === ([] :: [Int])
    perf (take 1) []                === ([] :: [Int])
    perf (take 0) [1..]             === []
    perf (take 3) [1,2]             === [1,2]
    perf (take 2) [1..3]            === [1,2]
    perf (take 3) [1..3]            === [1..3]
    perf (take 3) [1..]             === [1..3]
    perf (take 3) (1:2:3:undefined) === [1..3]
  label "filter" $ do
    perf (filter even) []      === []
    perf (filter even) [1]     === []
    perf (filter even) [1,3,5] === []
    perf (filter even) [1..5]  === [2,4]
  label "map-take-filter" $ do
    perf (map (* 3) . take 5 . filter even) [1..] === [6,12]
    perf (map (* 3) . filter even . take 5) [1..] === [6,12,18,24,30]
    perf (take 5 . map (* 3) . filter even) [1..] === [6,12]
    perf (take 5 . filter even . map (* 3)) [1..] === [6,12]
    perf (filter even . map (* 3) . take 5) [1..] === [6,12,18,24,30]
    perf (filter even . take 5 . map (* 3)) [1..] === [6,12,18,24,30]
  label "drop" $ do
    perf (drop 0) []     === ([] :: [Int])
    perf (drop 1) []     === ([] :: [Int])
    perf (drop 0) [1]    === [1]
    perf (drop 1) [1]    === []
    perf (drop 2) [1]    === []
    perf (drop 0) [1..4] === [1..4]
    perf (drop 1) [1..4] === [2..4]
    perf (drop 3) [1..4] === [4]
    perf (drop 4) [1..4] === []
    perf (drop 5) [1..4] === []
    perf (drop 9) [1..4] === []
  label "takeWhile" $ do
    perf (takeWhile (<= 5)) []                === []
    perf (takeWhile (<= 5)) [1..4]            === [1..4]
    perf (takeWhile (<= 5)) [1..6]            === [1..5]
    perf (takeWhile (<= 5)) [5..]             === [5]
    perf (takeWhile (<= 5)) [6..]             === []
    perf (takeWhile (<= 5)) (4:5:6:undefined) === [4,5]
  label "dropWhile" $ do
    perf (dropWhile (<= 5)) []     === []
    perf (dropWhile (<= 5)) [1..4] === []
    perf (dropWhile (<= 5)) [1..6] === [6]
    perf (dropWhile (<= 5)) [3..9] === [6..9]
    perf (dropWhile (<= 5)) [5..9] === [6..9]
  label "scan" $ do
    label "basic" $ do
      perf (scan sum) []     === [0]
      perf (scan sum) [1]    === [0,1]
      perf (scan sum) [1..5] === [0,1,3,6,10,15]
    label "stop" $ do
      label "single" $ do
        perf (take 0 . scan sum) [1..] === [0]
        perf (scan sum . take 0) [1..] === []
        perf (take 5 . scan sum) [1..] === [0,1,3,6,10,15]
        perf (scan sum . take 5) [1..] === [0,1,3,6,10]
        perf (scan (take 5 sum)) [1..] === [0,1,3,6,10,15]
      label "multi" $ do
        perf (take 5 . scan sum . take 3) [1..] === [0,1,3]
        perf (take 3 . scan sum . take 5) [1..] === [0,1,3,6]
        perf (scan (take 5 sum) . take 3) [1..] === [0,1,3]
        perf (scan (take 3 sum) . take 5) [1..] === [0,1,3,6]
        perf (scan (take 5 sum) . take 4) [1..] === [0,1,3,6]
        perf (scan (take 4 sum) . take 5) [1..] === [0,1,3,6,10]
        perf (scan (take 5 sum) . take 5) [1..] === [0,1,3,6,10]
  let testGroupBy gby = do
        label "basic" $ do
          exec (gby (<) list list) [1]                     === [[1]]
          exec (gby (<) list list) [1,2]                   === [[1,2]]
          exec (gby (<) list list) [1,3,2]                 === [[1,3],[2]]
          exec (gby (<) list list) [2,1,3]                 === [[2],[1,3]]
          exec (gby (<) list list) [2,1,3,4,5]             === [[2],[1,3,4,5]]
          exec (gby (<) list list) [2,1,3,4,5,4,2,1,4,6,8] === [[2],[1,3,4,5],[4],[2],[1,4,6,8]]
          exec (gby (<) list list) [1..5]                  === [[1..5]]
        label "stop" $ do
          let xs = [7,1,2,3,4,3,5,9,2] ++ [1..]
          exec (gby (<) (take 0 list) $ take 0 list)  xs === []
          exec (gby (<) (take 0 list) $ take 1 list)  xs === [[]]
          exec (gby (<) (take 0 list) $ take 3 list)  xs === [[],[],[]]
          exec (gby (<) (take 1 list) $ take 0 list)  xs === []
          exec (gby (<) (take 3 list) $ take 0 list)  xs === []
          exec (gby (<) (take 1 list) $ take 1 list)  xs === [[7]]
          exec (gby (<) (take 2 list) $ take 3 list)  xs === [[7],[1,2],[3,5]]
          exec (gby (<) (take 3 list) $ take 2 list)  xs === [[7],[1,2,3]]
          exec (gby (<) (take 3 list) $ take 3 list)  xs === [[7],[1,2,3],[3,5,9]]
          exec (take 12 $ gby (<)  list         list) xs === [[7],[1,2,3,4],[3,5,9],[2],[1,2,3]]
          exec (take 12 $ gby (<) (take 2 list) list) xs === [[7],[1,2],[3,5],[2],[1,2]]
  label "groupBy" $ do
    label "empty" $ do
      exec (groupBy (<) sum  list) [] ===  []
      exec (groupBy (<) list list) [] === ([] :: [[Int]])
    testGroupBy groupBy
  label "groupBy1" $ do
    label "empty" $ do
      exec (groupBy1 (<) sum  list) [] ===  [0]
      exec (groupBy1 (<) list list) [] === ([[]] :: [[Int]])
    testGroupBy groupBy1
  label "inits" $ do
    label "basic" $ do
      exec (inits list list) []     === [[] :: [Int]]
      exec (inits list list) [1]    === [[],[1]]
      exec (inits list list) [1..4] === [[],[1],[1,2],[1,2,3],[1,2,3,4]]
    label "stop" $ do
      label "finite" $ do
        exec (inits (take 0 list) (take 0 list)) [1,2] === []
        exec (inits (take 3 list) (take 0 list)) [1,2] === []
        exec (inits (take 0 list) (take 1 list)) [1,2] === [[]]
        exec (inits (take 0 list) (take 4 list)) [1,2] === [[],[],[]]
        exec (inits (take 2 list) (take 4 list)) [1,2] === [[],[1],[1,2]]
        exec (inits (take 4 list) (take 4 list)) [1,2] === [[],[1],[1,2]]
        exec (inits (take 3 list) (take 5 list)) [1,2] === [[],[1],[1,2]]
      label "infinite" $ do
        exec (inits (take 0 list) (take 0 list)) [1..] === []
        exec (inits (take 3 list) (take 0 list)) [1..] === []
        exec (inits (take 0 list) (take 1 list)) [1..] === [[]]
        exec (inits (take 0 list) (take 4 list)) [1..] === [[],[],[],[]]
        exec (inits (take 2 list) (take 4 list)) [1..] === [[],[1],[1,2],[1,2]]
        exec (inits (take 4 list) (take 4 list)) [1..] === [[],[1],[1,2],[1,2,3]]
        exec (inits (take 3 list) (take 5 list)) [1..] === [[],[1],[1,2],[1,2,3],[1,2,3]]
  label "chunks" $ do
    label "degenerate" $ do
      exec (chunks list list) []     === ([] :: [[Int]])
      exec (chunks list list) [1]    === [[1]]
      exec (chunks list list) [1..4] === [[1..4]]
    label "chunksOf" $ do
      label "degenerate" $ do
        exec (chunksOf 0 list list) []     === ([] :: [[Int]])
        exec (chunksOf 0 list list) [1]    === ([] :: [[Int]])
        exec (chunksOf 0 list list) [1..4] === ([] :: [[Int]])
      label "basic" $ do
        exec (chunksOf 1 list list) []     === ([] :: [[Int]])
        exec (chunksOf 1 list list) [1]    === [[1]]
        exec (chunksOf 1 list list) [1..4] === [[1],[2],[3],[4]]
        exec (chunksOf 3 list list) [1]    === [[1]]
        exec (chunksOf 3 list list) [1..4] === [[1,2,3],[4]]
        exec (chunksOf 3 list list) [1..5] === [[1,2,3],[4,5]]
        exec (chunksOf 3 list list) [1..6] === [[1,2,3],[4,5,6]]
    label "splitOne" $ do
      exec (splitOne ',' list list) ""          === []
      exec (splitOne ',' list list) ","         === [""]
      exec (splitOne ',' list list) ",,"        === ["",""]
      exec (splitOne ',' list list) "a"         === ["a"]
      exec (splitOne ',' list list) "abc"       === ["abc"]
      exec (splitOne ',' list list) "a,bcd"     === ["a", "bcd"]
      exec (splitOne ',' list list) "ab,c,def"  === ["ab", "c", "def"]
      exec (splitOne ',' list list) "abc,def,"  === ["abc", "def"]
      exec (splitOne ',' list list) "abc,def,," === ["abc", "def", ""]
  label "compose" $ do
    label "parallel" $ do
      label "product" $ do
        exec ((,) <$> list        <*> list)        []     === ([],[] :: [Int])
        exec ((,) <$> list        <*> list)        [1..4] === ([1..4],[1..4])
        exec ((,) <$> take 3 list <*> list)        [1..4] === ([1..3],[1..3])
        exec ((,) <$> list        <*> take 3 list) [1..4] === ([1..3],[1..3])
        exec ((,) <$> take 0 list <*> take 1 list) [1..]  === ([],[])
        exec ((,) <$> take 1 list <*> take 0 list) [1..]  === ([],[])
        exec ((,) <$> take 1 list <*> take 1 list) [1..]  === ([1],[1])
        exec ((,) <$> take 3 list <*> take 4 list) [1..]  === ([1..3],[1..3])
        exec ((,) <$> take 4 list <*> take 3 list) [1..]  === ([1..3],[1..3])
        exec ((,) <$> take 4 list <*> take 4 list) [1..]  === ([1..4],[1..4])
      label "sum" $ do
        exec ((,) <$> list        <+> list)        []     === ([],[] :: [Int])
        exec ((,) <$> list        <+> list)        [1..4] === ([1..4],[1..4])
        exec ((,) <$> take 3 list <+> list)        [1..4] === ([1..3],[1..4])
        exec ((,) <$> list        <+> take 3 list) [1..4] === ([1..4],[1..3])
        exec ((,) <$> take 0 list <+> take 1 list) [1..]  === ([],[1])
        exec ((,) <$> take 1 list <+> take 0 list) [1..]  === ([1],[])
        exec ((,) <$> take 1 list <+> take 1 list) [1..]  === ([1],[1])
        exec ((,) <$> take 3 list <+> take 4 list) [1..]  === ([1..3],[1..4])
        exec ((,) <$> take 4 list <+> take 3 list) [1..]  === ([1..4],[1..3])
        exec ((,) <$> take 4 list <+> take 4 list) [1..]  === ([1..4],[1..4])
    label "sequential" $ do
      label "connect" $ do
        exec ((,) <$> list        </> list)        []     === ([],[] :: [Int])
        exec ((,) <$> list        </> list)        [1..4] === ([1..4],[])
        exec ((,) <$> take 3 list </> list)        [1..4] === ([1..3],[4])
        exec ((,) <$> list        </> take 3 list) [1..4] === ([1..4],[])
        exec ((,) <$> take 0 list </> take 1 list) [1..]  === ([],[1])
        exec ((,) <$> take 1 list </> take 0 list) [1..]  === ([1],[])
        exec ((,) <$> take 1 list </> take 1 list) [1..]  === ([1],[2])
        exec ((,) <$> take 3 list </> take 4 list) [1..]  === ([1..3],[4..7])
        exec ((,) <$> take 4 list </> take 3 list) [1..]  === ([1..4],[5..7])
        exec ((,) <$> take 4 list </> take 4 list) [1..]  === ([1..4],[5..8])
      label "weld" $ do
        exec ((,) <$> list        <//> list)        []     === ([],[] :: [Int])
        exec ((,) <$> list        <//> list)        [1..4] === ([1..4],[]) -- Sic.
        exec ((,) <$> take 3 list <//> list)        [1..4] === ([1..3],[3,4])
        exec ((,) <$> list        <//> take 3 list) [1..4] === ([1..4],[]) -- Sic.
        exec ((,) <$> take 0 list <//> take 1 list) [1..]  === ([],[1])
        exec ((,) <$> take 1 list <//> take 0 list) [1..]  === ([1],[])
        exec ((,) <$> take 1 list <//> take 1 list) [1..]  === ([1],[1])
        exec ((,) <$> take 3 list <//> take 4 list) [1..]  === ([1..3],[3..6])
        exec ((,) <$> take 4 list <//> take 3 list) [1..]  === ([1..4],[4..6])
        exec ((,) <$> take 4 list <//> take 4 list) [1..]  === ([1..4],[4..7])
  label "random" $ do
    perf (takeWhile (< 10) . dropWhile (<= 3) . filter even)    [1..] === [4,6,8]
    exec ((,) <$> take 4 list <+> (drop 2 . take 4) list)       [1..] === ([1..4],[3..6])
    perf (filter even . scan sum . take 6 . dropWhile (<= 10))  [1..] === [12,20,30]
    exec ((,,) <$> take 4 list <+> take 3 list <*> take 2 list) [1..] === ([1..2],[1..2],[1..2])
    exec ((,,) <$> take 4 list <+> take 3 list <*> take 5 list) [1..] === ([1..4],[1..3],[1..4])
    exec ((,,) <$> take 4 list <+> take 3 list </> take 2 list) [1..] === ([1..4],[1..3],[5..6])
    exec ((,) <$> sum <*> any even) [1..3] === (3,True)
    exec ((,) <$> sum <+> any even) [1..3] === (6,True)
  label "null" $ do
    exec null []             === True
    exec null [1]            === False
    exec null (1 : repeat 2) === False
    exec null (1:undefined)  === False
  label "length" $ do
    exec length []     === 0
    exec length [1]    === 1
    exec length [1..5] === 5
  label "all" $ do
    exec (all even) []                    === True
    exec (all even) [1]                   === False
    exec (all even) [2]                   === True
    exec (all even) [2,3]                 === False
    exec (all even) [2,4,6]               === True
    exec (all even) ([2,4,6] ++ repeat 1) === False
    exec (all even) (2:4:6:1:undefined)   === False
  label "any" $ do
    exec (any even) []                    === False
    exec (any even) [1]                   === False
    exec (any even) [2]                   === True
    exec (any even) [2,3]                 === True
    exec (any even) [1,3,4]               === True
    exec (any even) ([1,3,5] ++ repeat 2) === True
    exec (any even) (1:3:5:2:undefined)   === True
  label "find" $ do
    exec (find even) []                    === Nothing
    exec (find even) [1]                   === Nothing
    exec (find even) [2]                   === Just 2
    exec (find even) [2,3]                 === Just 2
    exec (find even) [1,3,4]               === Just 4
    exec (find even) ([1,3,5] ++ repeat 2) === Just 2
    exec (find even) (1:3:5:2:undefined)   === Just 2
  label "head" $ do
    exec head []             === (Nothing :: Maybe Int)
    exec head [1]            === Just 1
    exec head [1..5]         === Just 1
    exec head (1 : repeat 2) === Just 1
    exec head (1:undefined)  === Just 1
  label "last" $ do
    exec last []     === (Nothing :: Maybe Int)
    exec last [1]    === Just 1
    exec last [1..5] === Just 5

checkSuite :: IO ()
checkSuite = putStrLn $ runSuite suite

main = checkSuite
