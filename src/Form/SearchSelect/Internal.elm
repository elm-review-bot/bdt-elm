module Form.SearchSelect.Internal exposing
    ( State, ViewState
    , init, initialViewState
    , Msg, update
    , render
    , reInitialise, reset
    , setDefaultLabel, setToLabel
    , setInitialOption, setSelectedOption, setIsOptionDisabled
    , setIsError, setIsLocked, setIsClearable
    , setId
    , getIsChanged, getIsOpen
    , getSelectedOption, getInitialOption
    , getId
    )

import Html.Styled as Html exposing (..)
import Html.Styled.Lazy exposing (..)
import Html.Styled.Events exposing (..)
import Html.Styled.Attributes exposing (..)

import Browser.Dom as Dom
import Dict
import Task
import Http

import List.Extra as List

import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline as Decode

import Form.Helpers as Form exposing
    ( UpDown (..), onUpDown, onEnter
    , getNextOption, getPreviousOption
    , focusOption
    )
import Html.Styled.Bdt as Html
import Resettable exposing (Resettable)

import Form.SearchSelect.Css as Css


-- MODEL --


type alias State option =
    { isOpen : Bool
    , input : String
    , searchUrl : String
    , isSearching : Bool
    , options : List option
    , optionDecoder : Decoder option
    , selectedOption : Resettable (Maybe option)
    , focusedOption : Maybe option
    }


init : String -> Decoder option -> State option
init searchUrl optionDecoder =
    { isOpen = False
    , input = ""
    , searchUrl = searchUrl
    , isSearching = False
    , options = []
    , optionDecoder = optionDecoder
    , selectedOption = Resettable.init Nothing
    , focusedOption = Nothing
    }


type alias ViewState option =
    { inputMinimum : Int
    , isLocked : Bool
    , isClearable : Bool
    , isError : Bool
    , isOptionDisabled : option -> Bool
    , toLabel : option -> String
    , defaultLabel : String
    , id : Maybe String
    }


initialViewState : (option -> String) -> ViewState option
initialViewState toLabel =
    { inputMinimum = 2
    , isLocked = False
    , isClearable = False
    , isError = False
    , isOptionDisabled = always False
    , toLabel = toLabel
    , defaultLabel = "-- Nothing Selected --"
    , id = Nothing
    }


-- UPDATE --


type Msg option
    = Open
    | Blur
    | UpdateSearchInput Int String
    | Response (Result Http.Error (List option))
    | Select option
    | Clear
    | UpDown (option -> String) UpDown
    | Focus option
    | BlurOption option
    | DomFocus (Result Dom.Error ())


update : Msg option -> State option -> (State option, Cmd (Msg option))
update msg state =

    case msg of
        Open ->
            ({ state | isOpen = True }, Cmd.none)

        Blur ->
            ({ state | isOpen = False, input = "", focusedOption = Nothing }, Cmd.none)

        UpdateSearchInput inputMinimum value ->
            ({ state | input = value, isSearching = shouldSearch inputMinimum value
            }, if shouldSearch inputMinimum value then searchRequest state.searchUrl value state.optionDecoder else Cmd.none)

        Response result ->
            case result of
                Err error ->
                    ({ state | isSearching = False }, Cmd.none)

                Ok options ->
                    ({ state | isSearching = False, options = options, focusedOption = Nothing }, Cmd.none)

        Clear ->
            ({ state | selectedOption = Resettable.update Nothing state.selectedOption }, Cmd.none)

        Select selectedOption ->
            ({ state
                | input = ""
                , selectedOption = Resettable.update (Just selectedOption) state.selectedOption
            }, Cmd.none)

        UpDown toLabel Up ->
            let
                newFocusedOption =
                    getPreviousOption state.options state.focusedOption

            in
                ({ state | focusedOption = newFocusedOption }, focusOption toLabel newFocusedOption DomFocus)

        UpDown toLabel Down ->
            let
                newFocusedOption =
                    getNextOption state.options state.focusedOption

            in
                ({ state | focusedOption = newFocusedOption }, focusOption toLabel newFocusedOption DomFocus)

        Focus option ->
            ({ state | focusedOption = Just option }, Cmd.none)

        BlurOption option ->
            if Just option == state.focusedOption
            then ({ state | focusedOption = Nothing, isOpen = False }, Cmd.none)
            else (state, Cmd.none)

        DomFocus _ ->
            (state, Cmd.none)


-- SEARCH REQUEST --


searchRequest : String -> String -> Decoder option -> Cmd (Msg option)
searchRequest searchUrl input optionDecoder =
    searchResponseDecoder optionDecoder
        |> Http.get (searchUrl ++ input)
        |> Http.send Response


searchResponseDecoder : Decoder option -> Decoder (List option)
searchResponseDecoder optionDecoder =
    Decode.list optionDecoder


-- VIEW --


render : State option -> ViewState option -> Html (Msg option)
render state viewState =

    case state.isOpen of
        False ->
            lazy2 closed state viewState

        True ->
            lazy2 open state viewState


