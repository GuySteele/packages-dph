#include "fusion-phases.h"

-- | Functions that work on parallel arrays of scalar elements.
--   Unlike the functions defined in D.A.P.PArray, these only need
--   Scalar dictionaries, instead of PR or PA dictionaries. 
--
--   They are used when defining vectorised Prelude functions, 
--    eg in D.A.P.Prelude.Int and D.A.P.Prelude.Double.
--
--   The map and zipWith functions are also used by the vectoriser when
--   vectorising uses of scalar operators like (+).
--
module Data.Array.Parallel.PArray.Scalar 
        ( Scalar(..)

        -- * Conversions
        , toUArray,   fromUArray
        , fromUArray2

        -- * Maps and Zips
        , map
        , zipWith
        , zipWith3
        
        -- * Folds
        , fold,         folds
        , fold1,        fold1s
        , fold1Index,   fold1sIndex
        
        -- * Enumerations
        , enumFromTo, enumFromTol)
where
import Data.Array.Parallel.PArray.PData.Word8
import Data.Array.Parallel.PArray.PData.Double
import Data.Array.Parallel.PArray.PData
import Data.Array.Parallel.PArray.PRepr
import Data.Array.Parallel.Base
import Data.Word
import GHC.Exts
import qualified Data.Array.Parallel.Unlifted   as U
import qualified Data.Vector                    as V
import Prelude hiding 
        ( map, zipWith, zipWith3
        , enumFromTo)

-- | Class of Scalar data that can be converted to and from single unboxed
--   vectors.
class (PA a, U.Elt a) => Scalar a where
  fromScalarPData  :: PData  a             -> U.Array a
  toScalarPData    :: U.Array a            -> PData a
  
  -- TODO: make these return U.Arrays a, then need to be O(1).
  fromScalarPDatas :: PDatas a             -> V.Vector (U.Array a)
  toScalarPDatas   :: V.Vector (U.Array a) -> PDatas a


-- Shorthands for the above methods used in this module only.
from    :: Scalar a => PData a -> U.Array a
from    = fromScalarPData

to      :: Scalar a => U.Array a -> PData a
to      = toScalarPData


