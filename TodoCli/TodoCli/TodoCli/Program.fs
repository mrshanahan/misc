// Learn more about F# at http://fsharp.org

open System

let square x = x * x

type Todo = { description: string; notes: string; status: string }

let nTodo d n s = { description = d; status = s; notes = n }

let todos = [
    nTodo "Get groceries"       "TODO"        "Bananas, foobars, beef"
    nTodo "Fix bike"            "IN PROGRESS" ""
    nTodo "Do some other thing" "COMPLETE"    "Good job!"
]

//let buildTable ts =
//    let maxDesc = List.maxBy 
//    let header = 

[<EntryPoint>]
let main argv =
    printfn "TODO        STATUS         NOTES"
    printfn "%d squared is %d!" 12 (square 12)
    0 // return an integer exit code
