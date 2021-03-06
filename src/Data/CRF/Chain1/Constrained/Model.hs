{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}

-- | Internal implementation of the CRF model.

module Data.CRF.Chain1.Constrained.Model
( FeatIx (..)
, Model (..)
, mkModel
, valueL
, featToIx
, featToJustIx
, featToJustInt
, sgValue
, sgIxs
, obIxs
, nextIxs
, prevIxs
) where

import Control.Applicative ((<$>), (<*>))
import Data.Maybe (fromJust)
import Data.List (groupBy, sort)
import Data.Function (on)
import Data.Binary
import qualified Data.Vector.Generic.Base as G
import qualified Data.Vector.Generic.Mutable as G
import qualified Data.Set as Set
import qualified Data.Map as M
import qualified Data.Vector.Unboxed as U
import qualified Data.Vector as V
import qualified Data.Number.LogFloat as L
import           Data.Vector.Unboxed.Deriving

import Data.CRF.Chain1.Constrained.Feature
import Data.CRF.Chain1.Constrained.Dataset.Internal hiding (fromList)
import qualified Data.CRF.Chain1.Constrained.Dataset.Internal as A

-- | A feature index.  To every model feature a unique index is assigned.
newtype FeatIx = FeatIx { unFeatIx :: Int }
    deriving ( Show, Eq, Ord, Binary )
derivingUnbox "FeatIx" [t| FeatIx -> Int |] [| unFeatIx |] [| FeatIx |]

-- | A label and a feature index determined by that label.
type LbIx   = (Lb, FeatIx)

