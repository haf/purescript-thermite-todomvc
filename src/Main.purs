module Main (main) where

import Prelude

import Data.Tuple
import Data.Maybe (fromMaybe)
import Data.List ( List(..)
                 , (:)
                 , deleteAt
                 , updateAt
                 , filter
                 , fromList
                 , length
                 , range
                 , singleton
                 , zip
                 )

import Control.Plus (empty)

import Optic.Core
import Optic.Monad ((#~))
import Optic.Index (ix)
import Optic.Monad.Setter ((.=), (++=))

import qualified Thermite as T
import qualified Thermite.Html as T
import qualified Thermite.Html.Elements as T
import qualified Thermite.Html.Attributes as A
import qualified Thermite.Events as T
import qualified Thermite.Action as T
import qualified Thermite.Types as T

type Index = Int

data Action
  = NewItem String
  | RemoveItem Index
  | SetEditText String
  | SetCompleted Index Boolean
  | SetFilter Filter
  | DoNothing

data Item = Item String Boolean

data Filter = All | Active | Completed

instance eqFilter :: Eq Filter where
  eq All       All       = true
  eq Active    Active    = true
  eq Completed Completed = true
  eq _         _         = false

showFilter :: Filter -> String
showFilter All = "All"
showFilter Active = "Active"
showFilter Completed = "Completed"

data State = State
  { items       :: List Item
  , editText    :: String
  , filter      :: Filter
  }

_State :: LensP State { items :: _, editText :: _, filter :: _ }
_State f (State st) = State <$> f st

items :: forall r. LensP { items :: _ | r } _
items f st = f st.items <#> \i -> st { items = i }

editText :: forall r. LensP { editText :: _ | r } _
editText f st = f st.editText <#> \i -> st { editText = i }

filter_ :: forall r. LensP { filter :: _ | r } _
filter_ f st = f st.filter <#> \i -> st { filter = i }

itemBoolean :: LensP Item Boolean
itemBoolean f (Item str b) = Item str <$> f b

foreign import getValue :: forall event. event -> String

foreign import getChecked :: T.FormEvent -> Boolean

foreign import getKeyCode :: T.KeyboardEvent -> Int

handleKeyPress :: T.KeyboardEvent -> Action
handleKeyPress e = case getKeyCode e of
                     13 -> NewItem $ getValue e
                     27 -> SetEditText ""
                     _  -> DoNothing

handleChangeEvent :: T.FormEvent -> Action
handleChangeEvent e = SetEditText (getValue e)

handleCheckEvent :: Index -> T.FormEvent -> Action
handleCheckEvent index e = SetCompleted index (getChecked e)

initialState :: State
initialState = State { items: empty, editText: "", filter: All }

applyFilter :: Filter -> Item -> Boolean
applyFilter All       _ = true
applyFilter Active    (Item _ b) = not b
applyFilter Completed (Item _ b) = b

render :: T.Render _ State _ Action
render ctx (State st) _ _ =
  T.div (A.className "container") [ title, filters, items ]
  where
  title :: T.Html _
  title = T.h1' [ T.text "todos" ]

  items :: T.Html _
  items = T.table (A.className "table table-striped") 
                  [ T.thead' [ T.th (A.className "col-md-1") []
                             , T.th (A.className "col-md-10") [ T.text "Description" ]
                             , T.th (A.className "col-md-1") [] 
                             ]
                  , T.tbody' (fromList (newItem : (map item <<< filter (applyFilter st.filter <<< fst) $ zip st.items (range 0 $ length st.items))))
                  ]

  newItem :: T.Html _
  newItem = T.tr' [ T.td' []
                  , T.td' [ T.input (A.className "form-control"
                                     <> A.placeholder "Create a new task"
                                     <> A.value st.editText
                                     <> T.onKeyUp ctx handleKeyPress
                                     <> T.onChange ctx handleChangeEvent)
                                    []
                          ]
                  , T.td' []
                  ]

  item :: Tuple Item Index -> T.Html _
  item (Tuple (Item name completed) index) =
    T.tr' <<< map (T.td' <<< pure) $ 
          [ T.input (A._type "checkbox"
                     <> A.className "checkbox"
                     <> A.checked (if completed then "checked" else "")
                     <> A.title "Mark as completed"
                     <> T.onChange ctx (handleCheckEvent index))
                    []
          , T.text name
          , T.a (A.className "btn btn-danger pull-right"
                 <> A.title "Remove item"
                 <> T.onClick ctx \_ -> RemoveItem index)
                [ T.text "✖" ]
          ]

  filters :: T.Html _
  filters = T.div (A.className "btn-group") (filter_ <$> [All, Active, Completed])

  filter_ :: Filter -> T.Html _
  filter_ f = T.button (A.className (if f == st.filter then "btn toolbar active" else "btn toolbar")
                        <> T.onClick ctx (\_ -> SetFilter f)
                       )
                       [ T.text (showFilter f) ]

performAction :: T.PerformAction _ State _ Action
performAction _ action = T.modifyState (updateState action)
  where
  updateState :: Action -> State -> State
  updateState (NewItem s)        = \st -> st #~ do _State .. items ++= singleton (Item s false)
                                                   _State .. editText .= ""
  updateState (RemoveItem i)     = over (_State .. items) (\xs -> fromMaybe xs (deleteAt i xs))
  updateState (SetEditText s)    = _State .. editText .~ s
  updateState (SetCompleted i c) = _State .. items .. ix i .. itemBoolean .~ c
  updateState (SetFilter f)      = _State .. filter_ .~ f
  updateState DoNothing          = id

spec :: T.Spec _ State _ Action
spec = T.simpleSpec initialState performAction render

main = do
  let component = T.createClass spec
  T.render component {}
