module Data.CRF.Chain1.Constrained.Dataset.External
( Word (..)
, Sent
, Dist (unDist)
, mkDist
, WordL
, annotate
, SentL
) where

import qualified Data.Set as S
import qualified Data.Map as M

-- | A Word is represented by a set of observations
-- and a set of potential interpretation labels.
data Word a b = Word
    { obs   :: S.Set a
    , lbs   :: S.Set b }

-- | A sentence of words.
type Sent a b = [Word a b]

-- | A probability distribution defined over elements of type a.
-- All elements not included in the map have probability equal
-- to 0.
newtype Dist a = Dist { unDist :: M.Map a Double }

-- | Construct the probability distribution.
mkDist :: Ord a => [(a, Double)] -> Dist a
mkDist =
    Dist . normalize . M.fromListWith (+)
  where
    normalize dist =
        let z = sum (M.elems dist)
        in  fmap (/z) dist

-- | A WordL is a labeled word, i.e. a word with probability distribution
-- defined over labels.
type WordL a b = (Word a b, Dist b)

-- | Annotate the word with the label.
annotate :: Ord b => Word a b -> b -> WordL a b
annotate w x
    | x `S.member` lbs w    = (w, Dist (M.singleton x 1))
    | otherwise             =
        error "annotate: label not in the set of potential interpretations"

-- | A sentence of labeled words.
type SentL a b = [WordL a b]
