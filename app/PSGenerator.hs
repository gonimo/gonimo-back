{-# LANGUAGE OverloadedStrings #-}
import           Language.PureScript.Bridge

import           Control.Lens
import           Data.Proxy
import           GHC.Generics
import           Servant.PureScript

import           Gonimo.CodeGen.TypeBridges
import           Gonimo.Server.Db.Entities
import           Gonimo.Server.Types
import           Gonimo.Server.State.Types (SessionId, MessageNumber)
import           Gonimo.Server.Error
import           Gonimo.WebAPI
import           Gonimo.WebAPI.Types as Client

data GonimoBridge

instance HasBridge GonimoBridge where
  languageBridge _ = buildBridge gonimoBridge


gonimoProxy :: Proxy GonimoBridge
gonimoProxy = Proxy

data TestTypeConstructor m a = TestTypeConstructor (m a) deriving Generic

myTypes :: [SumType 'Haskell]
myTypes = [ mkSumType (Proxy :: Proxy Client.AuthData)
          , mkSumType (Proxy :: Proxy Account)
          , mkSumType (Proxy :: Proxy Client.InvitationInfo)
          , mkSumType (Proxy :: Proxy Client.InvitationReply)
          , mkSumType (Proxy :: Proxy ServerError)
          , mkSumType (Proxy :: Proxy AuthToken)
          , mkSumType (Proxy :: Proxy Device)
          , mkSumType (Proxy :: Proxy Coffee)
          , mkSumType (Proxy :: Proxy Invitation)
          , mkSumType (Proxy :: Proxy InvitationDelivery)
          , mkSumType (Proxy :: Proxy SendInvitation)
          , mkSumType (Proxy :: Proxy DeviceType)
          , mkSumType (Proxy :: Proxy Family)
          , mkSumType (Proxy :: Proxy DeviceInfo)
          , mkSumType (Proxy :: Proxy SessionId)
          , mkSumType (Proxy :: Proxy MessageNumber)
          , mkSumType (Proxy :: Proxy FamilyName)
          ]

mySettings :: Settings
mySettings = (addReaderParam "Authorization" defaultSettings & apiModuleName .~ "Gonimo.WebAPI") {
  _generateSubscriberAPI = True
  }

main :: IO ()
main = do
  let gonimoFrontPath = "../gonimo-front/src"
  writePSTypes gonimoFrontPath (buildBridge gonimoBridge) myTypes
  writeAPIModuleWithSettings mySettings gonimoFrontPath gonimoProxy gonimoAPI
