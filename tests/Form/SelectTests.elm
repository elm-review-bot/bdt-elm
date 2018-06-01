module Form.SelectTests exposing (suite)

import Test exposing (..)
import Fuzz exposing (Fuzzer)
import Expect exposing (Expectation)

import Form.Select as Select


suite : Test
suite =
    describe "Test Stuff"
        [ test "test" test1
        ]


test1 : () -> Expectation
test1 _ =
    Select.init []
        |> Expect.equal (Select.init [])