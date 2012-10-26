{-# LANGUAGE RecordWildCards #-}

-- | The module provides first-order, linear-chain conditional random fields
-- (CRFs) with position-wide constraints over label values.

module Data.CRF.Chain1.Constrained
(
-- * Data types
  Word
, Sent
, Dist (unDist)
, mkDist
, WordL
, annotate
, SentL

-- * CRF
, CRF (..)
-- ** Training
, train
-- ** Tagging
, tag

-- * Feature selection
, hiddenFeats
, presentFeats
) where

import Data.CRF.Chain1.Constrained.Dataset.External
import Data.CRF.Chain1.Constrained.Dataset.Codec
import Data.CRF.Chain1.Constrained.Feature.Present
import Data.CRF.Chain1.Constrained.Feature.Hidden
import Data.CRF.Chain1.Constrained.Train
import qualified Data.CRF.Chain1.Constrained.Inference as I

-- | Determine the most probable label sequence within the context of the
-- given sentence using the model provided by the 'CRF'.
tag :: (Ord a, Ord b) => CRF a b -> Sent a b -> [b]
tag CRF{..} sent
    = onWords . decodeLabels codec
    . I.tag model . encodeSent codec
    $ sent
  where
    onWords xs =
        [ unJust codec word x
        | (word, x) <- zip sent xs ]
