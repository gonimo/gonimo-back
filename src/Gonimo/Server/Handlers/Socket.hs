{-# LANGUAGE Unsafe #-}
module Gonimo.Server.Handlers.Socket where

import           Control.Applicative                  ((<|>))
import           Control.Monad.Trans.Maybe            (runMaybeT)
import           Data.Proxy                           (Proxy (..))
import           Data.Text                            (Text)
import           Gonimo.Server.Auth                   as Auth
import           Gonimo.Server.Effects
import           Gonimo.Server.Error
import qualified Gonimo.Server.State.MessageBox       as MsgBox
import           Gonimo.Server.State.Types
import           Gonimo.Server.Types
import           Gonimo.WebAPI                        (ReceiveChannelR,
                                                       ReceiveMessageR)
import           Servant.API                          ((:>))
import           Servant.Subscriber                   (Event (ModifyEvent))
import           Control.Monad.Trans.Class            (lift)
import           Gonimo.Server.Db.Entities            (FamilyId, DeviceId)

-- | Create a channel for communication with  a baby station
--
--   The baby station must call receiveChannel within a given timeout,
--   this handler will only return a secret if the baby station did so,
--   otherwise an error is thrown (not found - `NoSuchSocket`)
createChannel :: (AuthReader m, MonadServer m)
              => FamilyId -> DeviceId -> DeviceId -> m Secret
createChannel familyId toId fromId = do
  authorizeAuthData (isFamilyMember familyId)
  authorizeAuthData ((fromId ==) . deviceKey)

  secret <- generateSecret
  updateFamilyRetryEff SocketBusy familyId $ MsgBox.setData channelSecrets toId (fromId, secret)

  notify ModifyEvent endpoint (\f -> f familyId toId)

  waitForReaderEff NoSuchSocket familyId toId channelSecrets
  return secret
 where
   endpoint :: Proxy ("socket" :> ReceiveChannelR)
   endpoint = Proxy


receiveChannel :: (AuthReader m, MonadServer m)
               => FamilyId -> DeviceId -> m (Maybe ChannelRequest)
-- in this request @to@ is the one receiving the secret
receiveChannel familyId toId = do
    authorizeAuthData (isFamilyMember familyId)
    authorizeAuthData ((toId ==) . deviceKey)

    fmap fst . MsgBox.getData toId . _channelSecrets <$> getFamilyEff familyId

deleteChannelRequest :: (AuthReader m, MonadServer m)
                        =>  FamilyId -> DeviceId -> DeviceId -> Secret -> m ()
deleteChannelRequest familyId toId fromId secret = do
    authorizeAuthData (isFamilyMember familyId)
    authorizeAuthData ((toId ==) . deviceKey)

    let chanRequest = (fromId, secret)
    _ :: Maybe () <- runMaybeT $ do
      let markRead = mayUpdateFamilyEff familyId $ MsgBox.markRead channelSecrets toId chanRequest
      markRead <|> lift (throwServer (ChannelAlreadyGone chanRequest))
    pure ()

putMessage :: forall m. (AuthReader m, MonadServer m)
           => FamilyId -> DeviceId -> DeviceId -> Secret -> [Text] -> m ()
putMessage familyId fromId toId secret txt = do
    authorizeAuthData (isFamilyMember familyId)
    authorizeAuthData ((fromId ==) . deviceKey)

    let key = (fromId, toId, secret)
    updateFamilyRetryEff ChannelBusy familyId $ MsgBox.setData channelData key txt

    notify ModifyEvent endpoint (\f -> f familyId fromId toId secret)

    waitForReaderEff NoSuchChannel familyId key channelData
  where

   endpoint :: Proxy ("socket" :> ReceiveMessageR)
   endpoint = Proxy


receiveMessage :: (AuthReader m, MonadServer m)
               => FamilyId -> DeviceId -> DeviceId -> Secret -> m (Maybe (MessageNumber, [Text]))
receiveMessage familyId fromId toId secret = do
  authorizeAuthData (isFamilyMember familyId)
  authorizeAuthData ((toId ==) . deviceKey)

  MsgBox.getData (fromId, toId, secret) . _channelData <$> getFamilyEff familyId

deleteMessage :: (AuthReader m, MonadServer m) => FamilyId -> DeviceId -> DeviceId -> Secret
                -> MessageNumber -> m ()
deleteMessage familyId fromId toId secret num = do
    let key = (fromId, toId, secret)
    _ :: Maybe () <-runMaybeT $ do
      let markRead = mayUpdateFamilyEff familyId $ MsgBox.markRead channelData key num
      markRead <|> lift (throwServer (MessageAlreadyGone num))
    pure ()
