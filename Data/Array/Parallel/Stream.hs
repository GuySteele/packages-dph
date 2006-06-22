-----------------------------------------------------------------------------
-- |
-- Module      : Data.Array.Parallel.Stream
-- Copyright   : (c) 2006 Roman Leshchinskiy
-- License     : see libraries/base/LICENSE
-- 
-- Maintainer  : Roman Leshchinskiy <rl@cse.unsw.edu.au>
-- Stability   : internal
-- Portability : non-portable (existentials)
--
-- Description ---------------------------------------------------------------
--
-- This module defined the interface to the stream library used for loop
-- fusion.
--

module Data.Array.Parallel.Stream (
  module Data.Array.Parallel.Stream.Flat,
  module Data.Array.Parallel.Stream.Segmented
) where

import Data.Array.Parallel.Stream.Flat
import Data.Array.Parallel.Stream.Segmented

