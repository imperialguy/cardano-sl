{-# LANGUAGE FlexibleContexts #-}

-- | Logic of blocks processing.

module Pos.Block.Logic
       ( ClassifyHeaderRes (..)
       , applyBlock
       , classifyNewHeader
       , classifyHeaders
       , verifyBlock
       ) where

import           Control.Lens           ((^.))
import           Control.Monad.Catch    (onException)
import           Data.Default           (Default (def))
import qualified Data.Text              as T
import           Serokell.Util.Verify   (VerificationRes (..))
import           Universum

import           Pos.Context            (putBlkSemaphore, takeBlkSemaphore)
import qualified Pos.Modern.DB          as DB
import           Pos.Modern.Txp.Storage (txApplyBlocks, txVerifyBlocks)
import           Pos.Slotting           (getCurrentSlot)
import           Pos.Types              (Block, BlockHeader, VerifyHeaderParams (..),
                                         blockHeader, difficultyL, headerHash, headerSlot,
                                         prevBlockL, verifyHeader, vhpVerifyConsensus)
import           Pos.WorkMode           (WorkMode)

-- | Result of header classification.
data ClassifyHeaderRes
    = CHRcontinues      -- ^ Header continues our main chain.
    | CHRalternative    -- ^ Header continues alternative chain which
                        -- is more difficult.
    | CHRuseless !Text  -- ^ Header is useless.
    | CHRinvalid !Text  -- ^ Header is invalid.

-- | Make `ClassifyHeaderRes` from list of error messages using
-- `CHRinvalid` constructor. Intended to be used with `VerificationRes`.
-- Note: this version forces computation of all error messages. It can be
-- made more efficient but less informative by using head, for example.
mkCHRinvalid :: [Text] -> ClassifyHeaderRes
mkCHRinvalid = CHRinvalid . T.intercalate "; "

-- | Classify new header announced by some node. Result is represented
-- as ClassifyHeaderRes type.
classifyNewHeader
    :: (WorkMode ssc m)
    => BlockHeader ssc -> m ClassifyHeaderRes
-- Genesis headers seem useless, we can create them by ourselves.
classifyNewHeader (Left _) = pure $ CHRuseless "genesis header is useless"
classifyNewHeader (Right header) = do
    curSlot <- getCurrentSlot
    -- First of all we check whether header is from current slot and
    -- ignore it if it's not.
    if curSlot == header ^. headerSlot
        then classifyNewHeaderDo <$> DB.getTip <*> DB.getTipBlock
        else return $ CHRuseless "header is not for current slot"
  where
    classifyNewHeaderDo tip tipBlock
        -- If header's parent is our tip, we verify it against tip's header.
        | tip == header ^. prevBlockL =
            let vhp =
                    def
                    { vhpVerifyConsensus = True
                    , vhpPrevHeader = Just $ tipBlock ^. blockHeader
                    }
                verRes = verifyHeader vhp (Right header)
            in case verRes of
                   VerSuccess        -> CHRcontinues
                   VerFailure errors -> mkCHRinvalid errors
        -- If header's parent is not our tip, we check whether it's
        -- more difficult than our main chain.
        | tipBlock ^. difficultyL < header ^. difficultyL = CHRalternative
        -- If header can't continue main chain and is not more
        -- difficult than main chain, it's useless.
        | otherwise =
            CHRuseless $
            "header doesn't continue main chain and is not more difficult"

-- | Classify headers received in response to 'GetHeaders' message.
-- • If there are any errors in chain of headers, CHRinvalid is returned.
-- • If chain of headers is a valid continuation of our main chain,
-- CHRcontinues is returned.
-- • If chain of headers forks from our main chain but not too much,
-- CHRalternative is returned.
-- • If chain of headers forks from our main chain too much, CHRuseless
-- is returned, because paper suggests doing so.
classifyHeaders
    :: WorkMode ssc m
    => [BlockHeader ssc] -> m ClassifyHeaderRes
classifyHeaders = notImplemented

-- | Verify block received from network. If parent of this block is
-- not our tip, verification fails. This function checks everything
-- from block, including header, transactions, SSC data.
--
-- TODO: this function should be more complex and most likely take at
-- least list of blocks.
verifyBlock
    :: (WorkMode ssc m)
    => Block ssc -> m VerificationRes
verifyBlock blk = do
    txsVerRes <- txVerifyBlocks (pure blk)
    -- TODO: more checks of course. Consider doing CSL-39 first.
    return txsVerRes

-- | Apply definitely valid block. At this point we must have verified
-- all predicates regarding block (including txs and ssc data checks).
-- This function takes lock on block application and releases it after
-- finishing. It can fail if previous block of applied block differs
-- from stored tip.
--
-- TODO: this function should be more complex and most likely take at
-- least list of blocks.
applyBlock :: (WorkMode ssc m) => Block ssc -> m Bool
applyBlock blk = do
    tip <- takeBlkSemaphore
    let putBack = putBlkSemaphore tip
    let putNew = putBlkSemaphore $ headerHash blk
    if blk ^. prevBlockL == tip
        then True <$ onException (applyBlockDo blk >> putNew) putBack
        else False <$ putBack

applyBlockDo :: (WorkMode ssc m) => Block ssc -> m ()
applyBlockDo blk = do
    -- [CSL-331] Put actual Undo instead of empty list!
    DB.putBlock [] True blk
    txApplyBlocks (pure blk)
