(* HOF *)
let id x = x;
let const x y = x;
let flip f = \x y -> f y x;
let ap f x = f (f x);
let length xs = if (xs == []) then 0 else (1 + (length (tail xs)));
let drop n xs = if (n == 0) then xs else (drop (n-1) (tail xs));
-- let take n xs = if (n == 0) then [] else ((head xs) : (take (n-1) (tail xs)));
let foldr f acc xs = if (xs == []) then acc else ((f (head xs)) (foldr f acc (tail xs)));
let foldl f acc xs = if (xs == []) then acc else (foldl f (f acc (head xs)) (tail xs));

(* print functions *)
let show x = x;     (* this is just a synonym for id *)

(* maths function *)
let sum xs = if (xs == []) then 0 else ((head xs) + (sum (tail xs)));
-- let sum xs = foldl + 0 xs
let product xs = if (xs == []) then 1 else ((head xs) * (product (tail xs)));
-- let product xs = foldl * 1 xs
let abs x = if (x < 0) then (x * -1) else x;
let max a b = if (a < b) then b else a;
let min a b = if (a < b) then a else b;
let square a = a * a;
let negate x = if (x < 0) then (abs x) else (x * -1);

-- tests --
let zero? x = if (x == 0) then true else false;
let odd? x = if (x % 2 == 1) then true else false;
let even? x = if (x % 2 == 0) then true else false;
let positive? x = if (x > 0) then true else false;
let negative? x = if (x < 0) then true else false;

-- we need to have lets and where to hide definitions
let gcd' a b = if (b == 0) then a else (gcd' b (a % b));
let gcd a b = gcd' (abs a) (abs b);
