{-# LANGUAGE FlexibleInstances, FlexibleContexts, UndecidableInstances, ScopedTypeVariables #-}

import Data.Array.Parallel.PArray
import Data.Array.Parallel.PArray.PData.Base

import Testsuite
import DPH.Arbitrary.SliceSpec
import DPH.Arbitrary.Perm
import qualified DPH.Operators.List             as L

import Text.PrettyPrint
import Debug.Trace
import Control.Monad
import Data.Vector                              (Vector)
import Prelude                                  as P
import qualified Data.Vector                    as V
import qualified Data.Array.Parallel.Unlifted   as U


$(testcases [ ""         <@ [t| ( Int, 
                                  PArray Int, 
                                  PArray (PArray Int) )|]
            ]
  [d|
  -- Converting arrays to and from lists.
  --  Note that converting a nested array to and from a list is fairly involved, 
  --  as we need to construct the segment descriptors.
  prop_toFromVector :: (PR a, Eq a) => Vector a -> Bool
  prop_toFromVector xs 
   =   xs
    == toVectorPA (fromVectorPA xs) 


  -- | Define an array that maps all indices to the same element.
  prop_replicate :: (PR a, Eq a) => a -> Property
  prop_replicate x
   =   forAll (choose (0, 100)) $ \n
   ->  V.replicate n x
    == toVectorPA (replicatePA n x) 


  -- TODO: replicates


  -- | Take a single element from an array.
  prop_index :: (PR a, Eq a) => PArray a -> Property
  prop_index arr
    =   lengthPA arr > 0
    ==> forAll (choose (0, lengthPA arr - 1)) $ \ix 
    ->  (toVectorPA arr) V.! ix
     == indexPA arr ix


  -- | Extract a single slice from a single array.
  prop_extract :: (PR a, Eq a) => Vector a -> Property
  prop_extract vec
    =  forAll (arbitrarySliceSpec (V.length vec)) $ \(SliceSpec ixStart lenSlice)  
    -> let vResult  = V.slice ixStart lenSlice vec
           aResult  = toVectorPA (extractPA (fromVectorPA vec) ixStart lenSlice)
       in  vResult == aResult

  prop_extract' :: (PR a, Eq a) => PArray a -> Property
  prop_extract' arr
    =  forAll (arbitrarySliceSpec (lengthPA arr)) $ \(SliceSpec ixStart lenSlice)  
    -> let vResult  = V.slice ixStart lenSlice (toVectorPA arr)
           aResult  = toVectorPA (extractPA arr ixStart lenSlice)
       in  vResult == aResult


  -- | Extract many slices from a single array.
  --   The QuickCheck property takes a Vector (PArray a) because we want to use V.mapM 
  --   to determine the length of each segment.
  prop_extracts1 :: (PR a, Eq a) => PArray a -> Property
  prop_extracts1 arr
   =    lengthPA arr > 0 
    ==> forAll (choose (1, 10)) $ \sliceCount
     -> forAll (replicateM sliceCount (arbitrarySliceSpec1 (lengthPA arr))) $ \sliceSpecs'
     -> let sliceSpecs    = V.fromList sliceSpecs'
            lens          = V.map sliceSpecLen    sliceSpecs
            starts        = V.map sliceSpecStart  sliceSpecs
            sources       = V.replicate (V.length sliceSpecs) 0

            vec           = toVectorPA arr
            vresult       = V.concat $ V.toList
                          $ V.zipWith (\len start -> V.slice start len vec)
                                lens
                                starts

            aresult       = extractsPA 
                                (V.singleton arr)
                                (V.convert sources)
                                (V.convert starts)
                                (V.convert lens)

            vresult2      = toVectorPA aresult

        in vresult == vresult2


  -- | Append two arrays.  
  prop_app :: (PR a, Eq a) => Vector a -> Vector a -> Bool
  prop_app xs ys
    =   xs V.++ ys
     == toVectorPA (fromVectorPA xs `appPA` fromVectorPA ys) 
  

  -- | Combine two arrays based on a selector.
  prop_combine2 
     :: (PR a, Eq a
        , PprPhysical (PData a)
        , PprVirtual  (PData a)
        , Show a, Arbitrary a) => Perm -> Vector a-> Property
  prop_combine2 (Perm perm') zz

   -- Build a non-empty vector of tags.
   = let perm      = if V.length perm' `mod` 2 == 1
                        then perm' V.++ (V.singleton $ V.length perm')
                        else perm'
         
         vecLen    = V.length perm `div` 2

         vecTags   = V.backpermute
                        (V.replicate vecLen 0  V.++  V.replicate vecLen (1 :: Int))
                        perm

     in V.length vecTags >= 2
       ==> forAll (liftM V.fromList $ vectorOf vecLen arbitrary) $ \vec1
        -> forAll (liftM V.fromList $ vectorOf vecLen arbitrary) $ \vec2
        -> let 
               vecResult   = V.fromList
                           $ L.combine2 (V.toList vecTags) 
                                        (V.toList $ vec1 `asTypeOf` zz) 
                                        (V.toList $ vec2 `asTypeOf` zz)

               sel2        = U.tagsToSel2 (U.fromList $ V.toList vecTags)
               arrResult   = combine2PA  sel2 (fromVectorPA vec1) (fromVectorPA vec2)
           in  
{-            trace (render $ vcat
                        [ text "-----------------------------"
                        , text $ show perm
                        , text $ show vecTags
                        , text "SRC VEC1: " <> (pprv $ fromVectorPA (vec1 `asTypeOf` zz))
                        , text "SRC VEC2: " <> (pprv $ fromVectorPA (vec2 `asTypeOf` zz))
                        , text "DST VEC:  " <> (pprv $ fromVectorPA vecResult)
                        , text "DST ARR:  " <> (pprv $ arrResult) ]) $ -}
              vecResult == toVectorPA arrResult

     
  -- TODO: packByTag
  -- TODO: combine2
  
  -- TODO: fromUArrayPR
  -- TODO: toUArrayPR



  -- TODO: Move the compound PA funs into their own module.
  -- | Concatenate arrays
  prop_concat :: (PR a, Eq a) => Vector (Vector a) -> Bool
  prop_concat xss
   = let  xss' = fromVectorPA (V.map fromVectorPA xss)
     in   V.concat (V.toList xss) == toVectorPA (concatPA xss')
  
  |])



instance (Arbitrary a) => Arbitrary (V.Vector a) where
 arbitrary
  = do  xs      <- arbitrary
        return  $ V.fromList xs


instance (PprPhysical (PArray a), Arbitrary a, PR a) 
       => Arbitrary (PArray a) where
 arbitrary 
  = sized $ \size 
  -> do xs      <- resize (truncate $ (\x -> sqrt x * 2) $ fromIntegral size) 
                $ arbitrary 

--        trace   (render $ pprp $ fromListPA xs) $
        return  $ fromListPA xs


instance (PprPhysical (PData a), Arbitrary a, PR a) 
       => Arbitrary (PData a) where
 arbitrary 
  = sized $ \size 
  -> do xs      <- resize (truncate $ (\x -> sqrt x * 2 ) $ fromIntegral size) 
                $ arbitrary 

--       trace   (render $ pprp $ fromListPR xs) $
        return  $ fromVectorPR xs
