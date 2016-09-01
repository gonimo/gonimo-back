{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE RankNTypes #-}
module Gonimo.Server.Auth where

import           Control.Exception             (SomeException)
import           Control.Lens
import           Control.Monad                 (unless)
import           Control.Monad.Freer           (Eff, Member)
import           Control.Monad.Freer.Exception (Exc (..))
import           Control.Monad.Freer.Reader    (Reader (..), ask)
import           Database.Persist              (Entity (..), Key)
import           Gonimo.Server.DbEntities
import           Gonimo.Server.Effects
import           Gonimo.Server.Error

data AuthData = AuthData { _accountEntity   :: Entity Account
                         -- Usually just one ore two - so using list lookup
                         -- should be fine.
                         , _allowedFamilies :: [FamilyId]
                         , _clientEntity    :: Entity Client
                         }
$(makeLenses ''AuthData)

type AuthReader = Reader AuthData
type AuthReaderMember r = Member AuthReader r

type AuthServerConstraint r = (AuthReaderMember r, ServerConstraint r)
type AuthServerEffects = Eff '[AuthReader, Exc SomeException, Server]


askAccountId :: AuthReaderMember r => Eff r (Key Account)
askAccountId = entityKey . _accountEntity <$> ask

authView :: AuthReaderMember r => Getter AuthData a -> Eff r a
authView g = (^. g) <$> ask

clientKey :: AuthData -> Key Client
clientKey = entityKey . _clientEntity

isFamilyMember :: FamilyId -> AuthData -> Bool
isFamilyMember fid = (fid `elem`) . _allowedFamilies

isClient :: ClientId -> AuthData -> Bool
isClient clientId = (== clientId) . entityKey . _clientEntity

isAccount :: AccountId -> AuthData -> Bool
isAccount accountId = (== accountId) . entityKey . _accountEntity

authorize :: Member (Exc SomeException) r => (a -> Bool) -> a -> Eff r ()
authorize check x = unless (check x) (throwServer Forbidden)

authorizeJust :: Member (Exc SomeException) r => (a -> Maybe b) -> a -> Eff r b
authorizeJust check x = fromMaybeErr Forbidden . check $ x

authorizeAuthData :: (Member (Exc SomeException) r, AuthReaderMember r) => (AuthData -> Bool) -> Eff r ()
authorizeAuthData check = authorize check =<< ask
