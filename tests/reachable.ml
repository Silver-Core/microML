(* inc is a redundant function definition, not used in the program. It should compile but
 * with a warning of an unused function *)

let double x = x * 2
let compose x y = \z -> x (y z)
let inc x = x + 1

let main = compose double double 2