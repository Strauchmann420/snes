fun eq x y = (x = y)
fun neq x y = (x <> y)
fun protect (SOME x) _ = x
  | protect NONE f = f ()

signature NUMBER_PARSE = sig
 datatype size = BYTE | WORD | LONG
 datatype reason = VALUE_TOO_LARGE | INVALID_LENGTH | INVALID_CHARS
                 | NONMATCHING_SIZETAG | SIZETAG_TOO_SMALL
 exception Failure of string * reason
 type t = {size: size, value: int}
 val parse : string -> t
end

structure NumberParse: NUMBER_PARSE = struct
 datatype base = DEC | HEX | BIN
 datatype size = BYTE | WORD | LONG
 datatype reason = VALUE_TOO_LARGE | INVALID_LENGTH | INVALID_CHARS
                 | NONMATCHING_SIZETAG | SIZETAG_TOO_SMALL
 exception Failure of string * reason
 type t = {size: size, value: int}

 structure C = StringCvt
 fun numVal base str =
  let fun cvt r = case r of DEC=>C.DEC | HEX=>C.HEX | BIN=>C.BIN
  in case Int.scan (cvt base) List.getItem str
      of NONE => NONE
       | SOME (n,[]) => SOME n
       | SOME (_,_) => NONE
  end

 fun split s =
     let fun rest (p,soFar) [] = (p, rev soFar, NONE)
           | rest (p,soFar) (#"b"::[]) = (p, rev soFar, SOME BYTE)
           | rest (p,soFar) (#"w"::[]) = (p, rev soFar, SOME WORD)
           | rest (p,soFar) (#"l"::[]) = (p, rev soFar, SOME LONG)
           | rest (p,soFar) (x::xs) = rest (p,x::soFar) xs
         fun prefix (#"%"::xs) = rest (BIN,[]) xs
           | prefix (#"$"::xs) = rest (HEX,[]) xs
           | prefix xs = rest (DEC,[]) xs
     in case prefix s of (a,b,c) => (a,List.filter (neq #":") b,c)
     end

 fun sizeInBytes x = case x of BYTE=>1 | WORD=>2 | LONG=>3
 fun smallestFit v =
  if v <= 0xFF then SOME BYTE
  else if v <= 0xFFFF then SOME WORD
  else if v <= 0xFFFFFF then SOME LONG
  else NONE

 fun parse str =
  let fun fail r = raise (Failure (str,r))
      val (base,content,sizeTag) = split (explode str)
      val impliedSize =
       case (base, length content)
        of (BIN,8) => SOME BYTE | (HEX,2) => SOME BYTE
         | (BIN,16) => SOME WORD | (HEX,4) => SOME WORD
         | (BIN,24) => SOME LONG | (HEX,6) => SOME LONG
         | (BIN,_) => fail INVALID_LENGTH
         | (HEX,_) => fail INVALID_LENGTH
         | (DEC,_) => NONE
      val value = protect (numVal base content) (fn()=>fail INVALID_CHARS)
      val smallestFit = protect (smallestFit value) (fn()=>fail VALUE_TOO_LARGE)
      val size =
       case (impliedSize, sizeTag)
        of (NONE, SOME x) => x
         | (NONE, NONE) => smallestFit
         | (SOME x, SOME y) => if x=y then x else fail NONMATCHING_SIZETAG
         | (SOME x, NONE) => x
  in if ((sizeInBytes smallestFit) > (sizeInBytes size))
     then fail SIZETAG_TOO_SMALL
     else {size=size, value=value}:t
  end
end

structure N = NumberParse

val f = N.parse

;
; f "254w"
;
