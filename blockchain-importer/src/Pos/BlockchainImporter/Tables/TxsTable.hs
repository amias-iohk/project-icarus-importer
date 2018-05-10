{-# LANGUAGE Arrows                #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE TemplateHaskell       #-}

module Pos.BlockchainImporter.Tables.TxsTable
  ( -- * Data manipulation
    insertTx
  , deleteTx
  ) where

import           Control.Monad (void)
import           Data.Profunctor.Product.TH (makeAdaptorAndInstance)
import qualified Database.PostgreSQL.Simple as PGS
import           Opaleye
import           Pos.BlockchainImporter.Core (TxExtra (..))
import qualified Pos.BlockchainImporter.Tables.TxDetailsTable as TDT (insertTxDetails)
import           Pos.BlockchainImporter.Tables.Utils (hashToString)
import           Pos.Core (timestampToUTCTimeL)
import           Pos.Core.Txp (Tx (..))
import           Pos.Crypto (hash)
import           Universum

data TxRowPoly a b c = TxRow { trHash     :: a
                             , trBlockNum :: b
                             , trTime     :: c
                             } deriving (Show)

type TxRowPGW = TxRowPoly (Column PGText) (Column (Nullable PGInt8)) (Column (Nullable PGTimestamptz))
type TxRowPGR = TxRowPoly (Column PGText) (Column (Nullable PGInt8)) (Column (Nullable PGTimestamptz))

$(makeAdaptorAndInstance "pTxs" ''TxRowPoly)

txsTable :: Table TxRowPGW TxRowPGR
txsTable = Table "txs" (pTxs TxRow { trHash     = required "hash"
                                   , trBlockNum = required "block_num"
                                   , trTime     = required "time"
                                   })

-- | Inserts a given Tx into the Tx history tables.
insertTx :: PGS.Connection -> Tx -> TxExtra -> Word64 -> IO ()
insertTx conn tx txExtra blockHeight = PGS.withTransaction conn $ do
  insertTxHeader conn tx txExtra blockHeight
  TDT.insertTxDetails conn tx txExtra

-- | Inserts the basic info of a given Tx into the master Tx history table.
insertTxHeader :: PGS.Connection -> Tx -> TxExtra -> Word64 -> IO ()
insertTxHeader conn tx txExtra blockHeight = void $ runInsertMany conn txsTable [row]
  where
    row = TxRow { trHash     = pgString $ hashToString (hash tx)
                , trBlockNum = toNullable $ pgInt8 $ fromIntegral blockHeight
                , trTime     = maybeToNullable utcTime
                }
    utcTime = pgUTCTime . (^. timestampToUTCTimeL) <$> teReceivedTime txExtra

-- | Deletes a Tx by Tx hash from the Tx history tables.
deleteTx :: PGS.Connection -> Tx -> IO ()
deleteTx conn tx = void $ runDelete conn txsTable $ \row -> trHash row .== txHash
  where
    txHash = pgString $ hashToString (hash tx)