-- Instances --------------------------------------------------------------
instance Scalar Bool where
  {-# INLINE toScalarPData #-}
  toScalarPData bs
    = PBool (U.tagsToSel2 (U.map fromBool bs))

  {-# INLINE fromScalarPData #-}
  fromScalarPData (PBool sel)
    = U.map toBool (U.tagsSel2 sel)

  {-# INLINE fromScalarPDatas #-}
  fromScalarPDatas (PBools sels)
    = V.map (U.map toBool . U.tagsSel2) sels

  {-# INLINE toScalarPDatas #-}
  toScalarPDatas bss
    = let tagss = V.map (U.map fromBool) bss
          sels  = V.map U.tagsToSel2 tagss
      in  PBools sels


-- TODO: transitory instances. conversions need to be O(1).
instance Scalar Int where
  fromScalarPData  (PInt  xs)     = xs
  fromScalarPDatas (PInts xss)    = U.toVectors xss
  toScalarPData                   = PInt
  toScalarPDatas xss              = PInts $ U.fromVectors xss

-- TODO: transitory instances. conversions need to be O(1).
instance Scalar Word8 where
  fromScalarPData  (PWord8  xs)   = xs
  fromScalarPDatas (PWord8s xss)  = U.toVectors xss
  toScalarPData                   = PWord8
  toScalarPDatas xss              = PWord8s $ U.fromVectors xss

-- TODO: transitory instances. conversions need to be O(1).
instance Scalar Double where
  fromScalarPData  (PDouble xs)   = xs
  fromScalarPDatas (PDoubles xss) = U.toVectors xss
  toScalarPData                   = PDouble
  toScalarPDatas xss              = PDoubles $ U.fromVectors xss


-- Conversions ----------------------------------------------------------------
{-# INLINE_PA fromUArray #-}
fromUArray  :: Scalar a => U.Array a -> PArray a
fromUArray uarr
 = let  !(I# n#) = U.length uarr
   in   PArray n# (toScalarPData uarr) 
 
 
{-# INLINE_PA toUArray #-}
toUArray    :: Scalar a => PArray a -> U.Array a
toUArray (PArray _ pdata)
        = fromScalarPData pdata
 

-- Tuple Conversions ----------------------------------------------------------
-- | Convert an U.Array of pairs to a PArray.
{-# INLINE fromUArray2 #-}
fromUArray2
        :: (Scalar a, Scalar b)
        => U.Array (a, b) -> PArray (a, b)
fromUArray2 ps
 = let  !(I# n#) = U.length ps
        (xs,ys)  = U.unzip ps
    in  PArray n# (PTuple2 (toScalarPData xs) (toScalarPData  ys))
    

-- Maps and Zips --------------------------------------------------------------
-- | Apply a worker function to every element of an array, yielding a new array.
{-# INLINE_PA map #-}
map     :: (Scalar a, Scalar b) 
        => (a -> b) -> PArray a -> PArray b

map f (PArray len xs)
        = PArray len $ to $ U.map f (from xs)


-- | Zip two arrays, yielding a new array.
{-# INLINE_PA zipWith #-}
zipWith :: (Scalar a, Scalar b, Scalar c)
        => (a -> b -> c) -> PArray a -> PArray b -> PArray c

zipWith f (PArray len xs) (PArray _ ys)
        = PArray len $ to $ U.zipWith f (from xs) (from ys)


-- | Zip three arrays, yielding a new array.
{-# INLINE_PA zipWith3 #-}
zipWith3
        :: (Scalar a, Scalar b, Scalar c, Scalar d)
        => (a -> b -> c -> d) -> PArray a -> PArray b -> PArray c -> PArray d

zipWith3 f (PArray len xs) (PArray _ ys) (PArray _ zs)
        = PArray len $ to $ U.zipWith3 f (from xs) (from ys) (from zs)


-- Folds ----------------------------------------------------------------------
-- | Left fold over an array.
{-# INLINE_PA fold #-}
fold    :: Scalar a 
        => (a -> a -> a) -> a -> PArray a -> a

fold f z (PArray _ pdata)
        = U.fold f z $ from pdata


-- | Left fold over an array, using the first element to initialise the state.
{-# INLINE_PA fold1 #-}
fold1   :: Scalar a
        => (a -> a -> a) -> PArray a -> a

fold1 f (PArray _ pdata)
        = U.fold1 f $ from pdata


-- | Segmented fold of an array of arrays.
--   Each segment is folded individually, yielding an array of the fold results.
{-# INLINE_PA folds #-}
folds   :: Scalar a
        => (a -> a -> a) -> a -> PArray (PArray a) -> PArray a

folds f z (PArray _ (PNested vsegd pdatas))
 = let  -- Grab all the flat physical arrays.
        uarrs           = fromScalarPDatas pdatas 
        
        -- Sum up each physical segment individually.
        psegResults     = U.fold_ss f z (U.takeSSegdOfVSegd vsegd) uarrs
        
        -- Replicate the physcal results according to the vsegids
        vsegResults     = U.bpermute psegResults (U.takeVSegidsOfVSegd vsegd) 

   in   fromUArray vsegResults


-- | Segmented fold of an array of arrays, using the first element of each
--   segment to initialse the state for that segment.
--   Each segment is folded individually, yielding an array of all the fold results.
{-# INLINE_PA fold1s #-}
fold1s  :: Scalar a
        => (a -> a -> a) -> PArray (PArray a) -> PArray a

fold1s f (PArray _ (PNested vsegd pdatas))
 = let  -- Grab all the flat physical arrays.
        uarrs           = fromScalarPDatas pdatas 
 
        -- Sum up each physical segment individually.
        psegResults     = U.fold1_ss f (U.takeSSegdOfVSegd vsegd) uarrs
        
        -- Replicate the physcal results according to the vsegids
        vsegResults     = U.bpermute psegResults (U.takeVSegidsOfVSegd vsegd) 

   in   fromUArray vsegResults


-- | Left fold over an array, also passing the index of each element
--   to the parameter function.
fold1Index
        :: Scalar a
        => ((Int, a) -> (Int, a) -> (Int, a)) -> PArray a -> Int

{-# INLINE_PA fold1Index #-}
fold1Index f
        = fst . U.fold1 f . U.indexed . toUArray


-- | Segmented fold over an array, also passing the index of each 
--   element to the parameter function.
--   TODO: fold the psegs then replicate, like in the other folds.
--         this currently has the wrong complexity.
fold1sIndex
        :: Scalar a
        => ((Int, a) -> (Int, a) -> (Int, a))
        -> PArray (PArray a) -> PArray Int

{-# INLINE_PA fold1sIndex #-}
fold1sIndex f (PArray n# pdata)
 = let  segd    = takeSegdPD pdata
        xs      = concatPA pdata
   in   PArray n#
         $ toScalarPData
         $ U.fsts
         $ U.fold1_s f segd
         $ U.zip (U.indices_s segd)
         $ fromScalarPData xs


-- Enumerations --------------------------------------------------------------
-- | Construct a range of integers.
{-# INLINE_PA enumFromTo #-}
enumFromTo :: Int -> Int -> PArray Int
enumFromTo m n 
        = fromUArray (U.enumFromTo m n)


{-# INLINE_PA enumFromTol #-}
enumFromTol :: PArray Int -> PArray Int -> PArray (PArray Int)
enumFromTol (PArray m# ms) (PArray _ ns)
  = PArray m#
  $ PNested (U.promoteSegdToVSegd segd)
  $ toScalarPDatas
  $ V.singleton
  $ U.enumFromStepLenEach 
        (U.elementsSegd segd)
        (fromScalarPData ms)
        (U.replicate (U.elementsSegd segd) 1) 
        lens
  where
        lens  = U.zipWith distance (fromScalarPData ms) (fromScalarPData ns)
        segd  = U.lengthsToSegd lens

distance :: Int -> Int -> Int
{-# INLINE_STREAM distance #-}
distance m n = max 0 (n - m + 1)