closed : State option -> ViewState option -> Html (Msg option)
closed state viewState =

    div
        [ Css.container ]
        [ input
            [ Css.input viewState.isError viewState.isLocked
            , Css.title (Resettable.getValue state.selectedOption == Nothing)
            , Html.maybeAttribute id viewState.id
            , type_ "text"
            , disabled viewState.isLocked
            , tabindex 0 |> Html.attributeIf (not viewState.isLocked)
            , onFocus Open |> Html.attributeIf (not viewState.isLocked)
            , onClick Open |> Html.attributeIf (not viewState.isLocked)
            , value (state.selectedOption |> Resettable.getValue |> Maybe.map viewState.toLabel |> Maybe.withDefault "" )
            ]
            []
        ]


open : State option -> ViewState option -> Html (Msg option)
open state viewState =

    div
        [ Css.container ]
        [ input
            [ Css.input viewState.isLocked viewState.isError
            , Css.title (Resettable.getValue state.selectedOption == Nothing)
            , id "OPEN_SEARCH_SELECT"
            , type_ "text"
            , placeholder (Maybe.map viewState.toLabel (Resettable.getValue state.selectedOption) |> Maybe.withDefault "")
            , tabindex -1
            , disabled viewState.isLocked
            , onInput <| UpdateSearchInput viewState.inputMinimum
            , onBlur Blur
            , onUpDown <| UpDown viewState.toLabel
            , value state.input
            ]
            []
        , searchResults state viewState
        ]


searchResults : State option -> ViewState option -> Html (Msg option)
searchResults state viewState =

    case shouldSearch viewState.inputMinimum state.input of
        False ->
            infoMessage (InputMinimum viewState.inputMinimum)

        True ->
            case state.isSearching of
                True ->
                    infoMessage Searching

                False ->
                    case List.isEmpty state.options of
                        True ->
                            infoMessage NoResults

                        False ->
                            searchResultList state viewState


type InfoMessage
    = InputMinimum Int
    | Searching
    | NoResults


infoMessage : InfoMessage -> Html (Msg option)
infoMessage message =

    case message of
        InputMinimum int ->
            infoMessageContainer ("please type at least " ++ String.fromInt int ++ " characters to search")

        Searching ->
            infoMessageContainer "searching .."

        NoResults ->
            infoMessageContainer "no results"


infoMessageContainer : String -> Html (Msg option)
infoMessageContainer message =

    div
        [ Css.infoMessage ]
        [ text message ]


searchResultList : State option -> ViewState option -> Html (Msg option)
searchResultList state viewState =

    div
        [ Css.optionList ]
        (List.map (searchResultItem state.focusedOption viewState.toLabel) state.options)


searchResultItem : Maybe option -> (option -> String) -> option -> Html (Msg option)
searchResultItem focusedOption toLabel option =

    div
        [ Css.optionItem (Just option == focusedOption)
        , id <| Form.toHtmlId toLabel option
        -- use onMouseDown over onClick so that it triggers before the onBlur on the input
        , onMouseDown <| Select option
        , onFocus <| Focus option
        , onBlur <| BlurOption option
        , onEnter <| Select option
        ]
        [ text <| toLabel option ]


-- STATE SETTERS --


reInitialise : State option -> State option
reInitialise state =

    { state | selectedOption = Resettable.init (Resettable.getValue state.selectedOption) }


reset : State option -> State option
reset state =

    { state | selectedOption = Resettable.reset state.selectedOption }


setInitialOption : Maybe option -> State option -> State option
setInitialOption selectedOption state =

    { state | selectedOption = Resettable.init selectedOption }


setSelectedOption : Maybe option -> State option -> State option
setSelectedOption selectedOption state =

    { state | selectedOption = Resettable.update selectedOption state.selectedOption }


-- VIEW STATE SETTERS --


setToLabel : (option -> String) -> ViewState option -> ViewState option
setToLabel toLabel viewState =

    { viewState | toLabel = toLabel }


setDefaultLabel : String -> ViewState option -> ViewState option
setDefaultLabel defaultLabel viewState =

    { viewState | defaultLabel = defaultLabel }


setIsOptionDisabled : (option -> Bool) -> ViewState option -> ViewState option
setIsOptionDisabled isOptionDisabled viewState =

    { viewState | isOptionDisabled = isOptionDisabled }


setIsLocked : Bool -> ViewState option -> ViewState option
setIsLocked isLocked viewState =

    { viewState | isLocked = isLocked }


setIsError : Bool -> ViewState option -> ViewState option
setIsError isError viewState =

    { viewState | isError = isError }


setIsClearable : Bool -> ViewState option -> ViewState option
setIsClearable isClearable viewState =

    { viewState | isClearable = isClearable }


setId : String -> ViewState option -> ViewState option
setId id viewState =

    { viewState | id = Just id }


-- GETTERS --


getIsChanged : State option -> Bool
getIsChanged state =

    Resettable.getIsChanged state.selectedOption


getInitialOption : State option -> Maybe option
getInitialOption state =

    Resettable.getInitialValue state.selectedOption


getSelectedOption : State option -> Maybe option
getSelectedOption state =

    Resettable.getValue state.selectedOption


getIsOpen : State option -> Bool
getIsOpen =
    .isOpen


getId : ViewState option -> Maybe String
getId =
    .id


-- HELPERS --


shouldSearch : Int -> String -> Bool
shouldSearch inputMinimum input =
    String.length input >= inputMinimum