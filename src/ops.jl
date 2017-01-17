
# ops.jl - overloaded operators for constucting symbolic expressions.
#
# A couple of examples:
#
#    :x ⊕ :y      ==>  :(x + y)
#    2 ⊗ :(x ⊕ y) ==>  :(2 * (x + y))

# import Base: +, -, *, /, .+, .-, .*, ./

# ⊕(ex::Symbolic, v::Numeric) = :($ex + $v)
# ⊕(v::Numeric, ex::Symbolic) = :($v + $ex)
# ⊕(ex1::Symbolic, ex2::Symbolic) = :($ex1 + $ex2)
# ⊕(x, y) = x + y

# (-)(ex::Symbolic, v::Numeric) = :($ex - $v)
# (-)(v::Numeric, ex::Symbolic) = :($v - $ex)
# (-)(ex1::Symbolic, ex2::Symbolic) = :($ex1 - $ex2)

# ⊗(ex::Symbolic, v::Numeric) = :($ex * $v)
# ⊗(v::Numeric, ex::Symbolic) = :($v * $ex)
# ⊗(ex1::Symbolic, ex2::Symbolic) = :($ex1 * $ex2)
# ⊗(x, y) = x * y

# (/)(ex::Symbolic, v::Numeric) = :($ex / $v)
# (/)(v::Numeric, ex::Symbolic) = :($v / $ex)
# (/)(ex1::Symbolic, ex2::Symbolic) = :($ex1 / $ex2)

# elementwise operations

⊕(ex::Symbolic, v::Numeric) = :($ex .+ $v)
⊕(v::Numeric, ex::Symbolic) = :($v .+ $ex)
⊕(ex1::Symbolic, ex2::Symbolic) = :($ex1 .+ $ex2)
⊕(x, y) = x .+ y

# (.-)(ex::Symbolic, v::Numeric) = :($ex .- $v)
# (.-)(v::Numeric, ex::Symbolic) = :($v .- $ex)
# (.-)(ex1::Symbolic, ex2::Symbolic) = :($ex1 .- $ex2)

⊗(ex::Symbolic, v::Numeric) = :($ex .* $v)
⊗(v::Numeric, ex::Symbolic) = :($v .* $ex)
⊗(ex1::Symbolic, ex2::Symbolic) = :($ex1 .* $ex2)
⊗(x, y) = x .* y

# (./)(ex::Symbolic, v::Numeric) = :($ex ./ $v)
# (./)(v::Numeric, ex::Symbolic) = :($v ./ $ex)
# (./)(ex1::Symbolic, ex2::Symbolic) = :($ex1 ./ $ex2)

## Note: this is also correct, but generates more ugly expressions
##
## for op in [:(+), :(-), :(*), :(/)]
##     for T in [Number, Array]
##         @eval begin
##             Base.$(op)(ex::Symbolic, v::$T) = :(($$op)($ex,$v))
##             Base.$(op)(v::$T, ex::Symbolic) = :(($$op)($v,$ex))
##             Base.$(op)(ex1::Symbolic, ex2::Symbolic) = :(($$op($ex1,$ex2)))
##         end
##     end
## end

