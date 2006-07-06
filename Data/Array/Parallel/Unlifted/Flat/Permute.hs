-----------------------------------------------------------------------------
-- |
-- Module      : Data.Array.Parallel.Unlifted.Flat.Permute
-- Copyright   : (c) [2001..2002] Manuel M T Chakravarty & Gabriele Keller
--		 (c) 2006         Manuel M T Chakravarty & Roman Leshchinskiy
-- License     : see libraries/base/LICENSE
-- 
-- Maintainer  : Manuel M T Chakravarty <chak@cse.unsw.edu.au>
-- Stability   : experimental
-- Portability : portable
--
-- Description ---------------------------------------------------------------
--
-- Permutations on flat unlifted arrays.
--
-- Todo ----------------------------------------------------------------------
--

module Data.Array.Parallel.Unlifted.Flat.Permute (
  permuteU, permuteMU, bpermuteU, bpermuteDftU, reverseU, updateU, updateMU
) where

import Data.Array.Parallel.Base (
  ST, (:*:)(..))
import Data.Array.Parallel.Stream (
  Step(..), Stream(..))
import Data.Array.Parallel.Unlifted.Flat.UArr (
  UA, UArr, MUArr,
  lengthU, newU, newDynU, writeMU)
import Data.Array.Parallel.Unlifted.Flat.Stream (
  streamU, unstreamMU)
import Data.Array.Parallel.Unlifted.Flat.Basics (
  (!:), enumFromToU)
import Data.Array.Parallel.Unlifted.Flat.Combinators (
  mapU)

-- |Permutations
-- -------------

permuteMU :: UA e => MUArr e s -> UArr e -> UArr Int -> ST s ()
permuteMU mpa arr is = permute 0
  where
    n = lengthU arr
    permute i
      | i == n    = return ()
      | otherwise = writeMU mpa (is!:i) (arr!:i) >> permute (i + 1)
    

-- |Standard permutation
--
permuteU :: UA e => UArr e -> UArr Int -> UArr e
{-# INLINE permuteU #-}
permuteU arr is = newU (lengthU arr) $ \mpa -> permuteMU mpa arr is

-- |Back permutation operation (ie, the permutation vector determines for each
-- position in the result array its origin in the input array)
--
bpermuteU :: UA e => UArr e -> UArr Int -> UArr e
{-# INLINE bpermuteU #-}
bpermuteU a = mapU (a!:)

-- |Default back permute
--
-- * The values of the index-value pairs are written into the position in the
--   result array that is indicated by the corresponding index.
--
-- * All positions not covered by the index-value pairs will have the value
--   determined by the initialiser function for that index position.
--
bpermuteDftU :: UA e
	     => Int			        -- |length of result array
	     -> (Int -> e)		        -- |initialiser function
	     -> UArr (Int :*: e)		-- |index-value pairs
	     -> UArr e
{-# INLINE bpermuteDftU #-}
bpermuteDftU n init = updateU (mapU init . enumFromToU 0 $ n-1)

updateMU :: UA e => MUArr e s -> UArr (Int :*: e) -> ST s ()
{-# INLINE updateMU #-}
updateMU marr upd = updateM marr (streamU upd)

updateM :: UA e => MUArr e s -> Stream (Int :*: e) -> ST s ()
{-# INLINE [1] updateM #-}
updateM marr (Stream next s _) = upd s
  where
    upd s = case next s of
              Done               -> return ()
              Skip s'            -> upd s'
              Yield (i :*: x) s' -> do
                                      writeMU marr i x
                                      upd s' 

-- | Yield an array constructed by updating the first array by the
-- associations from the second array (which contains index/value pairs).
--
updateU :: UA e => UArr e -> UArr (Int :*: e) -> UArr e
{-# INLINE updateU #-}
updateU arr upd = update (streamU arr) (streamU upd)

update :: UA e => Stream e -> Stream (Int :*: e) -> UArr e
{-# INLINE [1] update #-}
update s1@(Stream _ _ n) s2 = newDynU n (\marr ->
  do
    i <- unstreamMU marr s1
    updateM marr s2
    return i
  )

-- |Reverse the order of elements in an array
--
reverseU :: UA e => UArr e -> UArr e
reverseU a = mapU (a!:) . enumFromToU 0 $ lengthU a - 1