dummyFeatIx :: FeatIx
dummyFeatIx = FeatIx (-1)
{-# INLINE dummyFeatIx #-}

isDummy :: FeatIx -> Bool
isDummy (FeatIx ix) = ix < 0
{-# INLINE isDummy #-}

notDummy :: FeatIx -> Bool
notDummy = not . isDummy
{-# INLINE notDummy #-}

-- | The model is actually a map from features to their respective potentials,
-- but for the sake of efficiency the internal representation is more complex.
data Model = Model {
    -- | Value (potential) of the model for feature index.
      values    :: U.Vector Double
    -- | A map from features to feature indices
    , ixMap     :: M.Map Feature FeatIx
    -- | A default set of labels.  It is used on sentence positions for which
    -- no constraints are assigned.
    , r0        :: AVec Lb
    -- | Singular feature index for the given label.  Index is equall to -1
    -- if feature is not present in the model.
    , sgIxsV 	:: U.Vector FeatIx
    -- | Set of labels for the given observation which, together with the
    -- observation, constitute an observation feature of the model. 
    , obIxsV    :: V.Vector (AVec LbIx)
    -- | Set of ,,previous'' labels for the value of the ,,current'' label.
    -- Both labels constitute a transition feature present in the the model.
    , prevIxsV  :: V.Vector (AVec LbIx)
    -- | Set of ,,next'' labels for the value of the ,,current'' label.
    -- Both labels constitute a transition feature present in the the model.
    , nextIxsV  :: V.Vector (AVec LbIx) }

instance Binary Model where
    put crf = do
        put $ values crf
        put $ ixMap crf
        put $ r0 crf
        put $ sgIxsV crf
        put $ obIxsV crf
        put $ prevIxsV crf
        put $ nextIxsV crf
    get = Model <$> get <*> get <*> get <*> get <*> get <*> get <*> get

-- | Construct CRF model from the associations list.  We assume that
-- the set of labels is of the {0, 1, .. 'lbMax'} form and, similarly,
-- the set of observations is of the {0, 1, .. 'obMax'} form.
-- There should be no repetition of features in the input list.
-- TODO: We can change this function to take M.Map Feature Double.
fromList :: Ob -> Lb -> [(Feature, Double)] -> Model
fromList obMax' lbMax' fs =
    let _ixMap = M.fromList $ zip
            (map fst fs)
            (map FeatIx [0..])
    
        sFeats = [feat | (feat, _val) <- fs, isSFeat feat]
        tFeats = [feat | (feat, _val) <- fs, isTFeat feat]
        oFeats = [feat | (feat, _val) <- fs, isOFeat feat]

        obMax = unOb obMax'
        lbMax = unLb lbMax'
        _r0   = A.fromList (map Lb [0 .. lbMax])
        -- obMax = (unOb . maximum . Set.toList . obSet) (map fst fs)
        -- lbs   = (Set.toList . lbSet) (map fst fs)
        -- lbMax = (unLb . maximum) lbs
        -- _r0   = A.fromList lbs
        
        _sgIxsV = sgVects lbMax
            [ (unLb x, featToJustIx crf feat)
            | feat@(SFeature x) <- sFeats ]

        _prevIxsV = adjVects lbMax
            [ (unLb x, (y, featToJustIx crf feat))
            | feat@(TFeature x y) <- tFeats ]

        _nextIxsV = adjVects lbMax
            [ (unLb y, (x, featToJustIx crf feat))
            | feat@(TFeature x y) <- tFeats ]

        _obIxsV = adjVects obMax
            [ (unOb o, (x, featToJustIx crf feat))
            | feat@(OFeature o x) <- oFeats ]

        -- | Adjacency vectors.
        adjVects n xs =
            V.replicate (n + 1) (A.fromList []) V.// update
          where
            update = map mkVect $ groupBy ((==) `on` fst) $ sort xs
            mkVect (y:ys) = (fst y, A.fromList $ map snd (y:ys))
            mkVect [] = error "mkVect: null list"

        sgVects n xs = U.replicate (n + 1) dummyFeatIx U.// xs

        _values = U.replicate (length fs) 0.0
            U.// [ (featToJustInt crf feat, val)
                 | (feat, val) <- fs ]
        crf = Model _values _ixMap _r0 _sgIxsV _obIxsV _prevIxsV _nextIxsV
    in  crf

-- -- | Compute the set of observations.
-- obSet :: [Feature] -> Set.Set Ob
-- obSet =
--     Set.fromList . concatMap toObs
--   where
--     toObs (OFeature o _) = [o]
--     toObs _              = []
-- 
-- -- | Compute the set of labels.
-- lbSet :: [Feature] -> Set.Set Lb
-- lbSet =
--     Set.fromList . concatMap toLbs
--   where
--     toLbs (SFeature x)   = [x]
--     toLbs (OFeature _ x) = [x]
--     toLbs (TFeature x y) = [x, y]

-- | Construct the model from the list of features.  All parameters will be
-- set to 0.  There can be repetitions in the input list.
-- We assume that the set of labels is of the {0, 1, .. 'lbMax'} form and,
-- similarly, the set of observations is of the {0, 1, .. 'obMax'} form.
mkModel :: Ob -> Lb -> [Feature] -> Model
mkModel obMax lbMax fs =
    let fSet = Set.fromList fs
        fs'  = Set.toList fSet
        vs   = replicate (Set.size fSet) 0.0
    in  fromList obMax lbMax (zip fs' vs)

-- | Model potential defined for the given feature interpreted as a
-- number in logarithmic domain.
valueL :: Model -> FeatIx -> L.LogFloat
valueL crf (FeatIx i) = L.logToLogFloat (values crf U.! i)
{-# INLINE valueL #-}

-- | Determine index for the given feature.
featToIx :: Model -> Feature -> Maybe FeatIx
featToIx crf feat = M.lookup feat (ixMap crf)
{-# INLINE featToIx #-}

-- | Determine index for the given feature.  Throw error when
-- the feature is not a member of the model. 
featToJustIx :: Model -> Feature -> FeatIx
featToJustIx _crf = fromJust . featToIx _crf
{-# INLINE featToJustIx #-}

-- | Determine index for the given feature and return it as an integer.
-- Throw error when the feature is not a member of the model.
featToJustInt :: Model -> Feature -> Int
featToJustInt _crf = unFeatIx . featToJustIx _crf
{-# INLINE featToJustInt #-}

-- | Potential value (in log domain) of the singular feature with the
-- given label.  The value defaults to 1 (0 in log domain) when the feature
-- is not a member of the model.
sgValue :: Model -> Lb -> L.LogFloat
sgValue crf (Lb x) = 
    case unFeatIx (sgIxsV crf U.! x) of
        -- TODO: Is the value correct?
        -1 -> L.logToLogFloat (0 :: Float)
        ix -> L.logToLogFloat (values crf U.! ix)

-- | List of labels which can be located on the first position of
-- a sentence together with feature indices determined by them.
sgIxs :: Model -> [LbIx]
sgIxs crf
    = filter (notDummy . snd)
    . zip (map Lb [0..])
    . U.toList $ sgIxsV crf
{-# INLINE sgIxs #-}

-- | List of labels which constitute a valid feature in combination with
-- the given observation accompanied by feature indices determined by
-- these labels.
obIxs :: Model -> Ob -> AVec LbIx
obIxs crf x = obIxsV crf V.! unOb x
{-# INLINE obIxs #-}

-- | List of ,,next'' labels which constitute a valid feature in combination
-- with the ,,current'' label accompanied by feature indices determined by
-- ,,next'' labels.
nextIxs :: Model -> Lb -> AVec LbIx
nextIxs crf x = nextIxsV crf V.! unLb x
{-# INLINE nextIxs #-}

-- | List of ,,previous'' labels which constitute a valid feature in
-- combination with the ,,current'' label accompanied by feature indices
-- determined by ,,previous'' labels.
prevIxs :: Model -> Lb -> AVec LbIx
prevIxs crf x = prevIxsV crf V.! unLb x
{-# INLINE prevIxs #-}
