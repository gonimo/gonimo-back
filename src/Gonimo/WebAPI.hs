{-# LANGUAGE OverloadedStrings #-}
-- {-# OPTIONS_GHC -fno-warn-unused-imports #-}
module Gonimo.WebAPI where

import           Data.Proxy
import           Data.Text                       (Text)
import           Gonimo.Server.Db.Entities
import           Gonimo.Server.Types
import           Gonimo.WebAPI.Types             (InvitationInfo,
                                                  InvitationReply)
import qualified Gonimo.WebAPI.Types             as Client
import           Servant.API
import           Servant.API.BrowserHeader
import           Servant.Subscriber.Subscribable
import           Gonimo.Server.State.Types        (SessionId, MessageNumber, ChannelRequest)


type GonimoAPI =
       "accounts"                       :> BrowserHeader "User-Agent" Text :> Post '[JSON] Client.AuthData
  :<|> Header "Authorization" AuthToken :> AuthGonimoAPI
  :<|> "coffee"                         :> Get '[JSON] Coffee

type From    = Capture "fromDevice" DeviceId
type To      = Capture "toDevice"   DeviceId
type Channel = Capture "channelId"  Secret

type AuthGonimoAPI = "invitations"  :> InvitationsAPI
                :<|> "accounts"     :> AccountsAPI
                :<|> "families"     :> FamiliesAPI
                :<|> "socket"       :> SocketAPI
                :<|> "session"     :> SessionAPI


-- invitations API:
type InvitationsAPI = CreateInvitationR
                 :<|> AnswerInvitationR
                 :<|> SendInvitationR
                 :<|> PutInvitationInfoR

type CreateInvitationR = Capture "familyId" FamilyId :> Post '[JSON] (InvitationId, Invitation)

type AnswerInvitationR  =
  Capture "invitationSecret" Secret :> ReqBody '[JSON] InvitationReply :> Delete '[JSON] (Maybe FamilyId)

-- Send an invitation email/telegram message/...
type SendInvitationR    =
  "outbox"                          :> ReqBody '[JSON] Client.SendInvitation :> Post '[JSON] ()

-- | Retrieve information about an invitation and claim it - no other device will
--   no be able to claim or accept this invitation.
type PutInvitationInfoR =
  "info"                            :> Capture "invitationSecret" Secret :> Put '[JSON] InvitationInfo


-- AccountsAPI:
type AccountsAPI = Capture "accountId" AccountId :> AccountAPI
type AccountAPI  = GetAccountFamiliesR

type GetAccountFamiliesR = "families" :> Subscribable :> Get '[JSON] [FamilyId]


-- FamiliesAPI:
type FamiliesAPI = CreateFamilyR
              :<|> Capture "familyId" FamilyId :> FamilyAPI

type CreateFamilyR = Post '[JSON] FamilyId


-- FamilyAPI:
type FamilyAPI = GetFamilyR
            :<|> GetFamilyDevicesR

type GetFamilyR = Subscribable :> Get '[JSON] Family
-- TODO: This list should really be just the ids! Once we get a separate endpoint for retrieving a
-- DeviceInfor for a DeviceId, this _must_ be changed! For all information should only be retrievable from one endpoint - so handling notifications stays easy and efficient!!!
-- Currently if a single device info changes - all clients will refetch the whole list!
type GetFamilyDevicesR = "deviceInfos" :> Subscribable :> Get '[JSON] [(DeviceId, Client.DeviceInfo)]

-- SocketAPI:
type SocketAPI =  CreateChannelR
             :<|> ReceiveChannelR
             :<|> DeleteChannelRequestR
             :<|> PutMessageR
             :<|> ReceiveMessageR
             :<|> DeleteMessageR

-- Socket endpoints:
type CreateChannelR  = Capture "familyId" FamilyId :> To :> ReqBody '[JSON] DeviceId :> PostCreated '[JSON] Secret
type ReceiveChannelR  = Capture "familyId" FamilyId :> To :> Subscribable :> Get '[JSON] (Maybe ChannelRequest)
-- Deletes a channel request, the clients can still use the channel afterwards - as channels don't really exist
type DeleteChannelRequestR  = Capture "familyId" FamilyId :> To :> From :> Channel :> Delete '[JSON] ()

-- Channel endpoint:
type PutMessageR     = Capture "familyId" FamilyId :> From :> To :> Channel :> ReqBody '[JSON] [Text] :> Put '[JSON] ()
type ReceiveMessageR = Capture "familyId" FamilyId :> From :> To :> Channel :> Subscribable :> Get '[JSON] (Maybe (MessageNumber, [Text]))
-- A reader can mark a message as read - the putchannel handler will then remove the message:
type DeleteMessageR = Capture "familyId" FamilyId :> From :> To :> Channel :> "messages" :> Capture "messageNumber" MessageNumber :> Delete '[JSON] ()


-- SessionAPI:
type SessionAPI =  RegisterR
              :<|> UpdateR
              :<|> DeleteR
              :<|> ListDevicesR

-- RegisterR is subscribable although it is a post, it also never changes. But
-- having it subscriable enables us to delegate registration to the subscriber
-- in a pretty elegant way! :-)
type RegisterR    = Capture "familyId" FamilyId :> Capture "deviceId" DeviceId  :> ReqBody '[JSON] DeviceType :> Subscribable :> PostCreated '[JSON] SessionId
type UpdateR      = Capture "familyId" FamilyId :> Capture "deviceId" DeviceId  :> Capture "sessionId" SessionId :> ReqBody '[JSON] DeviceType :> Put '[JSON] ()
type DeleteR      = Capture "familyId" FamilyId :> Capture "deviceId" DeviceId  :> Capture "sessionId" SessionId :> Delete '[JSON] ()
type ListDevicesR = Capture "familyId" FamilyId :> Subscribable :> Get '[JSON] [(DeviceId,DeviceType)]

gonimoAPI :: Proxy GonimoAPI
gonimoAPI = Proxy

authGonimoAPI :: Proxy AuthGonimoAPI
authGonimoAPI = Proxy

invitationsAPI :: Proxy InvitationsAPI
invitationsAPI = Proxy

accountsAPI :: Proxy AccountsAPI
accountsAPI = Proxy

familiesAPI :: Proxy FamiliesAPI
familiesAPI = Proxy

socketAPI :: Proxy SocketAPI
socketAPI = Proxy

gonimoLink :: (IsElem endpoint GonimoAPI, HasLink endpoint) => Proxy endpoint -> MkLink endpoint
gonimoLink = safeLink gonimoAPI
