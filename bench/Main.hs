{-# LANGUAGE NoImplicitPrelude #-}
module Main where

import Lib as P
import Core
import Fold
import Data.Monoid
import qualified Prelude as P
import qualified Data.List as P
import Criterion.Main

-- 140 MB total memory in use.
fail1 :: IO ()
fail1 = print . uncurry (\xs ys -> P.sum xs + P.sum ys) . P.span (1 ==) $
          replicate (10^7) (1 :: Integer)

-- 2 MB total memory in use.
nofail1 :: IO ()
nofail1 = print . exec (span (+) (1 ==) sum sum) $ replicate (10^7) (1 :: Integer)

whnfFrom1To :: ([Integer] -> b) -> Integer -> Benchmarkable
whnfFrom1To f = whnf (f . enumFromTo 1)
{-# INLINE whnfFrom1To #-}

whnfFrom1 :: (Int -> [Integer] -> b) -> Int -> Benchmarkable
whnfFrom1 f = whnf (\n -> f n [n `seq` 1..])
{-# INLINE whnfFrom1 #-}

-- Prelude version is 20% faster.
benchSum :: Benchmark
benchSum = bgroup "sum"
  [ bench "Prefolds" $ whnfFrom1To (exec sum) (10^7)
  , bench "Prelude"  $ whnfFrom1To  P.sum        (10^7)
  ]

-- Prelude version is 20% slower.
benchAverage :: Benchmark
benchAverage = bgroup "average"
  [ bench "Prefolds" $ whnf average  (10^7)
  , bench "Prelude"  $ whnf paverage (10^7)
  ] where
      average  n = exec ((/) <$> sum <*> genericLength) [1..n]
      paverage n = P.sum [1..n] / fromIntegral (P.length [1..n])

-- Prelude version is more than two times faster than `Prefolds/Mul`
-- and three times faster than `Prefolds/Sum`.
benchAverageTake :: Benchmark
benchAverageTake = bgroup "averageTake"
  [ bench "Prefolds/Mul" $ whnf average  (10^7)
  , bench "Prefolds/Sum" $ whnf average' (10^7) -- Note that this doesn't do the same job as others.
  , bench "Prelude"      $ whnf paverage (10^7)
  ] where
      average  n = exec ((/) <$> take n sum <*> take n genericLength) [n `seq` 1..]
      average' n = exec ((/) <$> take n sum <+> take n genericLength) [n `seq` 1..]
      paverage n = P.sum (P.take n [n `seq` 1..])
                 / fromIntegral (P.length $ P.take n [n `seq` 1..])

-- All are equal.
benchSlowAverageTake :: Benchmark
benchSlowAverageTake = bgroup "slowAverageTake"
  [ bench "Prefolds/Mul" $ whnf average  (10^4)
  , bench "Prefolds/Sum" $ whnf average' (10^4) -- Note that this doesn't do the same job as others.
  , bench "Prelude"      $ whnf paverage (10^4)
  ] where
      average  n = exec ((/) <$> map slowId (take n sum) <*> take n genericLength) [n `seq` 1..]
      average' n = exec ((/) <$> map slowId (take n sum) <+> take n genericLength) [n `seq` 1..]
      paverage n = (P.sum . P.take n $ P.map slowId [n `seq` 1..])
                 / fromIntegral (P.length $ P.take n [n `seq` 1..])
      
      slowId :: (Eq a, Num a) => a -> a
      slowId n = go 1000 n where
        go 0 n = n
        go m n = go (m - 1) n

-- Prelude version is almost two times faster.
benchScan :: Benchmark
benchScan = bgroup "scan"
  [ bench "Prefolds.scan" $ whnfFrom1To (exec $ scan sum sum)    (10^6)
  , bench "Prelude.scan"  $ whnfFrom1To (P.sum . P.scanl' (+) 0) (10^6)
  ]

-- Prefolds versions are nearly equal, Prelude versions are two times faster.
benchScanTake :: Benchmark
benchScanTake = bgroup "scanTake"
  [ bench "Prefolds.scan/1" $ whnfFrom1 (\n -> exec $ scan (take n sum) sum)      (10^6-1)
  , bench "Prefolds.scan/2" $ whnfFrom1 (\n -> exec $ scan sum (take n sum))      (10^6)
  , bench "Prefolds.scan/3" $ whnfFrom1 (\n -> exec $ take n (scan sum sum))      (10^6-1)
  , bench "Prelude.scan/1"  $ whnfFrom1 (\n -> P.sum . P.scanl' (+) 0 . P.take n) (10^6-1)
  , bench "Prelude.scan/2"  $ whnfFrom1 (\n -> P.sum . P.take n . P.scanl' (+) 0) (10^6)
  ]

-- Prelude version is 10% slower.
benchGroup :: Benchmark
benchGroup = bgroup "group"
  [ bench "Prefolds.group" . flip whnf (gen 10) $
      getSum . exec (take (10^7) . group (foldMap Sum) $ sum)
  , bench "Prelude.group"  . flip whnf (gen 10) $
      P.sum . P.map (getSum . P.foldMap Sum) . P.group . P.take (10^7)
  ] where
      gen n = cycle $ replicate n 1 ++ replicate n 2

-- Prelude versions are two orders of magnitude slower, but they leak and I don't see why.
benchInits :: Benchmark
benchInits = bgroup "scan"
  [ bench "Prefolds.inits"    $ whnfFrom1 (\n -> exec $ inits sum (take n sum))              (10^3)
  , bench "Prelude.inits"     $ whnfFrom1 (\n -> P.sum . P.take n . P.map P.sum . P.inits)   (10^3)
  , bench "Prelude.lazyInits" $ whnfFrom1 (\n -> P.sum . P.take n . P.map P.sum . lazyInits) (10^3)
  ] where
      lazyInits :: [a] -> [[a]]
      lazyInits = foldr (\x -> ([] :) . P.map (x:)) [[]]

suite :: [Benchmark]
suite =
  [ benchSum
  , benchAverage
  , benchAverageTake
  , benchSlowAverageTake
  , benchScan
  , benchScanTake
  , benchGroup
  , benchInits
  ]

benchSuite :: IO ()
benchSuite = defaultMain suite

main = benchSuite
