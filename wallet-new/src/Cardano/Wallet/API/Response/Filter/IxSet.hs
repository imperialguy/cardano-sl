
{-# LANGUAGE DeriveGeneric #-}
module Cardano.Wallet.API.Response.Filter.IxSet where

import           Cardano.Wallet.API.Request.Filter
import qualified Data.IxSet.Typed as Ix

applyFilter :: IsIndexOf a idx => Ix.IxSet ixs a -> FilterOperation a -> Ix.IxSet ixs a
applyFilter inputData _ = inputData
